import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
      p.join('test', 'project', 'probes', 'lock_probe.dart'),
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
}
