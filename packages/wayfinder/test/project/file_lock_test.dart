import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wayfinder/project.dart';

void main() {
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wayfinder-lock-');
    file = File(p.join(temp.path, 'nested', 'writer.lock'));
  });

  tearDown(() => temp.delete(recursive: true));

  Future<Map<String, Object?>> probeFromSubprocess() async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      p.join('test', 'project', 'fixtures', 'lock_child.dart'),
      file.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return jsonDecode(const LineSplitter().convert('${result.stdout}').last)
        as Map<String, Object?>;
  }

  test('creates the file and its directory, and keeps the file on '
      'release', () async {
    final lock = await WayfinderFileLock.tryExclusive(file);
    expect(lock, isNotNull);
    expect(await file.exists(), isTrue);
    expect(lock!.isReleased, isFalse);
    await lock.release();
    await lock.release();
    expect(lock.isReleased, isTrue);
    expect(await file.exists(), isTrue);
    expect(await WayfinderFileLock.isHeld(file), isFalse);
  });

  test('a second holder in the same isolate is refused', () async {
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    try {
      expect(await WayfinderFileLock.tryExclusive(file), isNull);
      expect(await WayfinderFileLock.isHeld(file), isTrue);
    } finally {
      await lock.release();
    }
    final again = await WayfinderFileLock.tryExclusive(file);
    expect(again, isNotNull);
    await again!.release();
  });

  test('two isolates in one process exclude each other', () async {
    final path = file.path;
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    try {
      expect(
        await Isolate.run(() async {
          final other = await WayfinderFileLock.tryExclusive(File(path));
          await other?.release();
          return (
            acquired: other != null,
            held: await WayfinderFileLock.isHeld(File(path)),
          );
        }),
        (acquired: false, held: true),
      );
    } finally {
      await lock.release();
    }
    expect(
      await Isolate.run(() async {
        final other = await WayfinderFileLock.tryExclusive(File(path));
        await other?.release();
        return other != null;
      }),
      isTrue,
    );
  });

  test('an isolate holding the lock excludes this one', () async {
    final path = file.path;
    final ready = ReceivePort();
    final readySends = ready.sendPort;
    final worker = Isolate.run(() async {
      final lock = (await WayfinderFileLock.tryExclusive(File(path)))!;
      final control = ReceivePort();
      readySends.send(control.sendPort);
      await control.first;
      await lock.release();
    });
    final control = await ready.first as SendPort;
    try {
      expect(await WayfinderFileLock.tryExclusive(file), isNull);
      expect(await WayfinderFileLock.isHeld(file), isTrue);
    } finally {
      control.send(null);
      await worker;
    }
    expect(await WayfinderFileLock.isHeld(file), isFalse);
  });

  test('a dart run subprocess sees the lock as held', () async {
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    try {
      expect(await probeFromSubprocess(), {'held': true, 'acquired': false});
    } finally {
      await lock.release();
    }
    expect(await probeFromSubprocess(), {'held': false, 'acquired': true});
  });

  test('opening and closing a second descriptor on the file does not '
      'release the lock', () async {
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    try {
      final reader = await file.open();
      await reader.close();
      final writer = await file.open(mode: FileMode.append);
      await writer.close();
      await file.readAsString();
      expect(await WayfinderFileLock.isHeld(file), isTrue);
      expect(await probeFromSubprocess(), {'held': true, 'acquired': false});
      final path = file.path;
      expect(
        await Isolate.run(() async {
          final other = await WayfinderFileLock.tryExclusive(File(path));
          await other?.release();
          return other != null;
        }),
        isFalse,
      );
    } finally {
      await lock.release();
    }
  });

  test('release takes effect at once while another isolate starts '
      'processes', () async {
    final path = file.path;
    final spawning = Isolate.run(() async {
      final until = DateTime.now().add(const Duration(seconds: 2));
      var started = 0;
      while (DateTime.now().isBefore(until)) {
        await Future.wait([
          for (var i = 0; i < 4; i++) Process.run('git', ['--version']),
        ]);
        started += 4;
      }
      return started;
    });
    var cycles = 0;
    final until = DateTime.now().add(const Duration(milliseconds: 1500));
    while (DateTime.now().isBefore(until)) {
      final lock = await WayfinderFileLock.tryExclusive(File(path));
      expect(lock, isNotNull, reason: 'cycle $cycles');
      await lock!.release();
      expect(await WayfinderFileLock.isHeld(file), isFalse);
      cycles++;
    }
    expect(await spawning, greaterThan(0));
    expect(cycles, greaterThan(0));
  });

  test('a shared probe is not a holder: tryExclusive waits it out', () async {
    await (await WayfinderFileLock.tryExclusive(file))!.release();
    // An isHeld probe holds this shared lock for an instant; hold it longer.
    var release = await holdShared(file);
    final released = Future<void>.delayed(
      const Duration(milliseconds: 20),
      () => release(),
    );
    final lock = await WayfinderFileLock.tryExclusive(file);
    await released;
    expect(lock, isNotNull);
    await lock!.release();

    // A lock held longer than an instant still refuses.
    release = await holdShared(file);
    try {
      final watch = Stopwatch()..start();
      expect(await WayfinderFileLock.tryExclusive(file), isNull);
      expect(watch.elapsed, greaterThanOrEqualTo(_probeTolerance));
    } finally {
      await release();
    }
  });

  test(
    'an acquirer whose lock file a cleanup deleted locks the file now at '
    'the path',
    () async {
      final cleanup = (await WayfinderFileLock.tryExclusive(file))!;
      // Refused at first, so it tries again while the cleanup deletes the
      // file it opened.
      final waiting = WayfinderFileLock.tryExclusive(file);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await file.delete();
      await cleanup.release();
      final lock = await waiting;
      expect(lock, isNotNull);
      try {
        expect(await file.exists(), isTrue);
        expect(await WayfinderFileLock.isHeld(file), isTrue);
        expect(await WayfinderFileLock.tryExclusive(file), isNull);
      } finally {
        await lock!.release();
      }
    },
    skip: Platform.isWindows
        ? 'Windows deletes no file another handle has open'
        : false,
  );

  test('isHeld is false for a missing file and creates nothing', () async {
    expect(await WayfinderFileLock.isHeld(file), isFalse);
    expect(await file.parent.exists(), isFalse);
  });

  test('exclusive waits for the holder to release', () async {
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    var acquired = false;
    final waiting =
        WayfinderFileLock.exclusive(
          file,
          timeout: const Duration(seconds: 10),
        ).then((second) {
          acquired = true;
          return second;
        });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(acquired, isFalse);
    await lock.release();
    final second = await waiting;
    expect(acquired, isTrue);
    await second.release();
  });

  test('exclusive times out while another holds the lock', () async {
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    try {
      await expectLater(
        WayfinderFileLock.exclusive(
          file,
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
    } finally {
      await lock.release();
    }
  });

  test('exclusive stops when cancelled', () async {
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    final cancel = WayfinderCancellationController();
    try {
      final waiting = WayfinderFileLock.exclusive(
        file,
        timeout: const Duration(seconds: 30),
        cancel: cancel,
      );
      cancel.cancel();
      await expectLater(
        waiting,
        throwsA(
          isA<WayfinderException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
    } finally {
      await lock.release();
    }
  });

  test('the holder can record what the lock protects', () async {
    final lock = (await WayfinderFileLock.tryExclusive(file))!;
    try {
      await lock.writeNote('first note that is long\n');
      await lock.writeNote('{"root":"/a"}\n');
      expect(await WayfinderFileLock.isHeld(file), isTrue);
    } finally {
      await lock.release();
    }
    expect(await file.readAsString(), '{"root":"/a"}\n');
  });

  test(
    'contended non-blocking probes do not throw a stale flock errno',
    () async {
      // One holder, and this isolate plus three others calling the
      // non-blocking paths against it. A failed flock and the errno read
      // are separate calls; fifty rounds is enough for the race to show
      // when other dart test processes are running.
      final path = file.path;
      for (var round = 0; round < 50; round++) {
        final holder = (await WayfinderFileLock.tryExclusive(file))!;
        try {
          await Future.wait([
            _hammerLock(path),
            for (var i = 0; i < 3; i++) Isolate.run(() => _hammerLock(path)),
          ]);
        } finally {
          await holder.release();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// Probes a lock another holder keeps. [WayfinderFileLock.isHeld] and a
/// refused [WayfinderFileLock.tryExclusive] must not throw.
Future<void> _hammerLock(String path) async {
  final file = File(path);
  for (var i = 0; i < 100; i++) {
    await WayfinderFileLock.isHeld(file);
  }
  final acquired = await WayfinderFileLock.tryExclusive(file);
  if (acquired != null) {
    await acquired.release();
    throw StateError('A probe took a lock another holder kept.');
  }
}

/// How long `tryExclusive` retries a taken lock.
const _probeTolerance = Duration(milliseconds: 100);

/// Takes a shared lock on [file] the way an `isHeld` probe does, and
/// returns what releases it.
Future<Future<void> Function()> holdShared(File file) async {
  if (Platform.isWindows) {
    final handle = await file.open();
    await handle.lock(FileLock.shared);
    return () async {
      await handle.unlock();
      await handle.close();
    };
  }
  final library = DynamicLibrary.process();
  final open = library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  final flock = library
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  final close = library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  final path = file.absolute.path.toNativeUtf8();
  final descriptor = open(path, 0, 0); // O_RDONLY
  malloc.free(path);
  if (descriptor < 0) throw StateError('Cannot open ${file.path}.');
  if (flock(descriptor, 1 | 4) != 0) {
    // LOCK_SH | LOCK_NB
    close(descriptor);
    throw StateError('Cannot take a shared lock on ${file.path}.');
  }
  return () async {
    flock(descriptor, 8); // LOCK_UN
    close(descriptor);
  };
}
