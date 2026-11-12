import 'package:flutter/material.dart';

/// Ledger: warm paper, ink type, hairline rules, one rust
/// accent. Colour carries meaning only; everything else is type and spacing.
@immutable
class Ledger extends ThemeExtension<Ledger> {
  const Ledger({
    required this.bg,
    required this.ink,
    required this.muted,
    required this.line,
    required this.raised,
    required this.accent,
  });

  final Color bg;
  final Color ink;
  final Color muted;

  /// Hairline rules and tracks.
  final Color line;

  /// Barely-there fill for icon tiles and pressed states.
  final Color raised;

  /// Rust. Used for "today" and the live position on the dial, nothing else.
  final Color accent;

  static const paper = Ledger(
    bg: Color(0xFFF5F3EE),
    ink: Color(0xFF1E1D1A),
    muted: Color(0xFF8B867C),
    line: Color(0x171E1D1A),
    raised: Color(0x0A1E1D1A),
    accent: Color(0xFFB5643F),
  );

  /// One colour per task in charts, assigned in task order and never
  /// reshuffled. Checked for colour-blind separation and contrast on paper.
  static const series = [
    Color(0xFF2F6AA3), // blue
    Color(0xFFC4632E), // rust
    Color(0xFF0E9378), // teal
    Color(0xFFA87B12), // ochre
    Color(0xFF7656C4), // violet
    Color(0xFFC4465E), // rose
  ];

  /// Beyond six tasks, the rest share this.
  static const otherSeries = Color(0xFF8B867C);

  static Color seriesFor(int index) =>
      index < series.length ? series[index] : otherSeries;

  /// One-hue ink ramp, light to dark, for "how much" shading.
  static const ramp = [
    Color(0xFFECE8DF),
    Color(0xFFD3CCBE),
    Color(0xFFB0A794),
    Color(0xFF857C6B),
    Color(0xFF55503F),
    Color(0xFF1E1D1A),
  ];

  /// Paper left out all day: what [paper] turns into as work goes undone.
  /// Mirrored in android/.../res/drawable/widget_bg_*.xml.
  static const oldPaper = Color(0xFFDDCDAF);

  /// [paper] aged by [age] (0..1); see logic/paper.dart.
  static Ledger aged(double age) => age <= 0
      ? paper
      : paper.copyWith(bg: Color.lerp(paper.bg, oldPaper, age.clamp(0, 1)));

  static Ledger of(BuildContext context) =>
      Theme.of(context).extension<Ledger>()!;

  @override
  Ledger copyWith({
    Color? bg,
    Color? ink,
    Color? muted,
    Color? line,
    Color? raised,
    Color? accent,
  }) => Ledger(
    bg: bg ?? this.bg,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    raised: raised ?? this.raised,
    accent: accent ?? this.accent,
  );

  @override
  Ledger lerp(Ledger? other, double t) {
    if (other == null) return this;
    return Ledger(
      bg: Color.lerp(bg, other.bg, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

/// The three voices of the type system.
class Typo {
  Typo._();

  /// Instrument Serif: numerals and headlines.
  static TextStyle serif(double size, {Color? color, bool italic = false}) =>
      TextStyle(
        fontFamily: 'InstrumentSerif',
        fontSize: size,
        height: 1.05,
        letterSpacing: -size * 0.025,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color,
      );

  /// Geist: everything you read and tap. Variable font, so weight goes
  /// through the wght axis.
  static TextStyle sans(
    double size, {
    double weight = 400,
    Color? color,
    double? height,
  }) => TextStyle(
    fontFamily: 'Geist',
    fontSize: size,
    height: height,
    letterSpacing: -size * 0.008,
    fontVariations: [FontVariation('wght', weight)],
    color: color,
  );

  /// Geist Mono: minutes, counts, dates.
  static TextStyle mono(double size, {Color? color, double weight = 400}) =>
      TextStyle(
        fontFamily: 'GeistMono',
        fontSize: size,
        fontVariations: [FontVariation('wght', weight)],
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      );

  /// Small spaced capitals for labels.
  static TextStyle eyebrow(Color color) =>
      mono(10.5, color: color, weight: 500).copyWith(letterSpacing: 1.5);
}

class AppTheme {
  AppTheme._();

  /// Always paper, whatever the phone's dark-mode setting. [age] yellows it.
  static ThemeData light({double age = 0}) =>
      _build(Brightness.light, Ledger.aged(age));

  static ThemeData _build(Brightness b, Ledger l) {
    final scheme = ColorScheme.fromSeed(seedColor: l.accent, brightness: b)
        .copyWith(
          primary: l.ink,
          onPrimary: l.bg,
          secondary: l.accent,
          surface: l.bg,
          onSurface: l.ink,
          onSurfaceVariant: l.muted,
          surfaceContainerLowest: l.bg,
          surfaceContainerLow: l.bg,
          surfaceContainer: l.bg,
          surfaceContainerHigh: l.bg,
          surfaceContainerHighest: l.bg,
          outline: l.muted,
          outlineVariant: l.line,
          error: l.accent,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      fontFamily: 'Geist',
      splashFactory: NoSplash.splashFactory,
      highlightColor: l.raised,
    );
    return base.copyWith(
      extensions: [l],
      scaffoldBackgroundColor: l.bg,
      canvasColor: l.bg,
      dividerTheme: DividerThemeData(color: l.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: l.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: l.ink,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: l.bg,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: l.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: l.line),
        ),
        titleTextStyle: Typo.serif(28, color: l.ink),
        contentTextStyle: Typo.sans(14, color: l.muted, height: 1.5),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: l.accent,
        selectionColor: l.accent.withValues(alpha: .25),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        hintStyle: Typo.sans(16, color: l.muted),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: l.line),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: l.ink),
        ),
        border: UnderlineInputBorder(borderSide: BorderSide(color: l.line)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(l.bg),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? l.ink : l.line,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: l.ink,
        linearTrackColor: l.line,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: l.ink,
        contentTextStyle: Typo.sans(14, color: l.bg),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
