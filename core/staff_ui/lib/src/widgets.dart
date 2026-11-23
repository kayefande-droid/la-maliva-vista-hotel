import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import 'theme.dart';

/// A white panel on the cream canvas: hairline border, quiet shadow.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LamalivaSpace.md),
    this.title,
    this.trailing,
  });

  final Widget child;
  final EdgeInsets padding;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(LamalivaShape.panel),
        border: Border.all(color: c(LamalivaColors.line)),
        boxShadow: [
          BoxShadow(
            color: c(LamalivaColors.ink).withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                padding.top,
                padding.right,
                LamalivaSpace.sm,
              ),
              child: Row(
                children: [
                  Expanded(child: Text(title!, style: T.panelTitle)),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Padding(
            padding: title == null
                ? padding
                : EdgeInsets.fromLTRB(
                    padding.left,
                    0,
                    padding.right,
                    padding.bottom,
                  ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Room and reservation state, in the hotel's own words.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  static (Color, Color) colorsFor(String status) {
    switch (status.toLowerCase().replaceAll('_', ' ')) {
      case 'available':
      case 'clean':
        return (c(LamalivaColors.success), c(LamalivaColors.successSoft));
      case 'occupied':
      case 'checked in':
        return (c(LamalivaColors.info), c(LamalivaColors.infoSoft));
      case 'reserved':
      case 'confirmed':
        return (c(LamalivaColors.warning), c(LamalivaColors.warningSoft));
      case 'cleaning':
      case 'pending':
        return (c(LamalivaColors.warning), c(LamalivaColors.warningSoft));
      case 'maintenance':
      case 'no show':
      case 'cancelled':
        return (c(LamalivaColors.danger), c(LamalivaColors.dangerSoft));
      case 'checked out':
        return (c(LamalivaColors.inkMuted), c(LamalivaColors.creamDeep));
      default:
        return (c(LamalivaColors.inkMuted), c(LamalivaColors.creamDeep));
    }
  }

  static String labelFor(String status) {
    if (status.isEmpty) return 'Unknown';
    final words = status.replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colorsFor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? LamalivaSpace.xs : LamalivaSpace.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(LamalivaShape.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            labelFor(status),
            style: TextStyle(
              fontFamily: LamalivaType.uiFamily,
              fontSize: 11.5,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// One figure and its name — arrivals, departures, occupancy.
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final String? detail;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: T.label),
        const SizedBox(height: LamalivaSpace.xxs),
        Text(
          value,
          style: emphasise
              ? T.figure.copyWith(color: c(LamalivaColors.orangeMid))
              : T.figure,
        ),
        if (detail != null) ...[
          const SizedBox(height: LamalivaSpace.xxs),
          Text(detail!, style: T.micro),
        ],
      ],
    );
  }
}

/// Four states, always: loading, empty, error, full.
class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.xs),
            child: Row(
              children: [
                _bar(96),
                const SizedBox(width: LamalivaSpace.md),
                Expanded(child: _bar(double.infinity)),
                const SizedBox(width: LamalivaSpace.md),
                _bar(72),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bar(double width) => Container(
    height: 12,
    width: width == double.infinity ? null : width,
    decoration: BoxDecoration(
      color: c(LamalivaColors.creamDeep),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.xl),
      child: Column(
        children: [
          Icon(icon, size: 26, color: c(LamalivaColors.inkFaint)),
          const SizedBox(height: LamalivaSpace.sm),
          Text(title, style: T.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: LamalivaSpace.xxs),
          SizedBox(
            width: 320,
            child: Text(body, textAlign: TextAlign.center, style: T.bodyMuted),
          ),
        ],
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.lg),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 26,
            color: c(LamalivaColors.danger),
          ),
          const SizedBox(height: LamalivaSpace.sm),
          Text(
            'The server did not answer',
            style: T.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: LamalivaSpace.xxs),
          SizedBox(
            width: 380,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: T.bodyMuted,
            ),
          ),
          const SizedBox(height: LamalivaSpace.md),
          GhostButton(
            label: 'Try again',
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

/// Horizontal filter row of the hotel's own statuses.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('All', null),
          for (final option in options)
            _chip(StatusPill.labelFor(option), option),
        ],
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final active = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: LamalivaSpace.xs),
      child: Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          onTap: () => onSelected(value),
          child: AnimatedContainer(
            duration: LamalivaMotion.quick,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: LamalivaSpace.sm),
            decoration: BoxDecoration(
              color: active ? c(LamalivaColors.navy800) : Colors.white,
              borderRadius: BorderRadius.circular(LamalivaShape.pill),
              border: Border.all(
                color: active
                    ? c(LamalivaColors.navy800)
                    : c(LamalivaColors.line),
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: LamalivaType.uiFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white : c(LamalivaColors.inkMuted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Room number, guest reference: monospaced-ish, always scannable.
class Reference extends StatelessWidget {
  const Reference(this.text, {super.key, this.dark = false});

  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: T.numeral.copyWith(
        color: dark ? c(LamalivaColors.cream) : c(LamalivaColors.navy800),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

/// A short, honest entrance: content fades up into place once, never on
/// scroll, and never at all when the system asks for reduced motion.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LamalivaMotion.deliberate,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final curve = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Row-level hover feedback, used on every table row in the console.
class HoverRow extends StatefulWidget {
  const HoverRow({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: LamalivaMotion.quick,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover
                ? c(LamalivaColors.cream).withValues(alpha: 0.75)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                width: 2,
                color: _hover
                    ? c(LamalivaColors.orangeStart)
                    : Colors.transparent,
              ),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A figure that counts to its value once, so a number arriving reads as a
/// number arriving. Instant under reduced motion.
class CountedFigure extends StatelessWidget {
  const CountedFigure({
    super.key,
    required this.value,
    this.suffix = '',
    this.style,
  });

  final num value;
  final String suffix;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final end = value.toDouble();
    final decimals = end % 1 == 0 ? 0 : 1;
    final text = style ?? T.figure;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text('${end.toStringAsFixed(decimals)}$suffix', style: text);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: end),
      duration: LamalivaMotion.deliberate * 1.6,
      curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      builder: (context, v, _) =>
          Text('${v.toStringAsFixed(decimals)}$suffix', style: text),
    );
  }
}

String formatDate(String? iso) {
  if (iso == null || iso.length < 10) return '—';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final parts = iso.substring(0, 10).split('-');
  if (parts.length != 3) return iso;
  final month = int.tryParse(parts[1]) ?? 1;
  final day = int.tryParse(parts[2]) ?? 1;
  return '${day.toString().padLeft(2, '0')} ${months[(month - 1).clamp(0, 11)]} ${parts[0]}';
}

String formatMoney(Object? amount, {String currency = 'XAF'}) {
  final value = amount is num ? amount : num.tryParse('$amount') ?? 0;
  final whole = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(whole[i]);
  }
  return '$buffer $currency';
}
