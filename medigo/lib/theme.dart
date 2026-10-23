import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppSpacing {
  // Spacing values
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Edge insets shortcuts
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  // Horizontal padding
  static const EdgeInsets horizontalXs = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalXl = EdgeInsets.symmetric(horizontal: xl);

  // Vertical padding
  static const EdgeInsets verticalXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets verticalXl = EdgeInsets.symmetric(vertical: xl);
}

/// Border radius constants for consistent rounded corners
class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
}

// =============================================================================
// THEME EXTENSIONS
// =============================================================================

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color labLogoBackground;
  final Color warning;
  final Color onWarning;

  const AppColors({required this.labLogoBackground, required this.warning, required this.onWarning});

  static const light = AppColors(
    labLogoBackground: Colors.white,
    // Vibrant warning orange with high-contrast text
    warning: Color(0xFFFF9800),
    onWarning: Colors.white,
  );
  static const dark = AppColors(
    labLogoBackground: Colors.white,
    // Keep warning vivid in dark mode as well
    warning: Color(0xFFFF9800),
    onWarning: Colors.white,
  );

  @override
  AppColors copyWith({Color? labLogoBackground, Color? warning, Color? onWarning}) => AppColors(
        labLogoBackground: labLogoBackground ?? this.labLogoBackground,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      labLogoBackground: Color.lerp(labLogoBackground, other.labLogoBackground, t) ?? labLogoBackground,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      onWarning: Color.lerp(onWarning, other.onWarning, t) ?? onWarning,
    );
  }
}

// =============================================================================
// TEXT STYLE EXTENSIONS
// =============================================================================

/// Extension to add text style utilities to BuildContext
/// Access via context.textStyles
extension TextStyleContext on BuildContext {
  TextTheme get textStyles => Theme.of(this).textTheme;
}

/// Helper methods for common text style modifications
extension TextStyleExtensions on TextStyle {
  /// Make text bold
  TextStyle get bold => copyWith(fontWeight: FontWeight.bold);

  /// Make text semi-bold
  TextStyle get semiBold => copyWith(fontWeight: FontWeight.w600);

  /// Make text medium weight
  TextStyle get medium => copyWith(fontWeight: FontWeight.w500);

  /// Make text normal weight
  TextStyle get normal => copyWith(fontWeight: FontWeight.w400);

  /// Make text light
  TextStyle get light => copyWith(fontWeight: FontWeight.w300);

  /// Add custom color
  TextStyle withColor(Color color) => copyWith(color: color);

  /// Add custom size
  TextStyle withSize(double size) => copyWith(fontSize: size);
}

// =============================================================================
// COLORS
// =============================================================================

/// Modern, vibrant-blue palette (medical, calm yet confident)
class LightModeColors {
  // Primary: Vibrant medical blue
  static const lightPrimary = Color(0xFF6694FD); // Blue 600
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFDCEBFF);
  static const lightOnPrimaryContainer = Color(0xFF0B3C83);

  // Secondary: Deep indigo to keep it professional, not too colorful
  static const lightSecondary = Color(0xFF1E40AF); // Indigo 800
  static const lightOnSecondary = Color(0xFFEAF2FF);

  // Tertiary: Soft sky blue for subtle accents
  static const lightTertiary = Color(0xFF93C5FD); // Blue 300
  static const lightOnTertiary = Color(0xFF0F172A); // Slate 900

  // Error colors
  static const lightError = Color(0xFFB3261E);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFF9DEDC);
  static const lightOnErrorContainer = Color(0xFF410E0B);

  // Surfaces
  static const lightSurface = Color(0xFFFBFCFF);
  static const lightOnSurface = Color(0xFF0B1220);
  static const lightBackground = Color(0xFFF5F8FF);
  static const lightSurfaceVariant = Color(0xFFE6ECF9);
  static const lightOnSurfaceVariant = Color(0xFF3A4A62);

  // Outline and shadow
  static const lightOutline = Color(0xFF7C8FA9);
  static const lightShadow = Color(0xFF000000);
  static const lightInversePrimary = Color(0xFF93C5FD);
}

