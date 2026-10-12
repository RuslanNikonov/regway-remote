import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../models/model.dart';
import 'theme.dart';

/// v3 quality pill: delay + frame-loss bands, 3 s average, 3 s stale, 2 s color hold.
const double kRwQualityDelayGoodMs = 80;
const double kRwQualityDelayBadMs = 200;
const double kRwQualityLossGoodPct = 1;
const double kRwQualityLossBadPct = 5;
const Duration kRwQualityAvgWindow = Duration(seconds: 3);
const Duration kRwQualityStaleAfter = Duration(seconds: 3);
const Duration kRwQualityColorHold = Duration(seconds: 2);

enum RwQualityBand { none, good, warn, bad }

class RwQualityView {
  final RwQualityBand band;
  final double? delayMs;
  final double? lossPct;
  const RwQualityView({required this.band, this.delayMs, this.lossPct});
}

RwQualityBand rwQualityBand({double? delayMs, double? lossPct}) {
  var band = RwQualityBand.good;
  var any = false;
  if (delayMs != null) {
    any = true;
    if (delayMs >= kRwQualityDelayBadMs) {
      band = RwQualityBand.bad;
    } else if (delayMs >= kRwQualityDelayGoodMs) {
      band = RwQualityBand.warn;
    }
  }
  if (lossPct != null) {
    any = true;
    if (lossPct >= kRwQualityLossBadPct) {
      band = _worse(band, RwQualityBand.bad);
    } else if (lossPct >= kRwQualityLossGoodPct) {
      band = _worse(band, RwQualityBand.warn);
    }
  }
  return any ? band : RwQualityBand.none;
}

RwQualityBand _worse(RwQualityBand a, RwQualityBand b) {
  if (a == RwQualityBand.bad || b == RwQualityBand.bad) {
    return RwQualityBand.bad;
  }
  if (a == RwQualityBand.warn || b == RwQualityBand.warn) {
    return RwQualityBand.warn;
  }
  return RwQualityBand.good;
}

class _Samp {
  final DateTime at;
  final double? delayMs;
  final double? fps;
  const _Samp(this.at, this.delayMs, this.fps);
}

/// Rolling 3 s average of delay / frame-loss; color steps at most once per 2 s.
class RwQualityTracker {
  final _samples = <_Samp>[];
  RwQualityBand _shown = RwQualityBand.none;
  DateTime? _lastColorChange;
  DateTime? _ingestedEventAt;
  double _peakFps = 0;

  RwQualityView update({
    required DateTime now,
    DateTime? eventAt,
    double? delayMs,
    double? fps,
  }) {
    if (eventAt != null &&
        eventAt != _ingestedEventAt &&
        (delayMs != null || fps != null)) {
      _ingestedEventAt = eventAt;
      _samples.add(_Samp(eventAt, delayMs, fps));
      if (fps != null && fps > _peakFps) _peakFps = fps;
    }
    _samples.removeWhere((s) => now.difference(s.at) > kRwQualityAvgWindow);
    if (_samples.isEmpty ||
        now.difference(_samples.last.at) > kRwQualityStaleAfter) {
      _shown = RwQualityBand.none;
      _lastColorChange = now;
      return const RwQualityView(band: RwQualityBand.none);
    }

    final delays = _samples
        .map((s) => s.delayMs)
        .whereType<double>()
        .toList(growable: false);
    final fpss =
        _samples.map((s) => s.fps).whereType<double>().toList(growable: false);
    final avgDelay = delays.isEmpty
        ? null
        : delays.reduce((a, b) => a + b) / delays.length;
    final avgFps =
        fpss.isEmpty ? null : fpss.reduce((a, b) => a + b) / fpss.length;
    final lossPct = (avgFps == null || _peakFps <= 0)
        ? null
        : (100.0 * (1.0 - (avgFps / _peakFps)).clamp(0.0, 1.0));
    final band = rwQualityBand(delayMs: avgDelay, lossPct: lossPct);
    if (_shown != RwQualityBand.none &&
        band != _shown &&
        band != RwQualityBand.none &&
        _lastColorChange != null &&
        now.difference(_lastColorChange!) < kRwQualityColorHold) {
      // keep shown color
    } else if (band != _shown) {
      _shown = band;
      _lastColorChange = now;
    }
    return RwQualityView(band: _shown, delayMs: avgDelay, lossPct: lossPct);
  }
}

double? rwParseDelayMs(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return double.tryParse(raw.trim());
}

double? rwParseFps(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  double? minFps;
  for (final part in raw.split(RegExp(r'\s+'))) {
    final v = double.tryParse(part);
    if (v == null) continue;
    minFps = minFps == null ? v : math.min(minFps, v);
  }
  return minFps;
}

class RwQualityPill extends StatefulWidget {
  final FFI ffi;
  const RwQualityPill({super.key, required this.ffi});

  @override
  State<RwQualityPill> createState() => _RwQualityPillState();
}

class _RwQualityPillState extends State<RwQualityPill> {
  final RwQualityTracker _tracker = RwQualityTracker();
  Timer? _tick;
  RwQualityView _view = const RwQualityView(band: RwQualityBand.none);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) _refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _refresh() {
    final data = widget.ffi.qualityMonitorModel.data;
    final next = _tracker.update(
      now: DateTime.now(),
      eventAt: widget.ffi.qualityMonitorModel.lastUpdated,
      delayMs: rwParseDelayMs(data.delay),
      fps: rwParseFps(data.fps),
    );
    if (next.band != _view.band ||
        next.delayMs != _view.delayMs ||
        next.lossPct != _view.lossPct) {
      setState(() => _view = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.ffi.qualityMonitorModel,
      child: Consumer<QualityMonitorModel>(
        builder: (context, _, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refresh();
          });
          final p = rwOf(context);
          final view = _view;
          final Color color;
          switch (view.band) {
            case RwQualityBand.good:
              color = p.accent;
              break;
            case RwQualityBand.warn:
              color = p.yellow;
              break;
            case RwQualityBand.bad:
              color = p.danger;
              break;
            case RwQualityBand.none:
              color = p.muted;
              break;
          }
          final label = view.delayMs == null
              ? translate('— ms')
              : '${view.delayMs!.round()} ${translate('ms')}';
          final delayLine = view.delayMs == null
              ? translate('Delay: —')
              : translate('Delay: {} ms').replaceFirst(
                  '{}', '${view.delayMs!.round()}');
          final lossLine = view.lossPct == null
              ? translate('Packet loss: —')
              : translate('Packet loss: {}%').replaceFirst(
                  '{}', view.lossPct!.toStringAsFixed(1));
          final tip =
              '$delayLine\n$lossLine\n${translate('Average over 3 s')}';
          return Tooltip(
            message: tip,
            waitDuration: const Duration(milliseconds: 400),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withOpacity(0.45), width: 1),
              ),
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: RwFonts.body,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 16 / 12,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
