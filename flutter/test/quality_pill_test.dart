import 'package:flutter_hbb/regway/quality_pill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delay thresholds 80 / 200 ms', () {
    expect(rwQualityBand(delayMs: 40), RwQualityBand.good);
    expect(rwQualityBand(delayMs: 79.9), RwQualityBand.good);
    expect(rwQualityBand(delayMs: 80), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 199), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 200), RwQualityBand.bad);
  });

  test('loss thresholds 1 / 5 percent', () {
    expect(rwQualityBand(delayMs: 40, lossPct: 0.5), RwQualityBand.good);
    expect(rwQualityBand(delayMs: 40, lossPct: 1), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 40, lossPct: 4.9), RwQualityBand.warn);
    expect(rwQualityBand(delayMs: 40, lossPct: 5), RwQualityBand.bad);
  });

  test('worst of delay and loss wins', () {
    expect(rwQualityBand(delayMs: 250, lossPct: 0), RwQualityBand.bad);
    expect(rwQualityBand(delayMs: 40, lossPct: 9), RwQualityBand.bad);
    expect(rwQualityBand(delayMs: 120, lossPct: 0.2), RwQualityBand.warn);
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
    final t2 = t0.add(const Duration(seconds: 2));
    expect(
      tracker.update(now: t2, eventAt: t2, delayMs: 250, fps: 30).band,
      RwQualityBand.bad,
    );
  });
}
