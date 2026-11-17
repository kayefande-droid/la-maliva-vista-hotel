/// LA-MALIVA VISTA design tokens — one source of truth for the Windows app,
/// the Android app and any web surface.
///
/// The palette is taken from the hotel's own logo (deep navy ground, sky-blue
/// mark) with a single orange gradient reserved for primary actions, live data
/// and emphasis. Orange is never a background wash: that is what keeps the
/// interface looking expensive instead of loud.
///
/// Pure Dart: no Flutter import, so it can be unit-tested and reused by both
/// apps without a widget binding.
library lamaliva_design;

/// Brand surface and ink.
abstract final class LamalivaColors {
  // Navy — structure, navigation, headers, dark app surfaces.
  static const navy900 = ColorValue(0xFF070F1E);
  static const navy800 = ColorValue(0xFF0B1930);
  static const navy700 = ColorValue(0xFF122443);
  static const navy600 = ColorValue(0xFF1B3257);

  // Sky blue — the logo mark. Secondary accent only, never a large fill.
  static const sky500 = ColorValue(0xFF4FB3D9);
  static const sky400 = ColorValue(0xFF6DCBE8);
  static const sky300 = ColorValue(0xFFA5E1F2);

  // Orange — the single action colour. Gradient, top to bottom.
  static const orangeStart = ColorValue(0xFFF5A54E);
  static const orangeMid = ColorValue(0xFFE87A2B);
  static const orangeEnd = ColorValue(0xFFB8421F);
  static const orangeGradient = <ColorValue>[orangeStart, orangeMid, orangeEnd];

  // Warm neutrals — the website and light panes.
  static const cream = ColorValue(0xFFFAF6EF);
  static const creamDeep = ColorValue(0xFFF2EADC);
  static const sand = ColorValue(0xFFE4D8C6);

  // Ink.
  static const ink = ColorValue(0xFF111826);
  static const inkMuted = ColorValue(0xFF5A6579);
  static const inkFaint = ColorValue(0xFF8B95A7);

  // Semantics — desaturated so they sit under the brand rather than shouting.
  static const success = ColorValue(0xFF1E6B41);
  static const successSoft = ColorValue(0xFFBFE6CD);
  static const warning = ColorValue(0xFF9A6410);
  static const warningSoft = ColorValue(0xFFF3DDB0);
  static const danger = ColorValue(0xFFA03024);
  static const dangerSoft = ColorValue(0xFFF6C9C2);
  static const info = ColorValue(0xFF1D5A96);
  static const infoSoft = ColorValue(0xFFC4DCF5);

  // Hairlines and elevation.
  static const line = ColorValue(0xFFDDD3C4);
  static const lineDark = ColorValue(0xFF22314D);
}

/// Minimal colour value type so this file stays dependency-free.
final class ColorValue {
  const ColorValue(this.value);

  /// 0xAARRGGBB
  final int value;

  int get alpha => (value >> 24) & 0xFF;
  int get red => (value >> 16) & 0xFF;
  int get green => (value >> 8) & 0xFF;
  int get blue => value & 0xFF;

  double get opacity => alpha / 255.0;

  ColorValue withAlpha(double opacity) {
    final a = (opacity.clamp(0.0, 1.0) * 255).round();
    return ColorValue((a << 24) | (value & 0x00FFFFFF));
  }

  @override
  String toString() =>
      '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Typography. A display serif carries the hotel's voice; a neutral grotesk
/// carries the interface; numerals are tabular everywhere data is compared.
abstract final class LamalivaType {
  static const displayFamily = 'Cormorant Garamond';
  static const uiFamily = 'Inter';
  static const monoFamily = 'JetBrains Mono';

  // Desktop scale (Windows).
  static const displayLarge = 34.0;
  static const displayMedium = 27.0;
  static const titleLarge = 20.0;
  static const titleMedium = 16.0;
  static const bodyLarge = 14.5;
  static const bodyMedium = 13.5;
  static const label = 12.5;
  static const micro = 11.0;

  // Mobile scale (Android) — one step down, never below 12 for body.
  static const mobileTitle = 19.0;
  static const mobileBody = 14.0;
  static const mobileLabel = 12.0;

  static const displayHeight = 1.12;
  static const titleHeight = 1.28;
  static const bodyHeight = 1.55;
  static const trackingTight = -0.4;
  static const trackingLabel = 0.6;
}

/// Spacing — a 4pt grid, used strictly. No arbitrary values in screens.
abstract final class LamalivaSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 72.0;

  /// Desktop content column: never let a data table stretch past this.
  static const contentMax = 1440.0;
  static const readingMax = 680.0;
  static const railWidth = 232.0;
  static const railCollapsed = 76.0;
  static const commandBarHeight = 64.0;
}

/// Shape and elevation. Small radii read as crafted; large radii read as a
/// component library. Cards are 10, inputs 8, sheets 16.
abstract final class LamalivaShape {
  static const input = 8.0;
  static const card = 10.0;
  static const panel = 14.0;
  static const sheet = 16.0;
  static const pill = 999.0;

  static const hairline = 1.0;
  static const strong = 1.5;
}

/// Motion. Short, eased, honest. Nothing bounces in a hotel ledger.
abstract final class LamalivaMotion {
  static const instant = Duration(milliseconds: 90);
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const deliberate = Duration(milliseconds: 380);
  static const page = Duration(milliseconds: 320);

  /// Standard curve: fast out, gentle settle.
  static const easingOut = [0.16, 1.0, 0.3, 1.0];
  static const easingInOut = [0.65, 0.0, 0.35, 1.0];

  /// Disable all non-essential motion when the OS asks for reduced motion.
  static const respectsReducedMotion = true;
}

/// Layout breakpoints shared by both apps.
abstract final class LamalivaBreakpoints {
  static const compact = 600.0; // phone portrait / narrow window
  static const medium = 900.0; // phone landscape, small tablet, small window
  static const expanded = 1280.0; // desktop with rail + detail pane
  static const wide = 1600.0;

  /// Android target range: Galaxy Note 8 (360 x 740 dp logical) through
  /// current Galaxy S/Note/A series. Nothing may overflow at 360 dp.
  static const androidMinWidth = 360.0;
  static const androidComfortable = 412.0;

  /// Windows minimum: a 1366 x 768 laptop at 125% scaling (~1093 dp).
  static const windowsMinWidth = 1024.0;
  static const windowsMinHeight = 680.0;
}
