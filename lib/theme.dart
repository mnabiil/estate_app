import 'package:flutter/material.dart';

/// Palet & gaya visual Amani Living.
///
/// Terinspirasi UI kit "Rise Real Estate" (Figma Community): teks navy,
/// warna utama teal gelap, aksen hijau lime, kartu abu muda bersudut besar,
/// font Lato (teks) + Raleway (judul besar).
abstract final class AppColors {
  static const navy = Color(0xFF252B5C);
  static const teal = Color(0xFF234F68);
  static const lime = Color(0xFF8BC83F);
  static const limeDark = Color(0xFF5E9A1E);
  static const surfaceGray = Color(0xFFF5F4F8);
  static const textMuted = Color(0xFF53587A);
  static const hint = Color(0xFFA1A5C1);

  /// Gradasi kartu utama (seperti kartu pembayaran di desain).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3EA05E), Color(0xFF2E7EA6), Color(0xFF3F9F7A)],
    stops: [0, 0.55, 1],
  );

  /// Latar layar login (seperti layar pembuka di desain).
  static const splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6E93AE), Color(0xFF2F5C7A), teal],
    stops: [0, 0.5, 1],
  );
}

const fontBody = 'Lato';
const fontDisplay = 'Raleway';

/// Sudut kartu besar, khas desain.
const radiusCard = 25.0;
const radiusField = 20.0;
const radiusButton = 12.0;

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFF8FC1DD) : AppColors.teal,
    onPrimary: dark ? const Color(0xFF0E2433) : Colors.white,
    secondary: AppColors.lime,
    onSecondary: Colors.white,
    secondaryContainer: dark ? const Color(0xFF2E4A10) : const Color(0xFFE8F4DA),
    onSecondaryContainer:
        dark ? const Color(0xFFD4EDB5) : const Color(0xFF2E4A10),
    tertiary: dark ? const Color(0xFFC5C9EE) : AppColors.navy,
    surface: dark ? const Color(0xFF12152B) : Colors.white,
    onSurface: dark ? const Color(0xFFEDEEF5) : AppColors.navy,
    onSurfaceVariant: dark ? const Color(0xFFB4B7CF) : AppColors.textMuted,
    outline: AppColors.hint,
    outlineVariant: dark ? const Color(0xFF2E3354) : const Color(0xFFE6E6EE),
    surfaceContainerLowest: dark ? const Color(0xFF0D1022) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF181C36) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF1C2140) : AppColors.surfaceGray,
    surfaceContainerHigh: dark ? const Color(0xFF1F2445) : AppColors.surfaceGray,
    surfaceContainerHighest:
        dark ? const Color(0xFF23284A) : AppColors.surfaceGray,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontBody,
  );

  // Judul besar memakai Raleway, sisanya Lato.
  TextStyle? display(TextStyle? s, FontWeight w) =>
      s?.copyWith(fontFamily: fontDisplay, fontWeight: w);
  final text = base.textTheme.copyWith(
    displayLarge: display(base.textTheme.displayLarge, FontWeight.w700),
    displayMedium: display(base.textTheme.displayMedium, FontWeight.w700),
    displaySmall: display(base.textTheme.displaySmall, FontWeight.w700),
    headlineLarge: display(base.textTheme.headlineLarge, FontWeight.w700),
    headlineMedium: display(base.textTheme.headlineMedium, FontWeight.w700),
    headlineSmall: display(base.textTheme.headlineSmall, FontWeight.w700),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium:
        base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radiusField),
    borderSide: BorderSide.none,
  );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 18),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
      ),
      titleTextStyle: text.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: scheme.onSurface,
      ),
      subtitleTextStyle:
          text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.lime,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.lime.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: fontBody,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.outlineVariant, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(
          fontFamily: fontBody,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.lime,
      foregroundColor: Colors.white,
      elevation: 2,
      extendedTextStyle: const TextStyle(
        fontFamily: fontBody,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.hint),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurface,
      suffixIconColor: scheme.onSurfaceVariant,
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest),
      labelStyle: TextStyle(
        fontFamily: fontBody,
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface),
      ),
      checkmarkColor: scheme.onPrimary,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerHighest),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface),
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface),
        side: const WidgetStatePropertyAll(BorderSide.none),
        minimumSize: const WidgetStatePropertyAll(Size(0, 50)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
        )),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primary,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: fontBody,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          )),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.navy,
      contentTextStyle: const TextStyle(
        fontFamily: fontBody,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusButton),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}

/// Judul dua warna khas desain: baris tipis + baris tebal berwarna utama.
/// Contoh: "Halo," / "Budi Santoso".
class TwoToneHeading extends StatelessWidget {
  const TwoToneHeading(this.light, this.bold, {super.key, this.color});

  final String light;
  final String bold;

  /// Warna kustom (misal putih di atas latar gelap).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.headlineSmall!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          light,
          style: style.copyWith(
            fontWeight: FontWeight.w500,
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
        Text(
          bold,
          style: style.copyWith(
            fontWeight: FontWeight.w800,
            color: color ?? theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
