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
  primaryContainer: Color(0xFF70F7E6),
  onPrimaryContainer: Color(0xFF00201B),
  secondary: saccoGold,
  onSecondary: Colors.black,
  secondaryContainer: Color(0xFFFFDEA6),
  onSecondaryContainer: Color(0xFF261900),
  tertiary: saccoEmeraldLight,
  onTertiary: Colors.white,
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF191C1B),
  surfaceContainerHighest: Color(0xFFE7E0EC),
  onSurfaceVariant: Color(0xFF3F4945),
  outline: Color(0xFF79747E),
  outlineVariant: Color(0xFFCAC4D0),
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF4DB6AC),
  onPrimary: Color(0xFF003730),
  primaryContainer: saccoEmerald,
  onPrimaryContainer: Color(0xFF70F7E6),
  secondary: saccoGoldLight,
  onSecondary: Color(0xFF412D00),
  secondaryContainer: Color(0xFF4A4458),
  onSecondaryContainer: Color(0xFFE8DEF8),
  tertiary: Color(0xFF80CBC4),
  onTertiary: Color(0xFF00201B),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF17221F),
  onSurface: Color(0xFFE0E3E1),
  surfaceContainerHighest: Color(0xFF49454F),
  onSurfaceVariant: Color(0xFFCAC4D0),
  outline: Color(0xFF938F99),
  outlineVariant: Color(0xFF49454F),
);

ThemeData _theme(ColorScheme c, Color background) => ThemeData(
      useMaterial3: true,
      colorScheme: c,
      scaffoldBackgroundColor: background,
      navigationBarTheme: NavigationBarThemeData(backgroundColor: c.surface, elevation: 6, height: 68),
      dialogTheme: DialogThemeData(backgroundColor: c.surface),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );

final lightTheme = _theme(_light, const Color(0xFFFAFBF9));
final darkTheme = _theme(_dark, const Color(0xFF101715));
