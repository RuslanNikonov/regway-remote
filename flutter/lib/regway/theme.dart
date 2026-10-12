import 'dart:ui';

import 'package:flutter/material.dart';

/// Design tokens from `tokens.md` / `client-base.css`.
class RwColors {
  RwColors._();

  static const Color bg = Color(0xFF04030B);
  static const Color bg2 = Color(0xFF0A0820);
  static const Color bg2Fill = Color(0xB80A0820); // 0.72
  static const Color inputFill = Color(0x9904030B); // 0.6
  static const Color text = Color(0xFFEEF0FF);
  static const Color muted = Color(0xFFA7ABC9);
  static const Color accent = Color(0xFF38D9FF);
  static const Color accentHover = Color(0xFF6BE3FF);
  static const Color onAccent = Color(0xFF04030B);
  static const Color violet = Color(0xFF7C5CFF);
  static const Color danger = Color(0xFFFF3D5E);
  static const Color warn = Color(0xFFFF7A2F);
  static const Color yellow = Color(0xFFFFC069);
  static const Color border = Color(0x1EA7ABC9); // 0.12
  static const Color navOnBg = Color(0x1F38D9FF); // 0.12
  static const Color navOnBorder = Color(0x7338D9FF); // 0.45
  static const Color toggleOff = Color(0x40A7ABC9); // 0.25
  static const Color ghostFill = Color(0x0DA7ABC9); // 0.05
  static const Color white = Color(0xFFFFFFFF);
}

class RwFonts {
  RwFonts._();
  static const String head = 'Unbounded';
  static const String body = 'Manrope';
}

class RwDim {
  RwDim._();
  static const double radiusField = 12;
  static const double radiusPanel = 16;
  static const double sidebar = 232;
  static const double sidebarNarrow = 208;
  static const double rail = 330;
  static const double railNarrow = 296;
  static const double gap = 20;
  static const double gapNarrow = 16;
  static const double pad = 20;
  static const double padNarrow = 16;
  static const double breakNarrow = 1300;
  static const double switchW = 42;
  static const double switchH = 24;
  static const double switchThumb = 18;
}

const List<FontFeature> kRwTabularFigures = [FontFeature.tabularFigures()];

class RwText {
  RwText._();

  static const TextStyle brand = TextStyle(
    fontFamily: RwFonts.head,
    fontWeight: FontWeight.w600,
    fontSize: 16,
    color: RwColors.text,
    height: 1.2,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: RwFonts.head,
    fontWeight: FontWeight.w600,
    fontSize: 26,
    color: RwColors.text,
    height: 1.2,
  );

  static const TextStyle h1Narrow = TextStyle(
    fontFamily: RwFonts.head,
    fontWeight: FontWeight.w600,
    fontSize: 22,
    color: RwColors.text,
    height: 1.2,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: RwFonts.head,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    color: RwColors.text,
    height: 1.2,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: RwFonts.head,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    color: RwColors.text,
    height: 1.2,
  );

  static const TextStyle body = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    color: RwColors.text,
    height: 1.35,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    color: RwColors.text,
    height: 1.35,
  );

  static const TextStyle muted = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    color: RwColors.muted,
    height: 1.35,
  );

  static const TextStyle label = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 12.5,
    color: RwColors.muted,
    height: 1.3,
  );

  static const TextStyle nav = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    color: RwColors.muted,
    height: 1.2,
  );

  static const TextStyle btn = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    color: RwColors.onAccent,
    height: 1.2,
  );

  static const TextStyle link = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: RwColors.accent,
    height: 1.2,
  );

  static const TextStyle num = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    color: RwColors.text,
    letterSpacing: 0.04 * 22,
    fontFeatures: kRwTabularFigures,
    height: 1.2,
  );

  static const TextStyle numSm = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: RwColors.text,
    fontFeatures: kRwTabularFigures,
    height: 1.2,
  );

  static const TextStyle error = TextStyle(
    fontFamily: RwFonts.body,
    fontWeight: FontWeight.w500,
    fontSize: 12.5,
    color: RwColors.danger,
    height: 1.3,
  );
}

