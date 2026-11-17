import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

/// Brand colours as Flutter colours.
Color c(ColorValue value) => Color(value.value);

/// The console's type scale.
///
/// Cormorant Garamond carries the hotel's voice (screen titles, figures that
/// deserve weight). Inter carries everything the staff reads and compares.
abstract final class T {
  static const display = TextStyle(
    fontFamily: LamalivaType.displayFamily,
    fontSize: 40,
    height: 1.06,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    color: Color(0xFF111826),
  );

  static const screenTitle = TextStyle(
    fontFamily: LamalivaType.displayFamily,
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: Color(0xFF111826),
  );

  static const panelTitle = TextStyle(
    fontFamily: LamalivaType.uiFamily,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: Color(0xFF111826),
  );

  static const figure = TextStyle(
    fontFamily: LamalivaType.displayFamily,
    fontSize: 44,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    color: Color(0xFF111826),
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const figureSmall = TextStyle(
    fontFamily: LamalivaType.displayFamily,
    fontSize: 26,
    height: 1.0,
    fontWeight: FontWeight.w600,
    color: Color(0xFF111826),
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const body = TextStyle(
    fontFamily: LamalivaType.uiFamily,
    fontSize: 14,
    height: 1.5,
    color: Color(0xFF111826),
  );

  static const bodyMuted = TextStyle(
    fontFamily: LamalivaType.uiFamily,
    fontSize: 13.5,
    height: 1.5,
    color: Color(0xFF5A6579),
  );

  static const label = TextStyle(
    fontFamily: LamalivaType.uiFamily,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: Color(0xFF5A6579),
  );

  static const micro = TextStyle(
    fontFamily: LamalivaType.uiFamily,
    fontSize: 11.5,
    height: 1.25,
    color: Color(0xFF8B95A7),
  );

  /// Reference numbers, room numbers, money: always aligned.
  static const numeral = TextStyle(
    fontFamily: LamalivaType.uiFamily,
    fontSize: 13.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: Color(0xFF111826),
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData buildStaffTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: c(LamalivaColors.navy800),
    brightness: Brightness.light,
    primary: c(LamalivaColors.navy800),
    onPrimary: Colors.white,
    secondary: c(LamalivaColors.orangeMid),
    surface: c(LamalivaColors.cream),
    onSurface: c(LamalivaColors.ink),
    error: c(LamalivaColors.danger),
  );

  OutlineInputBorder border(ColorValue color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(LamalivaShape.input),
        borderSide: BorderSide(color: c(color), width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c(LamalivaColors.cream),
    fontFamily: LamalivaType.uiFamily,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c(LamalivaColors.orangeMid),
      selectionColor: c(LamalivaColors.orangeStart).withValues(alpha: 0.28),
      selectionHandleColor: c(LamalivaColors.orangeMid),
    ),
    splashFactory: InkSparkle.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LamalivaSpace.sm,
        vertical: LamalivaSpace.sm,
      ),
      hintStyle: T.bodyMuted,
      labelStyle: T.label,
      floatingLabelStyle: const TextStyle(
        fontFamily: LamalivaType.uiFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF122443),
      ),
      border: border(LamalivaColors.line),
      enabledBorder: border(LamalivaColors.line),
      focusedBorder: border(LamalivaColors.navy600, 1.5),
      errorBorder: border(LamalivaColors.danger),
      focusedErrorBorder: border(LamalivaColors.danger, 1.5),
    ),
    iconTheme: IconThemeData(color: c(LamalivaColors.inkMuted), size: 20),
    dividerTheme: DividerThemeData(
      color: c(LamalivaColors.line),
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c(LamalivaColors.navy900),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(
        fontFamily: LamalivaType.uiFamily,
        fontSize: 12,
        color: Colors.white,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c(LamalivaColors.navy900),
      contentTextStyle: const TextStyle(
        fontFamily: LamalivaType.uiFamily,
        fontSize: 13,
        color: Colors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LamalivaShape.card),
      ),
    ),
  );
}

/// The single orange action. Used for exactly one thing per screen.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 48,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;
  final IconData? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: LamalivaColors.orangeGradient.map(c).toList(),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedOpacity(
            duration: LamalivaMotion.quick,
            opacity: enabled || widget.busy ? 1 : 0.45,
            child: AnimatedScale(
              duration: LamalivaMotion.instant,
              scale: _pressed ? 0.985 : 1,
              child: AnimatedContainer(
                duration: LamalivaMotion.quick,
                height: widget.height,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(LamalivaShape.input),
                  boxShadow: enabled && _hover
                      ? [
                          BoxShadow(
                            color: c(LamalivaColors.orangeEnd)
                                .withValues(alpha: 0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : const [],
                ),
                child: Center(
                  child: widget.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, size: 18, color: Colors.white),
                              const SizedBox(width: LamalivaSpace.xs),
                            ],
                            Text(
                              widget.label,
                              style: const TextStyle(
                                fontFamily: LamalivaType.uiFamily,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet secondary action: hairline border, ink text, no fill until hover.
class GhostButton extends StatefulWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.dark = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool dark;

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.dark
        ? c(LamalivaColors.sky300).withValues(alpha: 0.35)
        : c(LamalivaColors.line);
    final fg = widget.dark
        ? c(LamalivaColors.cream)
        : c(LamalivaColors.navy800);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: LamalivaMotion.quick,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: LamalivaSpace.sm),
          decoration: BoxDecoration(
            color: _hover
                ? (widget.dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white)
                : Colors.transparent,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(LamalivaShape.input),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: fg),
                const SizedBox(width: LamalivaSpace.xs),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: LamalivaType.uiFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
