import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Every booking, newest stay first, filterable by state.
class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  late Future<List<dynamic>> _rows = widget.api.reservations();
  String? _status;

  void _reload() => setState(() => _rows = widget.api.reservations());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _rows,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final all = snap.data ?? const <dynamic>[];
        final statuses = <String>{
          for (final r in all)
            if (r is Map && r['status'] != null) r['status'].toString(),
        }.toList()
          ..sort();
        final rows = all.where((raw) {
          if (raw is! Map) return false;
          return _status == null || raw['status']?.toString() == _status;
        }).toList();

        return RefreshIndicator(
          color: c(LamalivaColors.orangeMid),
          onRefresh: () async {
            _reload();
            await _rows;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.xl,
            ),
            children: [
              if (statuses.isNotEmpty)
                FilterBar(
                  options: statuses,
                  selected: _status,
                  onSelected: (value) => setState(() => _status = value),
                ),
              const SizedBox(height: LamalivaSpace.md),
              if (loading)
                const Panel(child: LoadingPanel(rows: 6))
              else if (snap.hasError)
                Panel(
                  child: ErrorPanel(
                    message: snap.error.toString(),
                    onRetry: _reload,
                  ),
                )
              else if (rows.isEmpty)
                const Panel(
                  child: EmptyPanel(
                    title: 'No bookings here',
                    body:
                        'Bookings appear as soon as the front desk records them. Change the filter to see other states.',
                    icon: Icons.event_note_outlined,
                  ),
                )
              else
                Panel(
                  padding: const EdgeInsets.all(LamalivaSpace.xs),
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 760
                            ? _table(rows)
                            : _cards(rows),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _table(List<dynamic> rows) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LamalivaSpace.md,
            LamalivaSpace.xs,
            LamalivaSpace.md,
            LamalivaSpace.xs,
          ),
          child: Row(
            children: const [
              SizedBox(width: 92, child: Text('Booking', style: T.label)),
              Expanded(flex: 3, child: Text('Guest', style: T.label)),
              SizedBox(width: 76, child: Text('Room', style: T.label)),
              SizedBox(width: 200, child: Text('Stay', style: T.label)),
              SizedBox(width: 60, child: Text('Nights', style: T.label)),
              SizedBox(width: 116, child: Text('Status', style: T.label)),
            ],
          ),
        ),
        Divider(color: c(LamalivaColors.line), height: 1),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
          Reveal(
            delay: Duration(milliseconds: (i * 24).clamp(0, 300)),
            offset: 8,
            child: HoverRow(
              child: _ReservationRow(row: rows[i] as Map<String, dynamic>),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cards(List<dynamic> rows) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
          Reveal(
            delay: Duration(milliseconds: (i * 24).clamp(0, 300)),
            offset: 8,
            child: _ReservationCard(row: rows[i] as Map<String, dynamic>),
          ),
        ],
      ],
    );
  }
}

class _ReservationRow extends StatelessWidget {
  const _ReservationRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final guest = (row['guest'] as Map?)?.cast<String, dynamic>();
    final room = (row['room'] as Map?)?.cast<String, dynamic>();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LamalivaSpace.md,
        vertical: LamalivaSpace.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '${row['reference'] ?? '—'}',
              style: T.numeral.copyWith(
                fontWeight: FontWeight.w600,
                color: c(LamalivaColors.inkMuted),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${guest?['display_name'] ?? 'Guest'}',
              style: T.body.copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 76,
            child: Text('${room?['number'] ?? '—'}', style: T.bodyMuted),
          ),
          SizedBox(
            width: 200,
            child: Text(
              '${formatDate(row['arrival'] as String?)}  →  ${formatDate(row['departure'] as String?)}',
              style: T.bodyMuted,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text('${row['nights'] ?? '—'}', style: T.numeral),
          ),
          SizedBox(
            width: 116,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(status: '${row['status'] ?? ''}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final guest = (row['guest'] as Map?)?.cast<String, dynamic>();
    final room = (row['room'] as Map?)?.cast<String, dynamic>();
    return Padding(
      padding: const EdgeInsets.all(LamalivaSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${guest?['display_name'] ?? 'Guest'}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              StatusPill(status: '${row['status'] ?? ''}', compact: true),
            ],
          ),
          const SizedBox(height: LamalivaSpace.xs),
          Row(
            children: [
              Icon(
                Icons.meeting_room_outlined,
                size: 14,
                color: c(LamalivaColors.inkFaint),
              ),
              const SizedBox(width: 4),
              Text('Room ${room?['number'] ?? '—'}', style: T.micro),
              const SizedBox(width: LamalivaSpace.sm),
              Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: c(LamalivaColors.inkFaint),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${formatDate(row['arrival'] as String?)} → ${formatDate(row['departure'] as String?)}',
                  style: T.micro,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
