import 'dart:ui';

import 'package:flutter/material.dart';

/// Design tokens from `tokens.md` v1 (dark) and v2 (light + card contrast).
/// Prefer [RwPalette.of] so light/dark follow ThemeMode. [RwColors] stays the
/// dark fallback for call sites without a [BuildContext].
class RwColors {
  RwColors._();

  static const Color bg = Color(0xFF04030B);
  static const Color bg2 = Color(0xFF0A0820);
  static const Color bg2Fill = Color(0xFF15123A);
  static const Color card = Color(0xFF15123A);
  static const Color cardHover = Color(0xFF1C1848);
  static const Color inputFill = Color(0x9904030B); // 0.6
  static const Color text = Color(0xFFEEF0FF);
  static const Color muted = Color(0xFFA7ABC9);
  static const Color accent = Color(0xFF38D9FF);
  static const Color accentHover = Color(0xFF6BE3FF);
  static const Color onAccent = Color(0xFF04030B);
  static const Color violet = Color(0xFF7C5CFF);
  static const Color danger = Color(0xFFFF3D5E);
  static const Color dangerHover = Color(0xFFFF5A75);
  static const Color warn = Color(0xFFFF7A2F);
  static const Color yellow = Color(0xFFFFC069);
  static const Color border = Color(0x38A7ABC9); // 0.22
  static const Color focusBorder = Color(0x7338D9FF); // 0.45
  static const Color navOnBg = Color(0x1F38D9FF); // 0.12
  static const Color navOnBorder = Color(0x7338D9FF); // 0.45
  static const Color toggleOff = Color(0x40A7ABC9); // 0.25
  static const Color ghostFill = Color(0x0DA7ABC9); // 0.05
  static const Color white = Color(0xFFFFFFFF);
}

/// Light/dark palette. Wired into [ThemeData.extensions].
@immutable
class RwPalette extends ThemeExtension<RwPalette> {
  final Color bg;
  final Color bg2;
  final Color card;
  final Color cardHover;
  final Color inputFill;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentHover;
  final Color onAccent;
  final Color violet;
  final Color danger;
  final Color dangerHover;
  final Color warn;
  final Color yellow;
  final Color border;
  final Color cardBorder;
  final Color focusBorder;
  final Color navOnBg;
  final Color navOnBorder;
  final Color toggleOff;
  final Color ghostFill;
  final Color white;
  final List<BoxShadow> cardShadow;
  final bool cosmicBackdrop;

  const RwPalette({
    required this.bg,
    required this.bg2,
    required this.card,
    required this.cardHover,
    required this.inputFill,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentHover,
    required this.onAccent,
    required this.violet,
    required this.danger,
    required this.dangerHover,
    required this.warn,
    required this.yellow,
    required this.border,
    required this.cardBorder,
    required this.focusBorder,
    required this.navOnBg,
    required this.navOnBorder,
    required this.toggleOff,
    required this.ghostFill,
    required this.white,
    required this.cardShadow,
    required this.cosmicBackdrop,
  });

  static const dark = RwPalette(
    bg: Color(0xFF04030B),
    bg2: Color(0xFF0A0820),
    card: Color(0xFF15123A),
    cardHover: Color(0xFF1C1848),
    inputFill: Color(0x9904030B),
    text: Color(0xFFEEF0FF),
    muted: Color(0xFFA7ABC9),
    accent: Color(0xFF38D9FF),
    accentHover: Color(0xFF6BE3FF),
    onAccent: Color(0xFF04030B),
    violet: Color(0xFF7C5CFF),
    danger: Color(0xFFFF3D5E),
    dangerHover: Color(0xFFFF5A75),
    warn: Color(0xFFFF7A2F),
    yellow: Color(0xFFFFC069),
    border: Color(0x38A7ABC9),
    cardBorder: Color(0x38A7ABC9),
    focusBorder: Color(0x7338D9FF),
    navOnBg: Color(0x1F38D9FF),
    navOnBorder: Color(0x7338D9FF),
    toggleOff: Color(0x40A7ABC9),
    ghostFill: Color(0x0DA7ABC9),
    white: Color(0xFFFFFFFF),
    cardShadow: [],
    cosmicBackdrop: true,
  );

