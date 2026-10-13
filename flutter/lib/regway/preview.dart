import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/peer_model.dart';
import 'theme.dart';

/// C5: online = 2–3 radial blobs (accent / violet / orange) on `card`, colours
/// from the ID hash. Offline = flat `card-hover` + 24px muted OS icon.
/// Recent table thumb: 36×24, r=6.
class RwPeerPreview extends StatelessWidget {
  final Peer peer;
  final double? width;
  final double? height;
  final double radius;
  const RwPeerPreview({
    super.key,
    required this.peer,
    this.width,
    this.height,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    if (!peer.online) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: p.cardHover,
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: Alignment.center,
        child: Icon(rwOsIcon(peer.platform), size: 24, color: p.muted),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: p.card,
        child: CustomPaint(
          painter: _BlobPainter(seed: peer.id.hashCode, p: p),
        ),
      ),
    );
  }
}

IconData rwOsIcon(String platform) {
  switch (platform.toLowerCase()) {
    case 'windows':
      return Icons.window;
    case 'macos':
    case 'osx':
    case 'darwin':
      return Icons.laptop_mac;
    case 'linux':
      return Icons.computer;
    case 'android':
      return Icons.phone_android;
    case 'ios':
      return Icons.phone_iphone;
    default:
      return Icons.devices;
  }
}

class _BlobPainter extends CustomPainter {
  final int seed;
  final RwPalette p;
  _BlobPainter({required this.seed, required this.p});

  @override
  void paint(Canvas canvas, Size size) {
    final colors = <Color>[p.accent, p.violet, p.warn];
    final n = 2 + (seed.abs() % 2); // 2 or 3
    for (var i = 0; i < n; i++) {
      final h = (seed + i * 9973).abs();
      final cx = size.width * (0.18 + ((h >> 3) % 70) / 100.0);
      final cy = size.height * (0.18 + ((h >> 7) % 70) / 100.0);
      final r = (size.shortestSide) * (0.35 + ((h >> 11) % 30) / 100.0);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i % colors.length].withOpacity(0.55),
            colors[i % colors.length].withOpacity(0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.seed != seed || old.p.accent != p.accent;
}
