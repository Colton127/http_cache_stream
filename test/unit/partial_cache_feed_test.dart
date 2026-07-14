import 'package:flutter_test/flutter_test.dart';
import 'package:http_cache_stream/src/cache_stream/cache_downloader/partial_cache_feed.dart';

void main() {
  test('waitForData completes immediately when data is already available', () {
    final feed = PartialCacheFeed(100);
    expect(feed.flushedPosition, 100);
    // Position 50 is already exceeded by flushedPosition 100.
    expect(feed.waitForData(50), completes);
  });

  test('waitForData waits until flushedPosition exceeds the position',
      () async {
    final feed = PartialCacheFeed(0);
    bool completed = false;
    final wait = feed.waitForData(100).then((_) => completed = true);

    feed.update(50);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse,
        reason: 'flushedPosition 50 does not exceed position 100');

    feed.update(100);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse,
        reason: 'flushedPosition must exceed, not equal, the position');

    feed.update(101);
    await wait;
    expect(completed, isTrue);
  });

  test('multiple waiters at different positions wake independently', () async {
    final feed = PartialCacheFeed(0);
    bool near = false, far = false;
    final nearWait = feed.waitForData(10).then((_) => near = true);
    final farWait = feed.waitForData(1000).then((_) => far = true);

    feed.update(11);
    await nearWait;
    expect(near, isTrue);
    expect(far, isFalse);

    feed.update(1001);
    await farWait;
    expect(far, isTrue);
  });

  test('finish wakes all waiters and records the error', () async {
    final feed = PartialCacheFeed(0);
    final error = StateError('stopped');
    final wait = feed.waitForData(100);

    feed.finish(error);
    await expectLater(wait, completes); // never errors
    expect(feed.isFinished, isTrue);
    expect(feed.finishError, same(error));

    // Waits after finish complete immediately.
    expect(feed.waitForData(500), completes);
  });

  test('finish without error marks a normal completion', () {
    final feed = PartialCacheFeed(10);
    feed.finish();
    expect(feed.isFinished, isTrue);
    expect(feed.finishError, isNull);
  });

  test('finish is idempotent and keeps the first result', () {
    final feed = PartialCacheFeed(0);
    feed.finish();
    feed.finish(StateError('late error'));
    expect(feed.finishError, isNull);
  });

  test('update ignores non-advancing positions', () {
    final feed = PartialCacheFeed(100);
    feed.update(100);
    expect(feed.flushedPosition, 100);
  });
}
