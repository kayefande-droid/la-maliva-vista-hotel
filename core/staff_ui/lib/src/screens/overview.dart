import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// The hotel today, at a glance: who is arriving, who is in the house, how the
/// rooms are split and what the store room holds.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  late Future<(Map<String, dynamic>, List<dynamic>)> _data = _load();

  Future<(Map<String, dynamic>, List<dynamic>)> _load() async {
    final results = await Future.wait([
      widget.api.overview(),
      widget.api.arrivals(),
    ]);
    return (results[0] as Map<String, dynamic>, results[1] as List<dynamic>);
  }

  void _reload() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Map<String, dynamic>, List<dynamic>)>(
      future: _data,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        return RefreshIndicator(
          color: c(LamalivaColors.orangeMid),
          onRefresh: () async {
            _reload();
            await _data;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.xl,
            ),
            children: [
              Reveal(
                child: _Greeting(
                  name: widget.api.staffName,
                  role: widget.api.staffRole,
                ),
              ),
              const SizedBox(height: LamalivaSpace.md),
              if (loading)
                const Panel(child: LoadingPanel(rows: 4))
              else if (snap.hasError)
                Panel(
                  child: ErrorPanel(
                    message: snap.error.toString(),
                    onRetry: _reload,
                  ),
                )
              else
                ..._body(snap.data!.$1, snap.data!.$2),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _body(Map<String, dynamic> overview, List<dynamic> arrivals) {
    final rooms = (overview['rooms'] as Map?)?.cast<String, dynamic>() ?? const {};
    final today = (overview['today'] as Map?)?.cast<String, dynamic>() ?? const {};
    final store = (overview['inventory'] as Map?)?.cast<String, dynamic>() ?? const {};

    final total = (rooms['total'] as num?)?.toInt() ?? 0;
    final occupied = (rooms['occupied'] as num?)?.toInt() ?? 0;
    final available = (rooms['available'] as num?)?.toInt() ?? 0;
    final maintenance = (rooms['maintenance'] as num?)?.toInt() ?? 0;
    final other = (total - occupied - available - maintenance).clamp(0, total);
    final rate = (rooms['occupancy_rate'] as num?)?.toDouble() ?? 0;

    return [
      Reveal(
        delay: const Duration(milliseconds: 60),
        child: Panel(
          padding: const EdgeInsets.all(LamalivaSpace.lg),
          child: LayoutBuilder(
            builder: (context, box) {
              final cells = [
                StatCell(
                  label: 'Arrivals today',
                  value: '${(today['arrivals'] as num?)?.toInt() ?? 0}',
                ),
                StatCell(
                  label: 'Departures today',
                  value: '${(today['departures'] as num?)?.toInt() ?? 0}',
                ),
                StatCell(
                  label: 'In the house',
                  value: '${(today['in_house'] as num?)?.toInt() ?? 0}',
                ),
                StatCell(
                  label: 'Occupancy',
                  value: '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%',
                  detail: '$occupied of $total rooms',
                  emphasise: true,
                ),
              ];
              if (box.maxWidth < 620) {
                return Column(
                  children: [
                    Row(children: [
                      Expanded(child: cells[0]),
                      Expanded(child: cells[1]),
                    ]),
                    const SizedBox(height: LamalivaSpace.lg),
                    Row(children: [
                      Expanded(child: cells[2]),
                      Expanded(child: cells[3]),
                    ]),
                  ],
                );
              }
              return Row(
                // Start-aligned: the occupied cell carries a detail line, and
                // centring the row pushed its label above its neighbours'.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cells.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 64,
                        color: c(LamalivaColors.line),
                        margin: const EdgeInsets.symmetric(
                          horizontal: LamalivaSpace.lg,
                        ),
                      ),
                    Expanded(child: cells[i]),
                  ],
                ],
              );
            },
          ),
        ),
      ),
      const SizedBox(height: LamalivaSpace.md),
      LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 880;
          final chart = Reveal(
            delay: const Duration(milliseconds: 110),
            child: Panel(
              title: 'Where the rooms stand',
              child: _OccupancyChart(
                occupied: occupied,
                available: available,
                maintenance: maintenance,
                other: other,
                total: total,
                rate: rate,
              ),
            ),
          );
          final storage = Reveal(
            delay: const Duration(milliseconds: 150),
            child: Panel(
              title: 'Store room',
              child: _StoragePanel(store: store),
            ),
          );
          final arrivalsPanel = Reveal(
            delay: const Duration(milliseconds: 190),
            child: Panel(
              title: 'Arriving today',
              trailing: Reference('${arrivals.length}'),
              child: arrivals.isEmpty
                  ? const EmptyPanel(
                      title: 'No arrivals today',
                      body:
                          'Guests registered straight into a room appear in the house figure above.',
                      icon: Icons.luggage_outlined,
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < arrivals.length; i++) ...[
                          if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
                          _ArrivalRow(item: arrivals[i] as Map<String, dynamic>),
                        ],
                      ],
                    ),
            ),
          );

          if (!wide) {
            return Column(
              children: [
                chart,
                const SizedBox(height: LamalivaSpace.md),
                storage,
                const SizedBox(height: LamalivaSpace.md),
                arrivalsPanel,
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: chart),
                  const SizedBox(width: LamalivaSpace.md),
                  Expanded(flex: 2, child: storage),
                ],
              ),
              const SizedBox(height: LamalivaSpace.md),
              arrivalsPanel,
            ],
          );
        },
      ),
    ];
  }
}