/// Dark mode colors with good contrast and muted depth
class DarkModeColors {
  // Primary: Lighter blue on dark backgrounds
  static const darkPrimary = Color(0xFF0068F1); // Blue 400
  static const darkOnPrimary = Color(0xFF0A2540);
  static const darkPrimaryContainer = Color(0xFF536397); // Indigo 800
  static const darkOnPrimaryContainer = Color(0xFFDCEBFF);

  // Secondary
  static const darkSecondary = Color(0xFF93C5FD); // Blue 300
  static const darkOnSecondary = Color(0xFF0B1220);

  // Tertiary
  static const darkTertiary = Color(0xFF3B82F6); // Blue 500
  static const darkOnTertiary = Color(0xFFFFFFFF);

  // Error colors
  static const darkError = Color(0xFFFFB4AB);
  static const darkOnError = Color(0xFF690005);
  static const darkErrorContainer = Color(0xFF8C1D18);
  static const darkOnErrorContainer = Color(0xFFFFDAD6);

  // Surfaces
  static const darkSurface = Color(0xFF0B1220);
  static const darkOnSurface = Color(0xFFE6ECF9);
  static const darkSurfaceVariant = Color(0xFF1C2735);
  static const darkOnSurfaceVariant = Color(0xFFBBD0EA);

  // Outline and shadow
  static const darkOutline = Color(0xFF6B7B95);
  static const darkShadow = Color(0xFF000000);
  static const darkInversePrimary = Color(0xFF2563EB);
}

/// Font size constants
class FontSizes {
  static const double displayLarge = 57.0;
  static const double displayMedium = 45.0;
  static const double displaySmall = 36.0;
  static const double headlineLarge = 32.0;
  static const double headlineMedium = 28.0;
  static const double headlineSmall = 24.0;
  static const double titleLarge = 22.0;
  static const double titleMedium = 16.0;
  static const double titleSmall = 14.0;
  static const double labelLarge = 14.0;
  static const double labelMedium = 12.0;
  static const double labelSmall = 11.0;
  static const double bodyLarge = 16.0;
  static const double bodyMedium = 14.0;
  static const double bodySmall = 12.0;
}

// =============================================================================
// THEMES
// =============================================================================

/// Light theme with modern, vibrant blue aesthetic
ThemeData get lightTheme => ThemeData(
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      colorScheme: ColorScheme.light(
        primary: LightModeColors.lightPrimary,
        onPrimary: LightModeColors.lightOnPrimary,
        primaryContainer: LightModeColors.lightPrimaryContainer,
        onPrimaryContainer: LightModeColors.lightOnPrimaryContainer,
        secondary: LightModeColors.lightSecondary,
        onSecondary: LightModeColors.lightOnSecondary,
        tertiary: LightModeColors.lightTertiary,
        onTertiary: LightModeColors.lightOnTertiary,
        error: LightModeColors.lightError,
        onError: LightModeColors.lightOnError,
        errorContainer: LightModeColors.lightErrorContainer,
        onErrorContainer: LightModeColors.lightOnErrorContainer,
        surface: LightModeColors.lightSurface,
        onSurface: LightModeColors.lightOnSurface,
        surfaceContainerHighest: LightModeColors.lightSurfaceVariant,
        onSurfaceVariant: LightModeColors.lightOnSurfaceVariant,
        outline: LightModeColors.lightOutline,
        shadow: LightModeColors.lightShadow,
        inversePrimary: LightModeColors.lightInversePrimary,
      ),
      brightness: Brightness.light,
      scaffoldBackgroundColor: LightModeColors.lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: LightModeColors.lightOnSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(LightModeColors.lightPrimary),
          foregroundColor: const WidgetStatePropertyAll(LightModeColors.lightOnPrimary),
          overlayColor: WidgetStatePropertyAll(LightModeColors.lightOnPrimary.withValues(alpha: 0.06)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
          side: const WidgetStatePropertyAll(BorderSide(color: LightModeColors.lightPrimary)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(LightModeColors.lightOnSurface),
          overlayColor: WidgetStatePropertyAll(LightModeColors.lightPrimary.withValues(alpha: 0.08)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: LightModeColors.lightPrimary)),
        prefixIconColor: LightModeColors.lightOnSurfaceVariant,
        suffixIconColor: LightModeColors.lightPrimary,
      ),
      textTheme: _buildTextTheme(Brightness.light),
      extensions: const <ThemeExtension<dynamic>>[AppColors.light],
    );

