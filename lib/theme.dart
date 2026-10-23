import 'package:flutter/material.dart';

class TinColors {
  static const cream = Color(0xFFFBF6F0);
  static const coral = Color(0xFFF2553A);
  static const green = Color(0xFF10A877);
  static const peach = Color(0xFFFFDCCB);
  static const ink = Color(0xFF2B1F1A);
  static const dark = Color(0xFF201A17);
  static const darkCard = Color(0xFF302823);
}

ThemeData tinTheme({required bool dark}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: TinColors.coral,
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: dark ? TinColors.dark : TinColors.cream,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? TinColors.dark : TinColors.cream,
    fontFamily: 'Plus Jakarta Sans',
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
        .textTheme
        .apply(
          fontFamily: 'Plus Jakarta Sans',
          bodyColor: dark ? Colors.white : TinColors.ink,
          displayColor: dark ? Colors.white : TinColors.ink,
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? TinColors.dark : TinColors.cream,
      foregroundColor: dark ? Colors.white : TinColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Bricolage Grotesque',
        fontSize: 23,
        fontWeight: FontWeight.w800,
        color: dark ? Colors.white : TinColors.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF2B2420) : Colors.white,
      hintStyle: TextStyle(
        color: dark ? Colors.white38 : TinColors.ink.withValues(alpha: .42),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: dark ? Colors.white10 : TinColors.ink.withValues(alpha: .06),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: TinColors.coral, width: 1.4),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

bool batterySaverMode = false;

bool get motionReduced =>
    batterySaverMode ||
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child, this.safeArea = true});
  final Widget child;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: safeArea ? SafeArea(child: child) : child);
  }
}
