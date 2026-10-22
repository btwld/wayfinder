import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'cancellation.dart';

/// An advisory exclusive lock on a file that holds across processes and
/// across the isolates of one process.
///
/// On macOS, Linux and other POSIX systems it is `flock(2)` on a descriptor
/// of its own, through `dart:ffi`. A `flock` lock belongs to that open file
/// description, so another isolate's descriptor conflicts with it and closing
/// any other descriptor of the file leaves it held. On Windows it is
/// [RandomAccessFile.lock], whose `LockFileEx` lock belongs to its handle
/// and has the same properties; it is also mandatory, so while it is held no
/// other handle reads the file's [writeNote].
///
/// Dart's own [RandomAccessFile.lock] is a `fcntl` record lock on POSIX: it
/// belongs to the whole process, so isolates do not exclude each other, and
/// closing any descriptor of the file releases it. Wayfinder's lock files use
/// this class instead. `flock` and `fcntl` locks do not exclude each other.
///
/// Its descriptor is close-on-exec, and [release] unlocks before closing, so
/// a child process another isolate starts never keeps the lock. The lock
/// file stays in place on release. A cleanup that deletes a lock file
/// deletes it while holding the lock, and an acquirer that opened the file
/// just before checks, once it has the lock, that the path still names the
/// file it locked, and opens the path again when it does not; so two holders
/// never lock different files. Always [release] in a `finally`; an abandoned
/// lock is held until its process exits.
final class WayfinderFileLock {
  WayfinderFileLock._(this.file, this._handle);

  /// The lock file.
  final File file;
  _Handle? _handle;

  /// Whether [release] ran.
  bool get isReleased => _handle == null;

  /// How long [tryExclusive] keeps trying a lock that is taken. An [isHeld]
  /// probe takes a shared lock for an instant, while a holder keeps the lock
  /// for its whole operation.
  static const _probeTolerance = Duration(milliseconds: 100);

  /// Takes the lock without waiting for a holder; null while another holder
  /// has it. Creates [file] and its directory when missing.
  ///
  /// An [isHeld] probe holds a shared lock on the file for an instant, and
  /// must not read as a holder, so a refused attempt is tried again for up
  /// to 100 milliseconds before this returns null.
  static Future<WayfinderFileLock?> tryExclusive(File file) async {
    final watch = Stopwatch()..start();
    var delay = const Duration(milliseconds: 1);
    while (true) {
      final lock = await _attempt(file);
      if (lock != null) return lock;
      final left = _probeTolerance - watch.elapsed;
      if (left <= Duration.zero) return null;
      await Future<void>.delayed(delay < left ? delay : left);
      if (delay < const Duration(milliseconds: 32)) delay *= 2;
    }
  }