  static const light = RwPalette(
    bg: Color(0xFFF4F5FB),
    bg2: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardHover: Color(0xFFFFFFFF),
    inputFill: Color(0xFFFFFFFF),
    text: Color(0xFF14122B),
    muted: Color(0xFF5D6180),
    accent: Color(0xFF0A9CC2),
    accentHover: Color(0xFF0889AB),
    onAccent: Color(0xFFFFFFFF),
    violet: Color(0xFF7C5CFF),
    danger: Color(0xFFD41E48),
    dangerHover: Color(0xFFB8193E),
    warn: Color(0xFFFF7A2F),
    yellow: Color(0xFFFFC069),
    border: Color(0xFFDFE1EE),
    cardBorder: Color(0xFFDFE1EE),
    focusBorder: Color(0x730A9CC2),
    navOnBg: Color(0x1F0A9CC2),
    navOnBorder: Color(0x730A9CC2),
    toggleOff: Color(0x405D6180),
    ghostFill: Color(0x0D5D6180),
    white: Color(0xFFFFFFFF),
    cardShadow: [
      BoxShadow(
        color: Color(0x140A0820),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
    cosmicBackdrop: false,
  );

  static RwPalette of(BuildContext context) {
    return Theme.of(context).extension<RwPalette>() ?? RwPalette.dark;
  }

  TextStyle get textBrand => RwText.brand.copyWith(color: text);
  TextStyle get textH1 => RwText.h1.copyWith(color: text);
  TextStyle get textH1Narrow => RwText.h1Narrow.copyWith(color: text);
  TextStyle get textH2 => RwText.h2.copyWith(color: text);
  TextStyle get textH3 => RwText.h3.copyWith(color: text);
  TextStyle get textBody => RwText.body.copyWith(color: text);
  TextStyle get textBodyStrong => RwText.bodyStrong.copyWith(color: text);
  TextStyle get textMuted => RwText.muted.copyWith(color: muted);
  TextStyle get textLabel => RwText.label.copyWith(color: muted);
  TextStyle get textNav => RwText.nav.copyWith(color: muted);
  TextStyle get textBtn => RwText.btn.copyWith(color: onAccent);
  TextStyle get textLink => RwText.link.copyWith(color: accent);
  TextStyle get textNum => RwText.num.copyWith(color: text);
  TextStyle get textNumSm => RwText.numSm.copyWith(color: text);
  TextStyle get textError => RwText.error.copyWith(color: danger);

  @override
  RwPalette copyWith({
    Color? bg,
    Color? bg2,
    Color? card,
    Color? cardHover,
    Color? inputFill,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentHover,
    Color? onAccent,
    Color? violet,
    Color? danger,
    Color? dangerHover,
    Color? warn,
    Color? yellow,
    Color? border,
    Color? cardBorder,
    Color? focusBorder,
    Color? navOnBg,
    Color? navOnBorder,
    Color? toggleOff,
    Color? ghostFill,
    Color? white,
    List<BoxShadow>? cardShadow,
    bool? cosmicBackdrop,
  }) {
    return RwPalette(
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      card: card ?? this.card,
      cardHover: cardHover ?? this.cardHover,
      inputFill: inputFill ?? this.inputFill,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      onAccent: onAccent ?? this.onAccent,
      violet: violet ?? this.violet,
      danger: danger ?? this.danger,
      dangerHover: dangerHover ?? this.dangerHover,
      warn: warn ?? this.warn,
      yellow: yellow ?? this.yellow,
      border: border ?? this.border,
      cardBorder: cardBorder ?? this.cardBorder,
      focusBorder: focusBorder ?? this.focusBorder,
      navOnBg: navOnBg ?? this.navOnBg,
      navOnBorder: navOnBorder ?? this.navOnBorder,
      toggleOff: toggleOff ?? this.toggleOff,
      ghostFill: ghostFill ?? this.ghostFill,
      white: white ?? this.white,
      cardShadow: cardShadow ?? this.cardShadow,
      cosmicBackdrop: cosmicBackdrop ?? this.cosmicBackdrop,
    );
  }

  @override
  RwPalette lerp(ThemeExtension<RwPalette>? other, double t) {
    if (other is! RwPalette) return this;
    return t < 0.5 ? this : other;
  }
}

RwPalette rwOf(BuildContext context) => RwPalette.of(context);

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

  static BoxDecoration get panel => panelOf(RwPalette.dark);

  static BoxDecoration panelOf(RwPalette p, {bool hover = false, bool focus = false}) {
    return BoxDecoration(
      color: hover ? p.cardHover : p.card,
      borderRadius: BorderRadius.circular(RwDim.radiusPanel),
      border: Border.all(
        color: (hover || focus) ? p.focusBorder : p.cardBorder,
        width: 1,
      ),
      boxShadow: p.cardShadow,
    );
  }

  static BoxDecoration get input => inputOf(RwPalette.dark);

  static BoxDecoration inputOf(RwPalette p) => BoxDecoration(
        color: p.inputFill,
        borderRadius: BorderRadius.circular(RwDim.radiusField),
        border: Border.all(color: p.cardBorder, width: 1),
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

  static const LinearGradient wallpaper1Light = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0x337C5CFF),
      Color(0xFFF4F5FB),
      Color(0x330A9CC2),
    ],
  );

  static const LinearGradient wallpaper2Light = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x337C5CFF),
      Color(0xFFF4F5FB),
      Color(0x2214122B),
    ],
  );

  static const LinearGradient wallpaperOfflineLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8EAF4), Color(0xFFF4F5FB)],
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
ButtonStyle rwFilledButtonStyle([RwPalette p = RwPalette.dark]) {
  return ButtonStyle(
    elevation: const MaterialStatePropertyAll(0),
    backgroundColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.disabled)) {
        return p.accent.withOpacity(0.35);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.pressed)) {
        return p.accentHover;
      }
      return p.accent;
    }),
    foregroundColor: MaterialStatePropertyAll(p.onAccent),
    shadowColor: const MaterialStatePropertyAll(Colors.transparent),
    overlayColor: const MaterialStatePropertyAll(Colors.transparent),
    padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
    shape: MaterialStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
    )),
    textStyle: MaterialStatePropertyAll(p.textBtn),
  );
}

