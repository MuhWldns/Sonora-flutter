/// Tema Sonora: Material 3 dengan identitas amber hangat milik Sonora.
///
/// Warna asli dari kanon desain Sonora dipertahankan (amber-500 sebagai aksen
/// tetap), dengan permukaan hangat netral untuk mode terang maupun gelap.
/// Seluruh widget mengambil warna dari [ColorScheme] dan [SonoraColors]
/// (ThemeExtension) sehingga tidak ada hex mentah yang tersebar di UI.
library;

import 'package:flutter/material.dart';

/// Aksen tanda tangan Sonora.
const Color kAmber = Color(0xFFF59E0B);
const Color kAmberDim = Color(0xFFB45309);
const Color kAmberBright = Color(0xFFFBBF24);

/// Grid 4dp.
const double kSpaceXs = 4;
const double kSpaceSm = 8;
const double kSpaceMd = 12;
const double kSpaceLg = 16;
const double kSpaceXl = 24;
const double kSpaceXxl = 32;

const double kRadiusSm = 8;
const double kRadiusMd = 12;
const double kRadiusLg = 16;
const double kRadiusXl = 24;

/// Target sentuh minimum sesuai panduan Android.
const double kTouchTarget = 48;

/// Token warna yang tidak dimiliki [ColorScheme]: aksen teks, kaca, dan glow.
@immutable
class SonoraColors extends ThemeExtension<SonoraColors> {
  const SonoraColors({
    required this.accentText,
    required this.onAccent,
    required this.glassSurface,
    required this.glassSurfaceSubtle,
    required this.glassSurfaceElevated,
    required this.glassBorder,
    required this.glassBorderHighlight,
    required this.glow,
    required this.success,
  });

  /// Aksen untuk teks di atas permukaan (kontras terhadap permukaan).
  final Color accentText;

  /// Teks/ikon di atas [ColorScheme.primary] (amber).
  final Color onAccent;

  final Color glassSurface;
  final Color glassSurfaceSubtle;
  final Color glassSurfaceElevated;
  final Color glassBorder;
  final Color glassBorderHighlight;

  /// Cahaya ambien di belakang artwork pemutar penuh.
  final Color glow;

  /// Status sukses (koneksi teruji, tersimpan).
  final Color success;

  static SonoraColors of(BuildContext context) {
    final colors = Theme.of(context).extension<SonoraColors>();
    assert(colors != null, 'SonoraColors tidak terpasang pada tema aktif.');
    return colors!;
  }

  @override
  SonoraColors copyWith({
    Color? accentText,
    Color? onAccent,
    Color? glassSurface,
    Color? glassSurfaceSubtle,
    Color? glassSurfaceElevated,
    Color? glassBorder,
    Color? glassBorderHighlight,
    Color? glow,
    Color? success,
  }) {
    return SonoraColors(
      accentText: accentText ?? this.accentText,
      onAccent: onAccent ?? this.onAccent,
      glassSurface: glassSurface ?? this.glassSurface,
      glassSurfaceSubtle: glassSurfaceSubtle ?? this.glassSurfaceSubtle,
      glassSurfaceElevated: glassSurfaceElevated ?? this.glassSurfaceElevated,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBorderHighlight: glassBorderHighlight ?? this.glassBorderHighlight,
      glow: glow ?? this.glow,
      success: success ?? this.success,
    );
  }

