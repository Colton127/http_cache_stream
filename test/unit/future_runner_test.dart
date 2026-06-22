import 'dart:async';

import 'package:http_cache_stream/src/etc/future_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deduplicates concurrent calls and runs the factory once', () async {
    final runner = FutureRunner<int>();
    final gate = Completer<void>();
    var calls = 0;

    Future<int> factory() async {
      calls++;
      await gate.future;
      return 42;
    }

    final a = runner.run(factory);
    final b = runner.run(factory);

    expect(runner.isRunning, isTrue);
    expect(identical(a, b), isTrue);

    gate.complete();
    expect(await a, 42);
    expect(await b, 42);
    expect(calls, 1);
  });

  test('clears the in-flight future after success so it can run again',
      () async {
    final runner = FutureRunner<int>();
    expect(await runner.run(() async => 1), 1);
    expect(runner.isRunning, isFalse);
    expect(await runner.run(() async => 2), 2);
  });

  test('clears the in-flight future after an error', () async {
    final runner = FutureRunner<int>();
    await expectLater(
      runner.run(() async => throw StateError('boom')),
      throwsStateError,
    );
    expect(runner.isRunning, isFalse);
    // Recovers and can run again.
    expect(await runner.run(() async => 7), 7);
  });
}
