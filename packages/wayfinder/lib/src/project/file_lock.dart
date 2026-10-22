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
/// file stays in place on release: deleting a lock file another process has
/// open would let two holders lock different files. Always [release] in a
/// `finally`; an abandoned lock is held until its process exits.
final class WayfinderFileLock {
  WayfinderFileLock._(this.file, this._handle);

  /// The lock file.
  final File file;
  _Handle? _handle;

  /// Whether [release] ran.
  bool get isReleased => _handle == null;

  /// Takes the lock without waiting; null while another holder has it.
  /// Creates [file] and its directory when missing.
  static Future<WayfinderFileLock?> tryExclusive(File file) async {
    final handle = await _open(file);
    try {
      if (await handle.tryLock(exclusive: true)) {
        return WayfinderFileLock._(file, handle);
      }
    } on Object {
      await handle.close();
      rethrow;
    }
    await handle.close();
    return null;
  }

  /// Takes the lock, polling until it is free. Throws a [TimeoutException]
  /// after [timeout], and `WayfinderException.cancelled()` when [cancel]
  /// fires first.
  static Future<WayfinderFileLock> exclusive(
    File file, {
    Duration timeout = const Duration(seconds: 120),
    WayfinderCancellation? cancel,
  }) async {
    final handle = await _open(file);
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
        if (await handle.tryLock(exclusive: true)) {
          return WayfinderFileLock._(file, handle);
        }
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
    } on Object {
      await handle.close();
      rethrow;
    } finally {
      await listening?.cancel();
    }
  }

  /// Whether any holder, in this process or another, has the lock on
  /// [file]. Tries a shared lock on a descriptor of its own and releases it
  /// at once, so it never disturbs a holder. False when [file] is missing.
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
  _PosixHandle(this._descriptor, this._path);

  int? _descriptor;
  final String _path;
  bool _locked = false;

  static Future<_PosixHandle> open(File file, {required bool create}) async {
    final libc = _Libc.instance;
    final path = file.absolute.path.toNativeUtf8();
    try {
      final flags =
          _Libc.readWrite | libc.closeOnExec | (create ? libc.create : 0);
      while (true) {
        final descriptor = libc.open(path, flags, 420); // 0644
        if (descriptor >= 0) return _PosixHandle(descriptor, file.path);
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
      if (libc.flock(descriptor, operation) == 0) return _locked = true;
      final errno = libc.errno;
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

/// The few libc calls the POSIX lock needs, as leaf calls: no VM transition
/// runs between a failed call and the read of its `errno`.
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
      create = apple ? 0x200 : 0x40,
      closeOnExec = apple ? 0x1000000 : 0x80000,
      wouldBlock = apple ? 35 : 11;

  static final instance = _Libc._(
    DynamicLibrary.process(),
    apple: Platform.isMacOS || Platform.isIOS,
  );

  static const lockShared = 1;
  static const lockExclusive = 2;
  static const lockNonBlocking = 4;
  static const unlock = 8;
  static const readWrite = 2;
  static const interrupted = 4;
  static const notFound = 2;

  final int Function(Pointer<Utf8>, int, int) open;
  final int Function(int, int) flock;
  final int Function(int) close;
  final Pointer<Int32> Function() _errno;

  /// `O_CREAT`, `O_CLOEXEC` and `EWOULDBLOCK`, which differ between Apple
  /// platforms and Linux.
  final int create;
  final int closeOnExec;
  final int wouldBlock;

  int get errno => _errno().value;
}
