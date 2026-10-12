import 'package:flutter_hbb/regway/quality_pill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delay: green ≤80, yellow 81–200, red >200', () {
    expect(rwQualityBand(delayMs: 40), RwQualityBand.good);
    expect(rwQualityBand(delayMs: 80), RwQualityBand.good);
    expect(rwQualityBand(delayMs: 81), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 200), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 201), RwQualityBand.bad);
  });

  test('loss: green ≤1%, yellow 1–5%, red >5%', () {
    expect(rwQualityBand(delayMs: 40, lossPct: 0.5), RwQualityBand.good);
    expect(rwQualityBand(delayMs: 40, lossPct: 1), RwQualityBand.good);
    expect(rwQualityBand(delayMs: 40, lossPct: 1.1), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 40, lossPct: 5), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 40, lossPct: 5.1), RwQualityBand.bad);
  });

  test('worse of delay and loss wins', () {
    expect(rwQualityBand(delayMs: 250, lossPct: 0), RwQualityBand.bad);
    expect(rwQualityBand(delayMs: 40, lossPct: 9), RwQualityBand.bad);
    expect(rwQualityBand(delayMs: 120, lossPct: 0.2), RwQualityBand.warn);
  });

  test('3 bars: good 3, warn 2, bad 1, none 0', () {
    expect(rwQualityBarsFilled(RwQualityBand.good), 3);
    expect(rwQualityBarsFilled(RwQualityBand.warn), 2);
    expect(rwQualityBarsFilled(RwQualityBand.bad), 1);
    expect(rwQualityBarsFilled(RwQualityBand.none), 0);
  });

  test('no data is grey after 3 s', () {
    final tracker = RwQualityTracker();
    final t0 = DateTime.utc(2026, 1, 1, 12);
    expect(
      tracker.update(now: t0, eventAt: t0, delayMs: 40, fps: 30).band,
      RwQualityBand.good,
    );
    expect(
      tracker
          .update(now: t0.add(const Duration(seconds: 4)), delayMs: 40, fps: 30)
          .band,
      RwQualityBand.none,
    );
  });

  test('color does not change more than once per 2 s', () {
    final tracker = RwQualityTracker();
    final t0 = DateTime.utc(2026, 1, 1, 12);
    expect(
      tracker.update(now: t0, eventAt: t0, delayMs: 40, fps: 30).band,
      RwQualityBand.good,
    );
    final t1 = t0.add(const Duration(milliseconds: 500));
    expect(
      tracker.update(now: t1, eventAt: t1, delayMs: 250, fps: 30).band,
      RwQualityBand.good,
    );
    // 3.1 s later the 40 ms sample is out of the 3 s window (avg 250 → red)
    // and the 2 s colour hold has expired.
    final t2 = t0.add(const Duration(milliseconds: 3100));
    expect(
      tracker.update(now: t2, eventAt: t2, delayMs: 250, fps: 30).band,
      RwQualityBand.bad,
    );
  });

  test('delay is averaged over a 3 s window', () {
    final tracker = RwQualityTracker();
    final t0 = DateTime.utc(2026, 1, 1, 12);
    tracker.update(now: t0, eventAt: t0, delayMs: 40, fps: 30);
    final t1 = t0.add(const Duration(seconds: 1));
    tracker.update(now: t1, eventAt: t1, delayMs: 160, fps: 30);
    final t2 = t0.add(const Duration(seconds: 2));
    final view = tracker.update(now: t2, eventAt: t2, delayMs: 40, fps: 30);
    expect(view.delayMs, 80);
    expect(view.band, RwQualityBand.good);
  });
}
