import 'package:flutter/material.dart';

// Same colours as the original Android app.
const saccoEmerald = Color(0xFF004D40);
const saccoEmeraldLight = Color(0xFF00796B);
const saccoGold = Color(0xFFE5A00D);
const saccoGoldLight = Color(0xFFFFD54F);
const okGreen = Color(0xFF2E7D32);
const okGreenBg = Color(0xFFE8F5E9);
const warnOrange = Color(0xFFE65100);

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: saccoEmerald,
  onPrimary: Colors.white,
  // Calm, not glowing: soft mint and sand instead of bright cyan and peach.
  primaryContainer: Color(0xFFCFE6DF),
  onPrimaryContainer: Color(0xFF00382F),
  secondary: saccoGold,
  onSecondary: Colors.black,
  secondaryContainer: Color(0xFFF1E6CC),
  onSecondaryContainer: Color(0xFF3A2A00),
  tertiary: saccoEmeraldLight,
  onTertiary: Colors.white,
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFF9FBF9),
  onSurface: Color(0xFF1B2421),
  surfaceContainerHighest: Color(0xFFE2E9E5),
  onSurfaceVariant: Color(0xFF465550),
  outline: Color(0xFF75837E),
  outlineVariant: Color(0xFFD0D9D4),
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF4DB6AC),
  onPrimary: Color(0xFF003730),
  primaryContainer: saccoEmerald,
  onPrimaryContainer: Color(0xFF70F7E6),
  secondary: saccoGoldLight,
  onSecondary: Color(0xFF412D00),
  secondaryContainer: Color(0xFF5C4300),
  onSecondaryContainer: Color(0xFFFFDEA6),
  tertiary: Color(0xFF80CBC4),
  onTertiary: Color(0xFF00201B),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF17221F),
  onSurface: Color(0xFFE0E3E1),
  surfaceContainerHighest: Color(0xFF26332F),
  onSurfaceVariant: Color(0xFFBFC9C5),
  outline: Color(0xFF899390),
  outlineVariant: Color(0xFF3F4945),
);

ThemeData _theme(ColorScheme c, Color background) => ThemeData(
      useMaterial3: true,
      colorScheme: c,
      scaffoldBackgroundColor: background,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        elevation: 6,
        height: 68,
        // Seven tabs on a small phone: keep every label on one line.
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10, letterSpacing: 0, color: c.onSurface)),
      ),
      dialogTheme: DialogThemeData(backgroundColor: c.surface),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      // Comfortable tap size on every button.
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 44))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 44))),
      dividerTheme: DividerThemeData(color: c.outlineVariant, space: 16),
    );

// Light grey-green page behind off-white cards: less glare than pure white on white.
final lightTheme = _theme(_light, const Color(0xFFECF1EE));
final darkTheme = _theme(_dark, const Color(0xFF101715));

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