  /// Takes the lock, polling until it is free. Throws a [TimeoutException]
  /// after [timeout], and `WayfinderException.cancelled()` when [cancel]
  /// fires first.
  static Future<WayfinderFileLock> exclusive(
    File file, {
    Duration timeout = const Duration(seconds: 120),
    WayfinderCancellation? cancel,
  }) async {
    // One listener per wait, removed after it, so a long-lived cancellation
    // does not collect one per poll.
    final cancelled = Completer<void>();
    final listening = cancel?.whenCancelled.asStream().listen((_) {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    try {
      final watch = Stopwatch()..start();
      var delay = const Duration(milliseconds: 5);
      while (true) {
        throwIfCancelled(cancel);
        if (await _attempt(file) case final lock?) return lock;
        final left = timeout - watch.elapsed;
        if (left <= Duration.zero) {
          throw TimeoutException(
            'Timed out waiting for the lock ${file.path}.',
            timeout,
          );
        }
        final wait = delay < left ? delay : left;
        await Future.any([Future<void>.delayed(wait), cancelled.future]);
        if (delay < const Duration(milliseconds: 200)) delay *= 2;
      }
    } finally {
      await listening?.cancel();
    }
  }

  /// One try for the lock on a descriptor opened for it; null when another
  /// descriptor has a conflicting lock. A cleanup may have deleted the file
  /// between this open and this lock, leaving the descriptor on a file no
  /// one else opens, so the lock is returned only while the path still
  /// names the file it locked; otherwise the path is opened again.
  static Future<WayfinderFileLock?> _attempt(File file) async {
    for (var opened = 0; opened < 3; opened++) {
      final handle = await _open(file);
      var kept = false;
      try {
        if (!await handle.tryLock(exclusive: true)) return null;
        if (await handle.namesFile()) {
          kept = true;
          return WayfinderFileLock._(file, handle);
        }
      } finally {
        if (!kept) await handle.close();
      }
    }
    return null;
  }

  /// Whether any holder, in this process or another, has the lock on
  /// [file]. Tries a shared lock on a descriptor of its own and releases it
  /// at once, so it never disturbs a holder, and [tryExclusive] does not
  /// mistake it for one. False when [file] is missing.
  static Future<bool> isHeld(File file) async {
    final _Handle handle;
    try {
      handle = await _open(file, create: false);
    } on PathNotFoundException {
      return false;
    }
    try {
      return !await handle.tryLock(exclusive: false);
    } finally {
      await handle.close();
    }
  }

  /// Replaces the lock file's contents with [text], such as the path the
  /// lock protects, so a later cleanup can tell what it belonged to. Only
  /// the holder writes. Read the note only once [isHeld] is false: on
  /// Windows the lock is a mandatory byte-range lock, so no other handle
  /// can read the file while it is held.
  Future<void> writeNote(String text) async {
    final handle = _handle ?? (throw StateError('The lock was released.'));
    await handle.write(text);
  }

  /// Releases the lock and closes its descriptor. Later calls do nothing.
  Future<void> release() async {
    final handle = _handle;
    _handle = null;
    await handle?.close();
  }

  static Future<_Handle> _open(File file, {bool create = true}) async {
    if (create) await file.parent.create(recursive: true);
    return Platform.isWindows
        ? _WindowsHandle.open(file, create: create)
        : _PosixHandle.open(file, create: create);
  }
}

/// One descriptor of a lock file, with its lock.
sealed class _Handle {
  /// Locks without waiting; false when another descriptor conflicts.
  Future<bool> tryLock({required bool exclusive});

  Future<void> write(String text);

  /// Whether the lock file's path still names the file this descriptor has
  /// open. True when that cannot be told.
  Future<bool> namesFile();

  /// Releases any lock and closes the descriptor.
  Future<void> close();
}

final class _WindowsHandle extends _Handle {
  _WindowsHandle(this._file, this._path);

  final RandomAccessFile _file;
  final String _path;
  bool _locked = false;

  static Future<_WindowsHandle> open(File file, {required bool create}) async {
    if (!create && !await file.exists()) {
      throw PathNotFoundException(
        file.path,
        const OSError('The system cannot find the file specified.', 2),
      );
    }
    return _WindowsHandle(
      await file.open(mode: create ? FileMode.append : FileMode.read),
      file.path,
    );
  }

  @override
  Future<bool> tryLock({required bool exclusive}) async {
    try {
      await _file.lock(exclusive ? FileLock.exclusive : FileLock.shared);
    } on FileSystemException {
      return false;
    }
    _locked = true;
    return true;
  }

  @override
  Future<void> write(String text) async {
    await _file.truncate(0);
    await _file.setPosition(0);
    await _file.writeString(text);
    await _file.flush();
  }

  /// Windows deletes no file another handle has open, so the path names the
  /// file this handle opened for as long as it is open.
  @override
  Future<bool> namesFile() async => true;

  @override
  Future<void> close() async {
    try {
      if (_locked) await _file.unlock();
    } on FileSystemException {
      // Closing the handle releases its lock regardless.
    } finally {
      _locked = false;
      await _file.close();
    }
  }

  @override
  String toString() => _path;
}

final class _PosixHandle extends _Handle {
  _PosixHandle(this._descriptor, this._path, this._absolutePath);

  int? _descriptor;
  final String _path;
  final String _absolutePath;
  bool _locked = false;

  static Future<_PosixHandle> open(File file, {required bool create}) async {
    final libc = _Libc.instance;
    final path = file.absolute.path.toNativeUtf8();
    try {
      final flags =
          _Libc.readWrite | libc.closeOnExec | (create ? libc.create : 0);
      while (true) {
        final descriptor = libc.open(path, flags, 420); // 0644
        if (descriptor >= 0) {
          return _PosixHandle(descriptor, file.path, file.absolute.path);
        }
        final errno = libc.errno;
        if (errno == _Libc.interrupted) continue;
        final error = OSError('open failed', errno);
        if (errno == _Libc.notFound) {
          throw PathNotFoundException(file.path, error, 'Cannot open lock');
        }
        throw FileSystemException('Cannot open lock', file.path, error);
      }
    } finally {
      malloc.free(path);
    }
  }

  @override
  Future<bool> tryLock({required bool exclusive}) async {
    final libc = _Libc.instance;
    final descriptor = _descriptor!;
    final operation =
        (exclusive ? _Libc.lockExclusive : _Libc.lockShared) |
        _Libc.lockNonBlocking;
    while (true) {
      final errno = libc.flockErrno(descriptor, operation);
      if (errno == 0) return _locked = true;
      if (errno == libc.wouldBlock) return false;
      if (errno == _Libc.interrupted) continue;
      throw FileSystemException(
        'Cannot lock',
        _path,
        OSError('flock failed', errno),
      );
    }
  }

  @override
  Future<void> write(String text) =>
      File(_path).writeAsString(text, flush: true);

  @override
  Future<bool> namesFile() async {
    final libc = _Libc.instance;
    return libc.identity?.sameFile(libc, _descriptor!, _absolutePath) ?? true;
  }

  @override
  Future<void> close() async {
    final descriptor = _descriptor;
    _descriptor = null;
    if (descriptor == null) return;
    final libc = _Libc.instance;
    // Unlock before closing: a child another isolate is forking shares the
    // open file description until it execs, and closing only this descriptor
    // would leave the lock held until then.
    if (_locked) libc.flock(descriptor, _Libc.unlock);
    _locked = false;
    libc.close(descriptor);
  }
}

/// The few libc calls the POSIX lock needs.
///
/// `errno` is thread-local. Two leaf calls still return to Dart between
/// them, and the isolate can resume on another thread, so a later read can
/// observe a stale `errno` (22 is the value this hit under load).
/// [flockErrno] does not read `errno` after `flock`.
final class _Libc {
  _Libc._(DynamicLibrary library, {required bool apple})
    : open = library
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
            int Function(Pointer<Utf8>, int, int)
          >('open', isLeaf: true),
      flock = library
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'flock',
            isLeaf: true,
          ),
      close = library.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
        isLeaf: true,
      ),
      _errno = library
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            apple
                ? '__error'
                : Platform.isAndroid
                ? '__errno'
                : '__errno_location',
            isLeaf: true,
          ),
      _flockSyscall = _loadFlockSyscall(library),
      create = apple ? 0x200 : 0x40,
      closeOnExec = apple ? 0x1000000 : 0x80000,
      wouldBlock = apple ? 35 : 11,
      identity = _FileIdentity.lookup(library, apple: apple);

  static final instance = _Libc._(
    DynamicLibrary.process(),
    apple: Platform.isMacOS || Platform.isIOS,
  );

  static const lockShared = 1;
  static const lockExclusive = 2;
  static const lockNonBlocking = 4;
  static const unlock = 8;
  static const readOnly = 0;
  static const readWrite = 2;
  static const interrupted = 4;
  static const notFound = 2;

  final int Function(Pointer<Utf8>, int, int) open;
  final int Function(int, int) flock;
  final int Function(int) close;
  final Pointer<Int32> Function() _errno;

  /// Linux x64 `flock` syscall: 0, or `-errno` in the result register.
  /// Null where that stub is not installed.
  final int Function(int, int)? _flockSyscall;

  /// 0 when a non-blocking `flock` took the lock, otherwise an errno.
  ///
  /// Where [_flockSyscall] is installed, the syscall result is the errno.
  /// Otherwise this reads `errno` afterwards. That read can belong to
  /// another thread. Apple cannot map an executable stub without a JIT
  /// entitlement, and any host whose stub failed to install is in the same
  /// place, so an unexpected errno on this non-blocking try is reported as
  /// busy and the caller retries.
  int flockErrno(int descriptor, int operation) {
    final syscall = _flockSyscall;
    if (syscall != null) {
      final result = syscall(descriptor, operation);
      if (result == 0) return 0;
      return result < 0 ? -result : result;
    }
    if (flock(descriptor, operation) == 0) return 0;
    final errno = this.errno;
    if (errno == wouldBlock || errno == _Libc.interrupted) return errno;
    return wouldBlock;
  }

  /// `O_CREAT`, `O_CLOEXEC` and `EWOULDBLOCK`, which differ between Apple
  /// platforms and Linux.
  final int create;
  final int closeOnExec;
  final int wouldBlock;

  /// Null where the identity of an open file cannot be read.
  final _FileIdentity? identity;

  int get errno => _errno().value;
}

