import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../common.dart';
import 'theme.dart';

/// C10 / C11 reconnect overlay. Survives toolbar collapse; driven by [RwReconnect].
class RwReconnect {
  RwReconnect._();
  static final active = false.obs;
  static final attempt = 1.obs;
  static final started = DateTime.now().obs;
  static final accessClosed = false.obs;
  static Timer? _tick;
  static bool _wasActive = false;

  static void begin() {
    if (!active.value) {
      started.value = DateTime.now();
      attempt.value = 1;
    } else {
      attempt.value = attempt.value + 1;
    }
    active.value = true;
    accessClosed.value = false;
    _wasActive = true;
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!active.value) return;
      if (DateTime.now().difference(started.value).inSeconds >= 60) {
        accessClosed.value = true;
      }
    });
  }

  static void restored() {
    if (!_wasActive && !active.value) return;
    active.value = false;
    accessClosed.value = false;
    _tick?.cancel();
    if (_wasActive) {
      _wasActive = false;
      final dark = !(Get.isDarkMode == false) &&
          (Get.context == null ||
              Theme.of(Get.context!).brightness == Brightness.dark);
      BotToast.showText(
        text: translate('Connection restored'),
        duration: const Duration(seconds: 3),
        contentColor: dark ? const Color(0xFF3DDC97) : const Color(0xFF12A36A),
      );
    }
  }

  static void stop() {
    active.value = false;
    accessClosed.value = false;
    _wasActive = false;
    _tick?.cancel();
  }
}

class RwReconnectOverlay extends StatelessWidget {
  final VoidCallback onDisconnect;
  const RwReconnectOverlay({super.key, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!RwReconnect.active.value) return const Offstage();
      final p = rwOf(context);
      final closed = RwReconnect.accessClosed.value;
      final elapsed = DateTime.now().difference(RwReconnect.started.value);
      final mm = elapsed.inMinutes.remainder(60).toString().padLeft(1, '0');
      final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
      return Positioned.fill(
        child: Container(
          color: p.bg.withOpacity(0.6),
          alignment: Alignment.center,
          child: Container(
            width: 360,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: closed ? p.danger.withOpacity(0.45) : p.cardBorder,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!closed)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: p.accent,
                    ),
                  ),
                if (!closed) const SizedBox(height: 14),
                Text(
                  closed
                      ? translate(
                          'Access closed. It will restore itself when the connection returns')
                      : translate('Connection lost, reconnecting…'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: RwFonts.body,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.3,
                    color: p.text,
                  ),
                ),
                if (!closed) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${translate('Attempt')} ${RwReconnect.attempt.value} · $mm:$ss',
                    style: p.textMuted.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (closed) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: RwGhostDisconnect(onTap: onDisconnect),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => launchUrlString(
                            'https://remote.regway.group/help/#no-server'),
                        child: Text(translate('Help'),
                            style: p.textLink.copyWith(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

class RwGhostDisconnect extends StatelessWidget {
  final VoidCallback onTap;
  const RwGhostDisconnect({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: BorderSide(color: p.cardBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(translate('Disconnect')),
    );
  }
}
