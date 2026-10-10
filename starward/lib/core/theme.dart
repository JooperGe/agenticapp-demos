import 'package:flutter/material.dart';

/// Central visual language for Starward.
///
/// Deep-space base tones with a calm cyan accent — "cozy sci-fi" rather than
/// high-saturation cyberpunk. Every panel in the app is a translucent dark
/// surface so the starfield behind it keeps showing through, which is what
/// gives the UI its sense of depth.
class StarColors {
  StarColors._();

  // Base space tones. Never pure black — there is always a trace of navy/violet.
  static const Color abyss = Color(0xFF070B16);
  static const Color deepNavy = Color(0xFF0B1230);
  static const Color navy = Color(0xFF121A3A);
  static const Color violet = Color(0xFF1C1B4B);

  // Accents.
  static const Color cyan = Color(0xFF7FE3E0);
  static const Color cyanDim = Color(0xFF4FB9C4);
  static const Color gold = Color(0xFFF2C879);
  static const Color coral = Color(0xFFF2998A);
  static const Color flora = Color(0xFF8EE6B0);
  static const Color danger = Color(0xFFFF9A8E);

  // Text.
  static const Color offWhite = Color(0xFFF2F1EA);
  static const Color muted = Color(0xFFAEB7D6);
  static const Color faint = Color(0xFF6D77A0);

  // Translucent panel fills.
  static const Color panel = Color(0xE60C1430);
  static const Color panelLight = Color(0xCC16204A);
  static const Color panelBorder = Color(0x33A9C6FF);
}

/// Reusable gradients for backgrounds and planet discs.
class StarGradients {
  StarGradients._();

  /// The default full-screen deep-space backdrop.
  static const LinearGradient space = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF0A0F24),
      Color(0xFF0B1230),
      Color(0xFF140F2E),
    ],
  );
}

ThemeData buildStarwardTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: StarColors.abyss,
    colorScheme: base.colorScheme.copyWith(
      surface: StarColors.deepNavy,
      primary: StarColors.cyan,
      secondary: StarColors.gold,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: StarColors.offWhite,
      displayColor: StarColors.offWhite,
      fontFamily: 'SF Pro Text',
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: StarColors.cyan,
      thumbColor: StarColors.cyan,
      inactiveTrackColor: StarColors.panelLight,
    ),
  );
}

/// Shared decoration for the translucent info panels used across pages.
BoxDecoration panelDecoration({
  Color? color,
  double radius = 18,
  Color? border,
}) {
  return BoxDecoration(
    color: color ?? StarColors.panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border ?? StarColors.panelBorder),
    boxShadow: const <BoxShadow>[
      BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 8)),
    ],
  );
}