/// Pages holding the flock syscall stub. The function pointer points into
/// one of them, so they stay mapped for the process.
final _flockStubPages = <Pointer<Uint8>>[];

/// One x86-64 `flock` syscall, or null when it cannot be installed.
///
/// `__NR_flock` is 73. Arguments arrive in `rdi` and `rsi`, which is where
/// the kernel reads them, and the result is 0 or `-errno`. The page is
/// written, then marked executable, so it is never writable and executable
/// at once. Other architectures, and a host that refuses the mapping, keep
/// the libc call.
int Function(int, int)? _loadFlockSyscall(DynamicLibrary library) {
  if (!Platform.isLinux && !Platform.isAndroid) return null;
  final abi = Abi.current();
  if (abi != Abi.linuxX64 && abi != Abi.androidX64) return null;
  try {
    final mmap = library
        .lookupFunction<
          Pointer<Uint8> Function(
            Pointer<Uint8>,
            IntPtr,
            Int32,
            Int32,
            Int32,
            Int64,
          ),
          Pointer<Uint8> Function(Pointer<Uint8>, int, int, int, int, int)
        >('mmap', isLeaf: true);
    final mprotect = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, IntPtr, Int32),
          int Function(Pointer<Uint8>, int, int)
        >('mprotect', isLeaf: true);
    const read = 1;
    const write = 2;
    const execute = 4;
    const mapPrivate = 2;
    const mapAnonymous = 0x20;
    final page = mmap(
      nullptr,
      4096,
      read | write,
      mapPrivate | mapAnonymous,
      -1,
      0,
    );
    if (page.address == 0 || page.address == -1) return null;
    // mov eax, 73; syscall; ret
    const bytes = [0xb8, 73, 0, 0, 0, 0x0f, 0x05, 0xc3];
    for (var i = 0; i < bytes.length; i++) {
      page[i] = bytes[i];
    }
    if (mprotect(page, 4096, read | execute) != 0) return null;
    _flockStubPages.add(page);
    return page.cast<NativeFunction<Int64 Function(Int64, Int64)>>().asFunction(
      isLeaf: true,
    );
  } on ArgumentError {
    return null;
  }
}

