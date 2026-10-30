/// Tema Sonora: bahasa desain Nocturne Audio — gelap atmosferik dengan aksen
/// crimson tunggal (`#E03A3E`).
///
/// Hierarki permukaan mengikuti spesifikasi Nocturne (canvas → base →
/// container-low → container → container-high → container-highest), tipografi
/// Plus Jakarta Sans, dan crimson hanya dipakai untuk titik fokus (aksi utama,
/// keadaan aktif, progres). Mode terang adalah derivasi dengan hierarki yang
/// sama. Seluruh widget mengambil warna dari [ColorScheme] dan [SonoraColors]
/// (ThemeExtension) sehingga tidak ada hex mentah yang tersebar di UI.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Aksen tanda tangan Sonora (crimson Nocturne).
const Color kAccent = Color(0xFFE03A3E);

/// Varian aksen lebih terang untuk teks di atas permukaan gelap.
const Color kAccentHover = Color(0xFFF2484C);

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

/// Radius lembar/sheet (kontrak Nocturne: 24–32).
const double kRadiusSheet = 28;

/// Target sentuh minimum sesuai panduan Android.
const double kTouchTarget = 48;

/// Token warna yang tidak dimiliki [ColorScheme]: aksen teks, kaca dock,
/// glow ambien, dan warna fungsional.
@immutable
class SonoraColors extends ThemeExtension<SonoraColors> {
  const SonoraColors({
    required this.accentText,
    required this.accentHover,
    required this.onAccent,
    required this.textTertiary,
    required this.glassSurface,
    required this.glassBorder,
    required this.glow,
    required this.success,
  });

  /// Aksen untuk teks/ikon di atas permukaan (kontras terhadap permukaan).
  final Color accentText;

  /// Varian aksen lebih terang (teks aktif di atas latar artwork gelap).
  final Color accentHover;

  /// Teks/ikon di atas [ColorScheme.primary] (crimson).
  final Color onAccent;

  /// Teks paling redup (caption, penomoran, metadata).
  final Color textTertiary;

  /// Isi dock kaca mini-player (translusen + blur via [GlassContainer]).
  final Color glassSurface;

