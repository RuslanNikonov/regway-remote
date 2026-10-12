import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../common/shared_state.dart';
import '../consts.dart';
import '../models/model.dart';
import 'theme.dart';

/// v3 quality pill: 3 bars + latency. Colour from delay only (≤80 green,
/// 81–200 yellow, >200 red, grey if stale >3 s). Frame-loss is tooltip-only:
/// RustDesk sends no frames on a still screen, so fps must not drive colour.
/// Reads QualityStatus / test_delay / speed already pushed to Flutter.
const double kRwQualityDelayGoodMs = 80;
const double kRwQualityDelayBadMs = 200;
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

/// Green: ≤80 ms. Yellow: 81–200 ms. Red: >200 ms. Frame-loss is ignored.
RwQualityBand rwQualityBand({double? delayMs}) {
  if (delayMs == null) return RwQualityBand.none;
  if (delayMs > kRwQualityDelayBadMs) return RwQualityBand.bad;
  if (delayMs > kRwQualityDelayGoodMs) return RwQualityBand.warn;
  return RwQualityBand.good;
}

class _Samp {
  final DateTime at;
  final double? delayMs;
  final double? fps;
  const _Samp(this.at, this.delayMs, this.fps);
}

/// Rolling 3 s average of delay (colour) and fps-derived frame-loss (tooltip);
/// colour steps at most once per 2 s.
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
    final band = rwQualityBand(delayMs: avgDelay);
    if (_shown != RwQualityBand.none &&
        band != _shown &&
        band != RwQualityBand.none &&
        _lastColorChange != null &&
        now.difference(_lastColorChange!) < kRwQualityColorHold) {
      // keep shown colour
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

Color rwQualityColor(RwPalette p, RwQualityBand band) {
  switch (band) {
    case RwQualityBand.good:
      return p.cosmicBackdrop
          ? const Color(0xFF34D399)
          : const Color(0xFF15915A);
    case RwQualityBand.warn:
      return p.yellow;
    case RwQualityBand.bad:
      return p.danger;
    case RwQualityBand.none:
      return p.muted;
  }
}

int rwQualityBarsFilled(RwQualityBand band) {
  switch (band) {
    case RwQualityBand.good:
      return 3;
    case RwQualityBand.warn:
      return 2;
    case RwQualityBand.bad:
      return 1;
    case RwQualityBand.none:
      return 0;
  }
}

class RwQualityPill extends StatefulWidget {
  final String id;
  final FFI ffi;
  const RwQualityPill({super.key, required this.id, required this.ffi});

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

  String _routeLabel() {
    try {
      final ct = ConnectionTypeState.find(widget.id);
      if (ct.direct.value == ConnectionType.strIndirect) {
        return translate('Via relay');
      }
      if (ct.direct.value != kInvalidValueStr) {
        return translate('Direct');
      }
    } catch (_) {}
    final d = widget.ffi.ffiModel.direct;
    if (d == true) return translate('Direct');
    if (d == false) return translate('Via relay');
    return '—';
  }

  String _statusLabel(RwQualityBand band) {
    switch (band) {
      case RwQualityBand.good:
        return translate('quality_good');
      case RwQualityBand.warn:
        return translate('quality_fair');
      case RwQualityBand.bad:
        return translate('quality_poor');
      case RwQualityBand.none:
        return translate('quality_unknown');
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
          final color = rwQualityColor(p, view.band);
          final label = view.delayMs == null
              ? translate('— ms')
              : '${view.delayMs!.round()} ${translate('ms')}';
          final delayLine = view.delayMs == null
              ? translate('Delay: —')
              : translate('Delay: {} ms')
                  .replaceFirst('{}', '${view.delayMs!.round()}');
          final lossLine = view.lossPct == null
              ? translate('Packet loss: —')
              : translate('Packet loss: {}%')
                  .replaceFirst('{}', view.lossPct!.toStringAsFixed(1));
          return Obx(() {
            final tip = [
              _statusLabel(view.band),
              delayLine,
              lossLine,
              _routeLabel(),
            ].join('\n');
            return Tooltip(
              message: tip,
              waitDuration: const Duration(milliseconds: 400),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withOpacity(0.45), width: 1),
                  boxShadow: p.cardShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RwSignalBars(
                      filled: rwQualityBarsFilled(view.band),
                      color: color,
                      empty: p.muted.withOpacity(0.35),
                    ),
                    const SizedBox(width: 7),
                    Text(
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
                  ],
                ),
              ),
            );
          });
        },
      ),
    );
  }
}

class _RwSignalBars extends StatelessWidget {
  final int filled;
  final Color color;
  final Color empty;
  const _RwSignalBars({
    required this.filled,
    required this.color,
    required this.empty,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 13,
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _bar(0, 4),
          const SizedBox(width: 2),
          _bar(1, 8),
          const SizedBox(width: 2),
          _bar(2, 12),
        ],
      ),
    );
  }

  Widget _bar(int index, double height) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: filled > index ? color : empty,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