ButtonStyle rwGhostButtonStyle([RwPalette p = RwPalette.dark]) {
  return ButtonStyle(
    elevation: const MaterialStatePropertyAll(0),
    backgroundColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.hovered)) {
        return p.ghostFill;
      }
      return p.ghostFill;
    }),
    foregroundColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.disabled)) {
        return p.muted.withOpacity(0.6);
      }
      return p.text;
    }),
    shadowColor: const MaterialStatePropertyAll(Colors.transparent),
    overlayColor: const MaterialStatePropertyAll(Colors.transparent),
    padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
    side: MaterialStatePropertyAll(BorderSide(color: p.cardBorder)),
    shape: MaterialStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
    )),
    textStyle: MaterialStatePropertyAll(p.textBodyStrong),
  );
}

SwitchThemeData rwSwitchTheme([RwPalette p = RwPalette.dark]) {
  return SwitchThemeData(
    splashRadius: 0,
    thumbColor: MaterialStateProperty.resolveWith((states) => p.white),
    trackOutlineColor: const MaterialStatePropertyAll(Colors.transparent),
    trackColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) {
        return p.accent;
      }
      return p.toggleOff;
    }),
  );
}

InputDecorationTheme rwInputDecorationTheme([RwPalette p = RwPalette.dark]) {
  return InputDecorationTheme(
    filled: true,
    fillColor: p.inputFill,
    isDense: true,
    hintStyle: p.textMuted,
    labelStyle: p.textLabel,
    errorStyle: p.textError,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: BorderSide(color: p.cardBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: BorderSide(color: p.cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: BorderSide(color: p.focusBorder, width: 1),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(RwDim.radiusField),
      borderSide: BorderSide(color: p.danger),
    ),
  );
}