  /// Garis tepi 1px permukaan kaca.
  final Color glassBorder;

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
    Color? accentHover,
    Color? onAccent,
    Color? textTertiary,
    Color? glassSurface,
    Color? glassBorder,
    Color? glow,
    Color? success,
  }) {
    return SonoraColors(
      accentText: accentText ?? this.accentText,
      accentHover: accentHover ?? this.accentHover,
      onAccent: onAccent ?? this.onAccent,
      textTertiary: textTertiary ?? this.textTertiary,
      glassSurface: glassSurface ?? this.glassSurface,
      glassBorder: glassBorder ?? this.glassBorder,
      glow: glow ?? this.glow,
      success: success ?? this.success,
    );
  }

  @override
  SonoraColors lerp(ThemeExtension<SonoraColors>? other, double t) {
    if (other is! SonoraColors) return this;
    return SonoraColors(
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}

/// Permukaan kaca: blur latar + isi translusen + garis tepi 1px.
///
/// Dipakai dock mini-player dan permukaan mengambang di atas konten.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(kRadiusLg)),
    this.blurSigma = 16,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final SonoraColors sonora = context.sonora;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: sonora.glassSurface,
            borderRadius: borderRadius,
            border: Border.all(color: sonora.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Membangun tema Sonora untuk [brightness] tertentu.
ThemeData buildSonoraTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme base = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: brightness,
  );

  final ColorScheme scheme = dark
      ? base.copyWith(
          primary: kAccent,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFF45191B),
          onPrimaryContainer: const Color(0xFFFFDAD9),
          secondary: kAccentHover,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFF3A2224),
          onSecondaryContainer: const Color(0xFFFFDAD9),
          surface: const Color(0xFF0F1417),
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFF9DA7AE),
          surfaceContainerLowest: const Color(0xFF0A0F12),
          surfaceContainerLow: const Color(0xFF171C1F),
          surfaceContainer: const Color(0xFF1D2327),
          surfaceContainerHigh: const Color(0xFF262D32),
          surfaceContainerHighest: const Color(0xFF353A3D),
          outline: const Color(0xFF353A3D),
          outlineVariant: const Color(0xFF232A2E),
          error: const Color(0xFFFFB4AB),
          onError: const Color(0xFF690005),
          errorContainer: const Color(0xFF93000A),
          onErrorContainer: const Color(0xFFFFDAD6),
          inverseSurface: const Color(0xFFE3E8EA),
          onInverseSurface: const Color(0xFF141C21),
          inversePrimary: kAccentHover,
          surfaceTint: kAccent,
        )
      : base.copyWith(
          primary: kAccent,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFFFDAD9),
          onPrimaryContainer: const Color(0xFF410006),
          secondary: const Color(0xFFB3272B),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFFFDAD9),
          onSecondaryContainer: const Color(0xFF410006),
          surface: const Color(0xFFFAFBFB),
          onSurface: const Color(0xFF141C21),
          onSurfaceVariant: const Color(0xFF51616B),
          surfaceContainerLowest: const Color(0xFFF4F6F7),
          surfaceContainerLow: const Color(0xFFF0F3F4),
          surfaceContainer: const Color(0xFFE3E8EA),
          surfaceContainerHigh: const Color(0xFFD9DFE1),
          surfaceContainerHighest: const Color(0xFFC3CCCF),
          outline: const Color(0xFFC3CCCF),
          outlineVariant: const Color(0xFFE3E8EA),
          error: const Color(0xFFB3261E),
          onError: Colors.white,
          errorContainer: const Color(0xFFF9DEDC),
          onErrorContainer: const Color(0xFF410E0B),
          inverseSurface: const Color(0xFF141C21),
          onInverseSurface: const Color(0xFFF0F3F4),
          inversePrimary: kAccent,
          surfaceTint: kAccent,
        );

  final SonoraColors sonora = dark
      ? const SonoraColors(
          accentText: kAccentHover,
          accentHover: kAccentHover,
          onAccent: Colors.white,
          textTertiary: Color(0xFF646F77),
          glassSurface: Color(0xEB171C1F),
          glassBorder: Color(0x14FFFFFF),
          glow: Color(0x47E03A3E),
          success: Color(0xFF6EE7B7),
        )
      : const SonoraColors(
          accentText: kAccent,
          accentHover: kAccent,
          onAccent: Colors.white,
          textTertiary: Color(0xFF8A97A0),
          glassSurface: Color(0xEBFFFFFF),
          glassBorder: Color(0x14000000),
          glow: Color(0x29E03A3E),
          success: Color(0xFF2E7D32),
        );

  final ThemeData scaffold = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
  );

  // Plus Jakarta Sans: display 28-32/800, section 20-22/700, item 16/600,
  // body 14/400, caption 11-12/500, overline 10/700 (+0.08em).
  final TextTheme text = GoogleFonts.plusJakartaSansTextTheme(scaffold.textTheme)
      .copyWith(
    displaySmall: scaffold.textTheme.displaySmall?.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      color: scheme.onSurface,
    ),
    headlineSmall: scaffold.textTheme.headlineSmall?.copyWith(
      fontSize: 27,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.55,
    ),
    titleLarge: scaffold.textTheme.titleLarge?.copyWith(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
    ),
    titleMedium: scaffold.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    titleSmall: scaffold.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: scaffold.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: scaffold.textTheme.bodyMedium?.copyWith(height: 1.45),
    bodySmall: scaffold.textTheme.bodySmall?.copyWith(
      height: 1.4,
      letterSpacing: 0.2,
    ),
    labelLarge: scaffold.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    labelSmall: scaffold.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
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
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: scheme.surfaceTint,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
        (Set<WidgetState> states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
        (Set<WidgetState> states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
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
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primary,
      disabledColor: scheme.surfaceContainerHighest,
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
      labelPadding: const EdgeInsets.symmetric(horizontal: kSpaceLg),
      padding: const EdgeInsets.symmetric(horizontal: kSpaceSm, vertical: kSpaceSm),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: scheme.onPrimary,
      ),
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: scheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusSheet)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusSheet)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainer,
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
      thumbColor: scheme.onSurface,
      overlayColor: scheme.primary.withValues(alpha: 0.14),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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