  @override
  SonoraColors lerp(ThemeExtension<SonoraColors>? other, double t) {
    if (other is! SonoraColors) return this;
    return SonoraColors(
      accentText: Color.lerp(accentText, other.accentText, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      glassSurfaceSubtle: Color.lerp(glassSurfaceSubtle, other.glassSurfaceSubtle, t)!,
      glassSurfaceElevated: Color.lerp(glassSurfaceElevated, other.glassSurfaceElevated, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBorderHighlight: Color.lerp(glassBorderHighlight, other.glassBorderHighlight, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

/// Membangun tema Sonora untuk [brightness] tertentu.
ThemeData buildSonoraTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme base = ColorScheme.fromSeed(
    seedColor: kAmber,
    brightness: brightness,
  );

  final ColorScheme scheme = dark
      ? base.copyWith(
          primary: kAmber,
          onPrimary: const Color(0xFF1A1917),
          primaryContainer: const Color(0xFF4A3410),
          onPrimaryContainer: const Color(0xFFFFE7C2),
          secondary: kAmberBright,
          onSecondary: const Color(0xFF1A1917),
          secondaryContainer: const Color(0xFF3A2C14),
          onSecondaryContainer: const Color(0xFFFFE7C2),
          surface: const Color(0xFF121110),
          onSurface: const Color(0xFFF4F2EE),
          onSurfaceVariant: const Color(0xFFA8A49C),
          surfaceContainerLowest: const Color(0xFF0C0B0A),
          surfaceContainerLow: const Color(0xFF1C1B19),
          surfaceContainer: const Color(0xFF201E1C),
          surfaceContainerHigh: const Color(0xFF272522),
          surfaceContainerHighest: const Color(0xFF2E2B28),
          outline: const Color(0xFF38352F),
          outlineVariant: const Color(0xFF2E2B28),
          error: const Color(0xFFF2B8B5),
          onError: const Color(0xFF601410),
          errorContainer: const Color(0xFF8C1D18),
          onErrorContainer: const Color(0xFFF9DEDC),
          inverseSurface: const Color(0xFFF4F2EE),
          onInverseSurface: const Color(0xFF1A1917),
          inversePrimary: kAmberDim,
          surfaceTint: kAmber,
        )
      : base.copyWith(
          primary: kAmber,
          onPrimary: const Color(0xFF1A1917),
          primaryContainer: const Color(0xFFFFE7C2),
          onPrimaryContainer: const Color(0xFF4A3410),
          secondary: kAmberDim,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFF6E3C5),
          onSecondaryContainer: const Color(0xFF4A3410),
          surface: const Color(0xFFFAFAF9),
          onSurface: const Color(0xFF1A1917),
          onSurfaceVariant: const Color(0xFF6B6862),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: const Color(0xFFF4F3F0),
          surfaceContainerHigh: const Color(0xFFEFEEE9),
          surfaceContainerHighest: const Color(0xFFF1F0EC),
          outline: const Color(0xFFE0DED8),
          outlineVariant: const Color(0xFFEDEBE5),
          error: const Color(0xFFB3261E),
          onError: Colors.white,
          errorContainer: const Color(0xFFF9DEDC),
          onErrorContainer: const Color(0xFF410E0B),
          inverseSurface: const Color(0xFF1A1917),
          onInverseSurface: const Color(0xFFF4F2EE),
          inversePrimary: kAmberBright,
          surfaceTint: kAmber,
        );

  final SonoraColors sonora = dark
      ? const SonoraColors(
          accentText: kAmberBright,
          onAccent: Color(0xFF1A1917),
          glassSurface: Color(0x14FFFFFF),
          glassSurfaceSubtle: Color(0x0AFFFFFF),
          glassSurfaceElevated: Color(0x24FFFFFF),
          glassBorder: Color(0x24FFFFFF),
          glassBorderHighlight: Color(0x47FFFFFF),
          glow: Color(0x2EF59E0B),
          success: Color(0xFF7BD88F),
        )
      : const SonoraColors(
          accentText: kAmberDim,
          onAccent: Color(0xFF1A1917),
          glassSurface: Color(0xFFFFFFFF),
          glassSurfaceSubtle: Color(0xFFF4F3F0),
          glassSurfaceElevated: Color(0xFFFFFFFF),
          glassBorder: Color(0x14000000),
          glassBorderHighlight: Color(0x24000000),
          glow: Color(0x24F59E0B),
          success: Color(0xFF2E7D32),
        );

  final ThemeData scaffold = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
  );
  final TextTheme text = scaffold.textTheme.copyWith(
    displaySmall: scaffold.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    headlineSmall: scaffold.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    ),
    titleLarge: scaffold.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: scaffold.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: scaffold.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: scaffold.textTheme.bodyLarge?.copyWith(height: 1.35),
    bodyMedium: scaffold.textTheme.bodyMedium?.copyWith(height: 1.35),
    labelLarge: scaffold.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );

  final BorderSide fieldBorder = BorderSide(color: scheme.outline);
  final OutlineInputBorder fieldShape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(kRadiusMd),
    borderSide: fieldBorder,
  );

  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    extensions: <ThemeExtension<dynamic>>[sonora],
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: scheme.surfaceTint,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (Set<WidgetState> states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusLg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primaryContainer,
      disabledColor: scheme.surfaceContainerHighest,
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
      labelPadding: const EdgeInsets.symmetric(horizontal: kSpaceSm),
      padding: const EdgeInsets.symmetric(horizontal: kSpaceSm, vertical: kSpaceXs),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: scheme.onPrimaryContainer,
      ),
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: scheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: scheme.surfaceTint,
      modalBarrierColor: Colors.black54,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: kSpaceLg,
        vertical: kSpaceMd,
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      border: fieldShape,
      enabledBorder: fieldShape,
      focusedBorder: fieldShape.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      errorBorder: fieldShape.copyWith(borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder: fieldShape.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: sonora.onAccent,
        disabledBackgroundColor: scheme.surfaceContainerHighest,
        disabledForegroundColor: scheme.onSurfaceVariant,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceXl, vertical: kSpaceMd),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, kTouchTarget),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceXl, vertical: kSpaceMd),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, kTouchTarget),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: sonora.accentText,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        minimumSize: const Size(0, kTouchTarget),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        minimumSize: const Size(kTouchTarget, kTouchTarget),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
      titleTextStyle: text.bodyLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      closeIconColor: scheme.onInverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// Akses cepat token Sonora dari [BuildContext].
extension SonoraThemeContext on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  SonoraColors get sonora => SonoraColors.of(this);
  TextTheme get texts => Theme.of(this).textTheme;
}
