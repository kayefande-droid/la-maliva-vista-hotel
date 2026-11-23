import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// What the hotel actually earned: rooms and the shop, by day, week and month.
///
/// Only management reaches this screen; the server refuses the report to any
/// other role. Money here is received cash, never a forecast.
class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  late Future<Map<String, dynamic>> _data = widget.api.moneyReport();
  late Future<List<dynamic>> _entries = widget.api.moneyEntries();
  int _grain = 0; // 0 = day, 1 = week, 2 = month

  void _reload() => setState(() {
    _data = widget.api.moneyReport();
    _entries = widget.api.moneyEntries();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
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
                ..._body(snap.data ?? const {}),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _body(Map<String, dynamic> data) {
    final today = (data['today'] as Map?)?.cast<String, dynamic>() ?? const {};
    final month =
        (data['this_month'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rows = switch (_grain) {
      1 => (data['weekly'] as List?) ?? const [],
      2 => (data['monthly'] as List?) ?? const [],
      _ => (data['daily'] as List?) ?? const [],
    };
    final peak = rows.fold<double>(
      0,
      (max, raw) => raw is Map
          ? [
              max,
              (raw['total'] as num?)?.toDouble() ?? 0,
            ].reduce((a, b) => a > b ? a : b)
          : max,
    );

    return [
      Reveal(
        child: Panel(
          padding: const EdgeInsets.all(LamalivaSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Taken today', style: T.label),
              const SizedBox(height: LamalivaSpace.xxs),
              Text(formatMoney(today['total']), style: T.figure),
              const SizedBox(height: LamalivaSpace.xs),
              Text(
                'Rooms ${formatMoney(today['rooms'])}   Â·   '
                'Shop ${formatMoney(today['shop'])}',
                style: T.bodyMuted,
              ),
              const SizedBox(height: LamalivaSpace.md),
              Divider(color: c(LamalivaColors.line), height: 1),
              const SizedBox(height: LamalivaSpace.md),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This month', style: T.label),
                        const SizedBox(height: LamalivaSpace.xxs),
                        Text(formatMoney(month['total']), style: T.figure),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rooms', style: T.label),
                        const SizedBox(height: LamalivaSpace.xxs),
                        Text(formatMoney(month['rooms']), style: T.figure),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shop', style: T.label),
                        const SizedBox(height: LamalivaSpace.xxs),
                        Text(formatMoney(month['shop']), style: T.figure),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: LamalivaSpace.md),
      Reveal(
        delay: const Duration(milliseconds: 60),
        child: Panel(
          title: 'Where it came from',
          trailing: _GrainSwitch(
            grain: _grain,
            onChanged: (value) => setState(() => _grain = value),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                const EmptyPanel(
                  title: 'No money recorded yet',
                  body:
                      'Payments taken at the desk and shop sales appear here as soon as they are saved.',
                  icon: Icons.payments_outlined,
                )
              else
                for (var i = 0; i < rows.length; i++)
                  _MoneyRow(
                    row: (rows[i] as Map).cast<String, dynamic>(),
                    grain: _grain,
                    peak: peak,
                    last: i == rows.length - 1,
                  ),
            ],
          ),
        ),
      ),
      const SizedBox(height: LamalivaSpace.md),
      const SizedBox(height: LamalivaSpace.md),
      Reveal(
        delay: const Duration(milliseconds: 90),
        child: Panel(
          title: 'Where the money came from',
          child: FutureBuilder<List<dynamic>>(
            future: _entries,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LoadingPanel(rows: 4);
              }
              if (snap.hasError) {
                return ErrorPanel(
                  message: snap.error.toString(),
                  onRetry: _reload,
                );
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return const EmptyPanel(
                  title: 'No money received yet',
                  body:
                      'Every room payment and shop sale will be listed here: '
                      'the room, the guest, the nights, or the bottles and plates.',
                  icon: Icons.receipt_long_outlined,
                );
              }
              return Column(
                children: [
                  for (var k = 0; k < rows.length; k++) ...[
                    if (k > 0)
                      Divider(color: c(LamalivaColors.line), height: 1),
                    _LedgerRow(entry: (rows[k] as Map).cast<String, dynamic>()),
                  ],
                ],
              );
            },
          ),
        ),
      ),
      Reveal(
        delay: const Duration(milliseconds: 110),
        child: Text(
          'These figures are money already received, counted on the hotel\'s '
          'own clock. A booking appears only once it has been paid.',
          style: T.micro,
        ),
      ),
    ];
  }
}

class _GrainSwitch extends StatelessWidget {
  const _GrainSwitch({required this.grain, required this.onChanged});

  final int grain;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Day', 'Week', 'Month'];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c(LamalivaColors.creamDeep),
        borderRadius: BorderRadius.circular(LamalivaShape.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: LamalivaMotion.quick,
                padding: const EdgeInsets.symmetric(
                  horizontal: LamalivaSpace.sm,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: grain == i ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(LamalivaShape.pill),
                  boxShadow: grain == i
                      ? [
                          BoxShadow(
                            color: c(
                              LamalivaColors.ink,
                            ).withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  style: T.micro.copyWith(
                    fontWeight: grain == i ? FontWeight.w700 : FontWeight.w500,
                    color: grain == i
                        ? c(LamalivaColors.navy800)
                        : c(LamalivaColors.inkMuted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.row,
    required this.grain,
    required this.peak,
    required this.last,
  });

  final Map<String, dynamic> row;
  final int grain;
  final double peak;
  final bool last;

  String _label() {
    if (grain == 1) {
      return 'Week of ${formatDate(row['week_start'] as String?)}';
    }
    if (grain == 2) {
      final month = DateTime.tryParse('${row['month']}-01');
      const names = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return month == null ? 'â€”' : '${names[month.month - 1]} ${month.year}';
    }
    return formatDate(row['date'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    final total = (row['total'] as num?)?.toDouble() ?? 0;
    final rooms = (row['rooms'] as num?)?.toDouble() ?? 0;
    final shop = (row['shop'] as num?)?.toDouble() ?? 0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_label(), style: T.bodyMuted)),
                  Text(
                    formatMoney(total),
                    style: T.numeral.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c(LamalivaColors.navy800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      if (rooms > 0)
                        Expanded(
                          flex: (rooms * 1000).round().clamp(1, 1000000),
                          child: ColoredBox(color: c(LamalivaColors.info)),
                        ),
                      if (shop > 0)
                        Expanded(
                          flex: (shop * 1000).round().clamp(1, 1000000),
                          child: ColoredBox(color: c(LamalivaColors.orangeMid)),
                        ),
                      if (total <= 0)
                        Expanded(
                          child: ColoredBox(color: c(LamalivaColors.creamDeep)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  _Key(
                    color: c(LamalivaColors.info),
                    label: formatMoney(rooms),
                  ),
                  const SizedBox(width: LamalivaSpace.sm),
                  _Key(
                    color: c(LamalivaColors.orangeMid),
                    label: formatMoney(shop),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!last) Divider(color: c(LamalivaColors.line), height: 1),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: T.micro),
      ],
    );
  }
}

/// One line of the ledger, in the words the desk uses: room 12, Eto'o paid
/// 40,000 for two nights; or three Malta at 1,500 from the shop.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final Map<String, dynamic> entry;

  String _method(String? method) {
    switch (method) {
      case 'momo':
        return 'Mobile Money';
      case 'transfer':
        return 'bank transfer';
      case 'card':
        return 'card';
      default:
        return 'cash';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRoom = entry['kind'] == 'room';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
    final refund = amount < 0;
    final title = isRoom
        ? 'Room ${entry['room'] ?? '—'} · ${entry['guest'] ?? 'Guest'}'
        : '${entry['item'] ?? 'Shop sale'}';
    final detail = isRoom
        ? '${entry['nights'] ?? 0} night${(entry['nights'] ?? 0) == 1 ? '' : 's'} '
              '(${formatDate(entry['arrival'] as String?)} to '
              '${formatDate(entry['departure'] as String?)}) · '
              '${refund ? 'refund' : 'paid'} by ${_method(entry['method'] as String?)}'
        : '${entry['quantity'] ?? 0} × ${formatMoney(entry['unit_price'] ?? 0)} · '
              '${_method(entry['method'] as String?)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c(LamalivaColors.creamDeep),
              borderRadius: BorderRadius.circular(LamalivaShape.card),
            ),
            child: Icon(
              isRoom ? Icons.bed_outlined : Icons.local_cafe_outlined,
              size: 17,
              color: c(LamalivaColors.navy800),
            ),
          ),
          const SizedBox(width: LamalivaSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(detail, style: T.micro),
              ],
            ),
          ),
          const SizedBox(width: LamalivaSpace.sm),
          Text(
            formatMoney(amount),
            style: T.numeral.copyWith(
              fontWeight: FontWeight.w700,
              color: refund
                  ? c(LamalivaColors.danger)
                  : c(LamalivaColors.navy800),
            ),
          ),
        ],
      ),
    );
  }
}