/// Dark theme with depth and balanced vibrancy
ThemeData get darkTheme => ThemeData(
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      colorScheme: ColorScheme.dark(
        primary: DarkModeColors.darkPrimary,
        onPrimary: DarkModeColors.darkOnPrimary,
        primaryContainer: DarkModeColors.darkPrimaryContainer,
        onPrimaryContainer: DarkModeColors.darkOnPrimaryContainer,
        secondary: DarkModeColors.darkSecondary,
        onSecondary: DarkModeColors.darkOnSecondary,
        tertiary: DarkModeColors.darkTertiary,
        onTertiary: DarkModeColors.darkOnTertiary,
        error: DarkModeColors.darkError,
        onError: DarkModeColors.darkOnError,
        errorContainer: DarkModeColors.darkErrorContainer,
        onErrorContainer: DarkModeColors.darkOnErrorContainer,
        surface: DarkModeColors.darkSurface,
        onSurface: DarkModeColors.darkOnSurface,
        surfaceContainerHighest: DarkModeColors.darkSurfaceVariant,
        onSurfaceVariant: DarkModeColors.darkOnSurfaceVariant,
        outline: DarkModeColors.darkOutline,
        shadow: DarkModeColors.darkShadow,
        inversePrimary: DarkModeColors.darkInversePrimary,
      ),
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DarkModeColors.darkSurface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: DarkModeColors.darkOnSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(DarkModeColors.darkPrimary),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: WidgetStatePropertyAll(DarkModeColors.darkPrimary.withValues(alpha: 0.08)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
          side: const WidgetStatePropertyAll(BorderSide(color: DarkModeColors.darkPrimary)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(DarkModeColors.darkOnSurface),
          overlayColor: WidgetStatePropertyAll(DarkModeColors.darkPrimary.withValues(alpha: 0.12)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: DarkModeColors.darkPrimary)),
        prefixIconColor: DarkModeColors.darkOnSurfaceVariant,
        suffixIconColor: DarkModeColors.darkPrimary,
      ),
      textTheme: _buildTextTheme(Brightness.dark),
      extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
    );

// =============================================================================
// GRADIENTS
// =============================================================================

class AppGradients {
  /// Primary diagonal gradient for hero areas and cards
  static LinearGradient primary(ColorScheme scheme) => LinearGradient(
        colors: [
          scheme.primary,
          scheme.primary.withValues(alpha: 0.72),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Subtle surface tint gradient
  static LinearGradient surfaceTint(ColorScheme scheme) => LinearGradient(
        colors: [
          scheme.primaryContainer,
          scheme.primaryContainer.withValues(alpha: 0.6),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Even lighter image placeholder gradient to clearly distinguish from summary cards
  static LinearGradient imagePlaceholder(ColorScheme scheme) => LinearGradient(
        colors: [
          scheme.surfaceContainerHighest,
          scheme.surface,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// Build text theme using Inter font family
TextTheme _buildTextTheme(Brightness brightness) {
  return TextTheme(
    displayLarge: GoogleFonts.inter(
      fontSize: FontSizes.displayLarge,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
    ),
    displayMedium: GoogleFonts.inter(
      fontSize: FontSizes.displayMedium,
      fontWeight: FontWeight.w400,
    ),
    displaySmall: GoogleFonts.inter(
      fontSize: FontSizes.displaySmall,
      fontWeight: FontWeight.w400,
    ),
    headlineLarge: GoogleFonts.inter(
      fontSize: FontSizes.headlineLarge,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: FontSizes.headlineMedium,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: GoogleFonts.inter(
      fontSize: FontSizes.headlineSmall,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: FontSizes.titleLarge,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: FontSizes.titleMedium,
      fontWeight: FontWeight.w500,
    ),
    titleSmall: GoogleFonts.inter(
      fontSize: FontSizes.titleSmall,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: FontSizes.labelLarge,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    ),
    labelMedium: GoogleFonts.inter(
      fontSize: FontSizes.labelMedium,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
    ),
    labelSmall: GoogleFonts.inter(
      fontSize: FontSizes.labelSmall,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: FontSizes.bodyLarge,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: FontSizes.bodyMedium,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: FontSizes.bodySmall,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
    ),
  );
}