class RwDecor {
  RwDecor._();

  static BoxDecoration get panel => BoxDecoration(
        color: RwColors.bg2Fill,
        borderRadius: BorderRadius.circular(RwDim.radiusPanel),
        border: Border.all(color: RwColors.border, width: 1),
      );

  static BoxDecoration get input => BoxDecoration(
        color: RwColors.inputFill,
        borderRadius: BorderRadius.circular(RwDim.radiusField),
        border: Border.all(color: RwColors.border, width: 1),
      );

  static const LinearGradient avatar = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [RwColors.violet, RwColors.accent],
  );

  static const LinearGradient wallpaper1 = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0x994B3AA8),
      Color(0xFF0A0820),
      Color(0x8C1A6A7A),
    ],
  );

  static const LinearGradient wallpaper2 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x8C4B3AA8),
      Color(0xFF0A0820),
      Color(0x661A3A6A),
    ],
  );

  static const LinearGradient wallpaperOffline = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14122B), Color(0xFF0A0820)],
  );

  static BoxDecoration cosmicBg() => const BoxDecoration(
        color: RwColors.bg,
        gradient: RadialGradient(
          center: Alignment(0.8, -1.1),
          radius: 1.15,
          colors: [Color(0x2E7C5CFF), Color(0x0004030B)],
          stops: [0.0, 0.6],
        ),
      );
}

/// Shared button / switch / input styles wired into [ThemeData].
ButtonStyle rwFilledButtonStyle() {
  return ButtonStyle(
    elevation: const MaterialStatePropertyAll(0),
    backgroundColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.disabled)) {
        return RwColors.accent.withOpacity(0.35);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.pressed)) {
        return RwColors.accentHover;
      }
      return RwColors.accent;
    }),
    foregroundColor: const MaterialStatePropertyAll(RwColors.onAccent),
    shadowColor: const MaterialStatePropertyAll(Colors.transparent),
    overlayColor: const MaterialStatePropertyAll(Colors.transparent),
    padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
    shape: MaterialStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
    )),
    textStyle: const MaterialStatePropertyAll(RwText.btn),
  );
}

ButtonStyle rwGhostButtonStyle() {
  return ButtonStyle(
    elevation: const MaterialStatePropertyAll(0),
    backgroundColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.hovered)) {
        return RwColors.ghostFill;
      }
      return const Color(0x0DA7ABC9);
    }),
    foregroundColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.disabled)) {
        return RwColors.muted.withOpacity(0.6);
      }
      return RwColors.text;
    }),
    shadowColor: const MaterialStatePropertyAll(Colors.transparent),
    overlayColor: const MaterialStatePropertyAll(Colors.transparent),
    padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
    side: const MaterialStatePropertyAll(BorderSide(color: RwColors.border)),
    shape: MaterialStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
    )),
    textStyle: const MaterialStatePropertyAll(RwText.bodyStrong),
  );
}

SwitchThemeData rwSwitchTheme() {
  return SwitchThemeData(
    splashRadius: 0,
    thumbColor: MaterialStateProperty.resolveWith((states) => RwColors.white),
    trackOutlineColor: const MaterialStatePropertyAll(Colors.transparent),
    trackColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return RwColors.accent;
      }
      return RwColors.toggleOff;
    }),
  );
}

InputDecorationTheme rwInputDecorationTheme() {
  return InputDecorationTheme(
    filled: true,
    fillColor: RwColors.inputFill,
    isDense: true,
    hintStyle: RwText.muted,
    labelStyle: RwText.label,
    errorStyle: RwText.error,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: const BorderSide(color: RwColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: const BorderSide(color: RwColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: const BorderSide(color: RwColors.accent, width: 1),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: const BorderSide(color: RwColors.danger),
    ),
  );
}
