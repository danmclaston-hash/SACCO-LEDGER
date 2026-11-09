import 'package:flutter/material.dart';

import '../core/catalog.dart';

export '../core/catalog.dart' show AppLook;

// Brand colours of the first look. Screens should read colours from the theme; these stay for the few fixed marks.
const saccoEmerald = Color(0xFF0B3D33);
const saccoEmeraldLight = Color(0xFF00796B);
const saccoGold = Color(0xFFE0A526);
const saccoGoldLight = Color(0xFFFFD54F);
const okGreen = Color(0xFF2E7D32);
const okGreenBg = Color(0xFFE8F5E9);
const warnOrange = Color(0xFFE65100);

/// What a look adds on top of the Material colour scheme.
@immutable
class SaccoLook extends ThemeExtension<SaccoLook> {
  final AppLook look;

  /// The strip at the top of every page, and the sign-in and lock screens.
  final Color brand;
  final Color onBrand;
  final Color onBrandMuted;

  /// The one colour that marks the main action and the group's mark on the brand strip.
  final Color accent;
  final Color onAccent;
  final double radius;

  /// Money and reference numbers. Passbook uses a typewriter face so digits line up.
  final String? numberFont;
  final Color ok;
  final Color okBg;
  final Color warn;

  const SaccoLook({
    required this.look,
    required this.brand,
    required this.onBrand,
    required this.onBrandMuted,
    required this.accent,
    required this.onAccent,
    required this.radius,
    required this.numberFont,
    required this.ok,
    required this.okBg,
    required this.warn,
  });

  static SaccoLook of(BuildContext context) => Theme.of(context).extension<SaccoLook>()!;

  bool get isPassbook => look == AppLook.passbook;
  TextStyle numbers(TextStyle? base) {
    final b = base ?? const TextStyle();
    return numberFont == null ? b : b.copyWith(fontFamily: numberFont, fontFeatures: const [FontFeature.tabularFigures()]);
  }

  @override
  SaccoLook copyWith() => this;
  @override
  SaccoLook lerp(ThemeExtension<SaccoLook>? other, double t) => t < 0.5 || other is! SaccoLook ? this : other;
}

const _emeraldLight = ColorScheme(
  brightness: Brightness.light,
  primary: saccoEmerald,
  onPrimary: Color(0xFFF6F3EC),
  primaryContainer: Color(0xFFD5E6DF),
  onPrimaryContainer: Color(0xFF07332A),
  secondary: saccoGold,
  onSecondary: Color(0xFF1A1404),
  secondaryContainer: Color(0xFFF3E7C6),
  onSecondaryContainer: Color(0xFF3A2A00),
  tertiary: Color(0xFF1F6B5C),
  onTertiary: Colors.white,
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF14231F),
  surfaceContainerHighest: Color(0xFFECE8DC),
  onSurfaceVariant: Color(0xFF55655F),
  outline: Color(0xFF7B877F),
  outlineVariant: Color(0xFFD9D3C3),
);

const _emeraldDark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF6FCBBB),
  onPrimary: Color(0xFF00382F),
  primaryContainer: Color(0xFF0F4A3E),
  onPrimaryContainer: Color(0xFFBFEDE3),
  secondary: saccoGold,
  onSecondary: Color(0xFF1A1404),
  secondaryContainer: Color(0xFF4F3B05),
  onSecondaryContainer: Color(0xFFFFE2A0),
  tertiary: Color(0xFF80CBC4),
  onTertiary: Color(0xFF00201B),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF0E3029),
  onSurface: Color(0xFFF4F1E8),
  surfaceContainerHighest: Color(0xFF164238),
  onSurfaceVariant: Color(0xFFB9CFC8),
  outline: Color(0xFF7FA097),
  outlineVariant: Color(0xFF2A554A),
);

const _ink = Color(0xFF14213D);
const _paper = Color(0xFFFAF7F0);
const _stamp = Color(0xFFB23A22);

const _passbookLight = ColorScheme(
  brightness: Brightness.light,
  primary: _ink,
  onPrimary: _paper,
  primaryContainer: Color(0xFFDDE3F0),
  onPrimaryContainer: Color(0xFF0E1A30),
  secondary: _stamp,
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFF6DDD6),
  onSecondaryContainer: Color(0xFF4A1408),
  tertiary: Color(0xFF34466B),
  onTertiary: Colors.white,
  error: Color(0xFFA3211A),
  onError: Colors.white,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFFFFFFF),
  onSurface: _ink,
  surfaceContainerHighest: Color(0xFFEFEADD),
  onSurfaceVariant: Color(0xFF4A5670),
  outline: Color(0xFF6B7690),
  outlineVariant: Color(0xFFC9C1AE),
);