/// Compares the device and inode, from `fstat(2)`, of a descriptor and of a
/// descriptor this opens on a path.
///
/// `struct stat` holds `st_dev` at offset 0, 64 bits wide on 64-bit Linux
/// and Android and 32 bits on Apple platforms, and the 64-bit `st_ino` at
/// offset 8. x86-64 macOS has that layout through `fstat$INODE64`; glibc
/// exports `fstat` from 2.33 on. Elsewhere [lookup] returns null and the
/// lock trusts its path.
final class _FileIdentity {
  _FileIdentity._(this._fstat, {required this.wideDevice});

  static _FileIdentity? lookup(DynamicLibrary library, {required bool apple}) {
    final abi = Abi.current();
    final String symbol;
    if (apple) {
      symbol = abi == Abi.macosX64 ? r'fstat$INODE64' : 'fstat';
    } else if (const {
      Abi.linuxX64,
      Abi.linuxArm64,
      Abi.linuxRiscv64,
      Abi.androidX64,
      Abi.androidArm64,
      Abi.androidRiscv64,
    }.contains(abi)) {
      symbol = 'fstat';
    } else {
      return null;
    }
    if (!library.providesSymbol(symbol)) return null;
    return _FileIdentity._(
      library.lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)
      >(symbol, isLeaf: true),
      wideDevice: !apple,
    );
  }

  /// Larger than any `struct stat` (144 bytes).
  static const _size = 256;

  final int Function(int, Pointer<Uint8>) _fstat;

  /// Whether `st_dev` is 64 bits wide.
  final bool wideDevice;

  /// Whether [path] names the file [descriptor] has open. True when either
  /// cannot be read, unless the path names nothing.
  bool sameFile(_Libc libc, int descriptor, String path) {
    final buffer = calloc<Uint8>(2 * _size);
    final native = path.toNativeUtf8();
    try {
      final named = buffer + _size;
      if (_fstat(descriptor, buffer) != 0) return true;
      final other = libc.open(native, _Libc.readOnly | libc.closeOnExec, 0);
      if (other < 0) return libc.errno != _Libc.notFound;
      try {
        if (_fstat(other, named) != 0) return true;
      } finally {
        libc.close(other);
      }
      return _id(buffer) == _id(named);
    } finally {
      malloc.free(native);
      calloc.free(buffer);
    }
  }

  (int, int) _id(Pointer<Uint8> stat) => (
    wideDevice ? stat.cast<Int64>().value : stat.cast<Int32>().value,
    (stat + 8).cast<Uint64>().value,
  );
}