/// The occupancy donut: one glance, the whole house.
class _OccupancyChart extends StatelessWidget {
  const _OccupancyChart({
    required this.occupied,
    required this.available,
    required this.maintenance,
    required this.other,
    required this.total,
    required this.rate,
  });

  final int occupied;
  final int available;
  final int maintenance;
  final int other;
  final int total;
  final double rate;

  @override
  Widget build(BuildContext context) {
    final segments = <(double, Color)>[
      (occupied.toDouble(), c(LamalivaColors.info)),
      (available.toDouble(), c(LamalivaColors.success)),
      (other.toDouble(), c(LamalivaColors.warning)),
      (maintenance.toDouble(), c(LamalivaColors.danger)),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final donutSize = box.maxWidth < 420 ? 132.0 : 158.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: const Cubic(0.16, 1.0, 0.3, 1.0),
              builder: (context, progress, _) => SizedBox(
                width: donutSize,
                height: donutSize,
                child: CustomPaint(
                  painter: _DonutPainter(segments: segments, progress: progress),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%',
                          style: T.figureSmall.copyWith(fontSize: 30),
                        ),
                        Text('occupied', style: T.micro),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: LamalivaSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LegendLine(
                    label: 'Occupied',
                    count: occupied,
                    total: total,
                    color: c(LamalivaColors.info),
                  ),
                  _LegendLine(
                    label: 'Available',
                    count: available,
                    total: total,
                    color: c(LamalivaColors.success),
                  ),
                  _LegendLine(
                    label: 'Reserved or cleaning',
                    count: other,
                    total: total,
                    color: c(LamalivaColors.warning),
                  ),
                  _LegendLine(
                    label: 'Maintenance',
                    count: maintenance,
                    total: total,
                    color: c(LamalivaColors.danger),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.progress});

  final List<(double, Color)> segments;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.$1);
    final thickness = size.width * 0.13;
    final rect = Rect.fromLTWH(
      thickness / 2,
      thickness / 2,
      size.width - thickness,
      size.height - thickness,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;

    if (total <= 0) {
      paint.color = const Color(0xFFE4D8C6);
      canvas.drawArc(rect, 0, math.pi * 2, false, paint);
      return;
    }

    // A hairline gap between segments keeps the chart reading as a chart.
    const gap = 0.035;
    var start = -math.pi / 2;
    for (final (weight, color) in segments) {
      if (weight <= 0) continue;
      final sweep = (weight / total) * math.pi * 2 * progress;
      paint.color = color;
      canvas.drawArc(rect, start, math.max(sweep - gap, 0.01), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress || old.segments != segments;
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: LamalivaSpace.xs),
          Expanded(child: Text(label, style: T.bodyMuted)),
          Text(
            '$count',
            style: T.numeral.copyWith(
              fontWeight: FontWeight.w700,
              color: c(LamalivaColors.navy800),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoragePanel extends StatelessWidget {
  const _StoragePanel({required this.store});

  final Map<String, dynamic> store;

  @override
  Widget build(BuildContext context) {
    final items = (store['items'] as num?)?.toInt() ?? 0;
    final low = (store['low_stock'] as num?)?.toInt() ?? 0;
    final value = store['value'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$items', style: T.figure),
                  Text('items on the shelf', style: T.micro),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: LamalivaSpace.sm),
        Divider(color: c(LamalivaColors.line), height: 1),
        const SizedBox(height: LamalivaSpace.sm),
        Row(
          children: [
            Expanded(child: Text('Stock value', style: T.bodyMuted)),
            Text(formatMoney(value), style: T.numeral.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: LamalivaSpace.xs),
        Row(
          children: [
            Expanded(child: Text('At reorder level', style: T.bodyMuted)),
            Text(
              '$low',
              style: T.numeral.copyWith(
                fontWeight: FontWeight.w700,
                color: low > 0 ? c(LamalivaColors.danger) : c(LamalivaColors.success),
              ),
            ),
          ],
        ),
        if (low > 0) ...[
          const SizedBox(height: LamalivaSpace.sm),
          Container(
            padding: const EdgeInsets.all(LamalivaSpace.xs),
            decoration: BoxDecoration(
              color: c(LamalivaColors.warningSoft).withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(LamalivaShape.card),
            ),
            child: Text(
              'Restock before the next shift handover.',
              style: T.micro.copyWith(color: c(LamalivaColors.warning)),
            ),
          ),
        ],
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.role});

  final String name;
  final String role;

  String get _todayLabel {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(LamalivaShape.panel),
      child: SizedBox(
        height: 168,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/img/mount-cameroon.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.55),
              filterQuality: FilterQuality.high,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    c(LamalivaColors.navy900).withValues(alpha: 0.92),
                    c(LamalivaColors.navy900).withValues(alpha: 0.55),
                    c(LamalivaColors.navy900).withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(LamalivaSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _todayLabel,
                    style: TextStyle(
                      fontFamily: LamalivaType.uiFamily,
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: LamalivaSpace.xxs),
                  Text(
                    'Good day, $name',
                    style: TextStyle(
                      fontFamily: LamalivaType.displayFamily,
                      fontSize: 32,
                      height: 1.12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: LamalivaSpace.xxs),
                  Text(
                    'Signed in as $role',
                    style: TextStyle(
                      fontFamily: LamalivaType.uiFamily,
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final guest = (item['guest'] as Map?)?.cast<String, dynamic>();
    final room = (item['room'] as Map?)?.cast<String, dynamic>();
    final nights = (item['nights'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.sm),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c(LamalivaColors.creamDeep),
              borderRadius: BorderRadius.circular(LamalivaShape.card),
            ),
            child: Center(
              child: Text(
                '${room?['number'] ?? '—'}',
                style: T.numeral.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: LamalivaSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${guest?['display_name'] ?? 'Guest'}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDate(item['arrival'] as String?)}'
                  '${nights == null ? '' : '  ·  $nights night${nights == 1 ? '' : 's'}'}',
                  style: T.micro,
                ),
              ],
            ),
          ),
          const SizedBox(width: LamalivaSpace.xs),
          StatusPill(status: '${item['status'] ?? ''}'),
        ],
      ),
    );
  }
}