const _passbookDark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFB4C6EE),
  onPrimary: Color(0xFF0E1A30),
  primaryContainer: Color(0xFF263A63),
  onPrimaryContainer: Color(0xFFDCE5FA),
  secondary: Color(0xFFF3A48E),
  onSecondary: Color(0xFF3A0E04),
  secondaryContainer: Color(0xFF6B2415),
  onSecondaryContainer: Color(0xFFFFDAD0),
  tertiary: Color(0xFFAEB9CE),
  onTertiary: Color(0xFF0E1A30),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF1B2B4B),
  onSurface: Color(0xFFF3EEE2),
  surfaceContainerHighest: Color(0xFF263A63),
  onSurfaceVariant: Color(0xFFAEB9CE),
  outline: Color(0xFF7C8BAA),
  outlineVariant: Color(0xFF34466B),
);

ThemeData themeFor(AppLook look, Brightness b) {
  final dark = b == Brightness.dark;
  final passbook = look == AppLook.passbook;
  final c = passbook ? (dark ? _passbookDark : _passbookLight) : (dark ? _emeraldDark : _emeraldLight);
  final background = passbook ? (dark ? const Color(0xFF0E1A30) : _paper) : (dark ? const Color(0xFF072B24) : const Color(0xFFF6F3EC));
  final ext = passbook
      ? SaccoLook(
          look: look,
          brand: dark ? const Color(0xFF0A1425) : _ink,
          onBrand: const Color(0xFFF3EEE2),
          onBrandMuted: const Color(0xFFAEB9CE),
          accent: dark ? const Color(0xFFF3A48E) : _stamp,
          onAccent: dark ? const Color(0xFF3A0E04) : Colors.white,
          radius: 6,
          numberFont: 'IBMPlexMono',
          ok: dark ? const Color(0xFF8FD3A8) : const Color(0xFF1E6B3A),
          okBg: dark ? const Color(0xFF173B2A) : const Color(0xFFDDEFE3),
          warn: dark ? const Color(0xFFFFB877) : const Color(0xFFA84A00),
        )
      : SaccoLook(
          look: look,
          brand: dark ? const Color(0xFF051F1A) : saccoEmerald,
          onBrand: const Color(0xFFF4F1E8),
          onBrandMuted: const Color(0xFFB9CFC8),
          accent: saccoGold,
          onAccent: const Color(0xFF1A1404),
          radius: 20,
          numberFont: null,
          ok: dark ? const Color(0xFF8FD3A8) : const Color(0xFF0B5A3C),
          okBg: dark ? const Color(0xFF14402F) : const Color(0xFFDCEFE6),
          warn: dark ? const Color(0xFFFFB877) : const Color(0xFFA84A00),
        );
  final r = BorderRadius.circular(passbook ? 6 : 14);
  final base = ThemeData(useMaterial3: true, colorScheme: c, fontFamily: passbook ? 'IBMPlexSans' : 'PlusJakartaSans');
  return base.copyWith(
    extensions: [ext],
    scaffoldBackgroundColor: background,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: passbook ? c.primaryContainer : c.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(passbook ? 6 : 16)),
      elevation: 0,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 12, letterSpacing: 0, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500, color: c.onSurface),
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ext.radius), side: BorderSide(color: c.outlineVariant)),
    ),
    dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(passbook ? 8 : 24))),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(passbook ? 8 : 24))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: c.outline)),
      filled: true,
      fillColor: c.surface,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: r),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: r),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: RoundedRectangleBorder(borderRadius: r), side: BorderSide(color: c.outline)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 44), shape: RoundedRectangleBorder(borderRadius: r))),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(passbook ? 4 : 10))),
    dividerTheme: DividerThemeData(color: c.outlineVariant, space: 16),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()}),
  );
}

// Kept for the first screen shown before a person's settings load.
final lightTheme = themeFor(AppLook.emerald, Brightness.light);
final darkTheme = themeFor(AppLook.emerald, Brightness.dark);

// ---------------- Payment brands ----------------
// Colours as the networks use them, so people recognise them at a glance.
// Logos are NOT drawn here: they belong to MTN, Airtel and Safaricom. To show the real logos,
// put the official files you have permission to use in assets/brands/ (see the README there).
class Brand {
  final Color color;
  final Color onColor;
  final IconData icon;
  final String? logo; // asset path, shown only if the file is there
  const Brand(this.color, this.onColor, this.icon, [this.logo]);
}

/// The look of each payment channel (core/catalog.dart), by its code.
const brands = <String, Brand>{
  'mtn_momo': Brand(Color(0xFFFFCB05), Color(0xFF000000), Icons.phone_android, 'assets/brands/mtn.png'),
  'airtel_money': Brand(Color(0xFFE40000), Color(0xFFFFFFFF), Icons.phone_android, 'assets/brands/airtel.png'),
  'bank': Brand(Color(0xFF1F4E79), Color(0xFFFFFFFF), Icons.account_balance),
  'cash': Brand(Color(0xFF2E7D32), Color(0xFFFFFFFF), Icons.payments_outlined),
  'flutterwave': Brand(Color(0xFFF5A623), Color(0xFF000000), Icons.verified_user, 'assets/brands/flutterwave.png'),
  'pesapal': Brand(Color(0xFF26338F), Color(0xFFFFFFFF), Icons.verified_user, 'assets/brands/pesapal.png'),
};
