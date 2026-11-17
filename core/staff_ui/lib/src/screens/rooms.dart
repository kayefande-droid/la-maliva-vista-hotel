import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// The rooms board: every room, its type, its rate and what state it is in.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  late Future<List<dynamic>> _rooms = widget.api.rooms();
  final _search = TextEditingController();
  String _query = '';
  String? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _rooms = widget.api.rooms());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _rooms,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final all = snap.data ?? const <dynamic>[];
        final statuses = <String>{
          for (final r in all)
            if (r is Map && r['status'] != null) r['status'].toString(),
        }.toList()
          ..sort();

        final filtered = all.where((raw) {
          if (raw is! Map) return false;
          if (_status != null && raw['status']?.toString() != _status) {
            return false;
          }
          if (_query.isEmpty) return true;
          final type = (raw['room_type'] as Map?)?['name'] ?? '';
          return '${raw['number']} $type'.toLowerCase().contains(_query);
        }).toList();

        return RefreshIndicator(
          color: c(LamalivaColors.orangeMid),
          onRefresh: () async {
            _reload();
            await _rooms;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.xl,
            ),
            children: [
              Wrap(
                spacing: LamalivaSpace.sm,
                runSpacing: LamalivaSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search room or type',
                        prefixIcon: Icon(Icons.search, size: 18),
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  if (statuses.isNotEmpty)
                    FilterBar(
                      options: statuses,
                      selected: _status,
                      onSelected: (value) => setState(() => _status = value),
                    ),
                ],
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
              else if (filtered.isEmpty)
                Panel(
                  child: EmptyPanel(
                    title: all.isEmpty ? 'No rooms yet' : 'No rooms match',
                    body: all.isEmpty
                        ? 'Create room types and rooms to see them here.'
                        : 'Try another status or clear the search.',
                    icon: Icons.meeting_room_outlined,
                  ),
                )
              else
                Panel(
                  padding: const EdgeInsets.all(LamalivaSpace.xs),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 720;
                      return wide
                          ? _table(filtered)
                          : _cards(filtered);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _table(List<dynamic> rooms) {
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
            children: [
              const SizedBox(width: 64, child: Text('Room', style: T.label)),
              Expanded(flex: 3, child: Text('Type', style: T.label)),
              const SizedBox(width: 72, child: Text('Floor', style: T.label)),
              const SizedBox(width: 140, child: Text('Rate', style: T.label)),
              const SizedBox(width: 120, child: Text('Status', style: T.label)),
            ],
          ),
        ),
        Divider(color: c(LamalivaColors.line), height: 1),
        for (var i = 0; i < rooms.length; i++) ...[
          if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
          Reveal(
            delay: Duration(milliseconds: (i * 24).clamp(0, 300)),
            offset: 8,
            child: _RoomRow(room: rooms[i] as Map<String, dynamic>),
          ),
        ],
      ],
    );
  }

  Widget _cards(List<dynamic> rooms) {
    return Column(
      children: [
        for (var i = 0; i < rooms.length; i++) ...[
          if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
          Reveal(
            delay: Duration(milliseconds: (i * 24).clamp(0, 300)),
            offset: 8,
            child: _RoomCard(room: rooms[i] as Map<String, dynamic>),
          ),
        ],
      ],
    );
  }
}

class _RoomRow extends StatefulWidget {
  const _RoomRow({required this.room});

  final Map<String, dynamic> room;

  @override
  State<_RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<_RoomRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final type = (room['room_type'] as Map?)?.cast<String, dynamic>();
    final status = '${room['status'] ?? ''}';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: LamalivaMotion.instant,
        color: _hover
            ? c(LamalivaColors.cream).withValues(alpha: 0.7)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LamalivaSpace.md,
            vertical: LamalivaSpace.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Reference('${room['number'] ?? '—'}'),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${type?['name'] ?? 'Room'}',
                      style: T.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (type?['capacity'] != null)
                      Text(
                        'Sleeps ${type!['capacity']}'
                        '${type['size_sqm'] == null ? '' : '  ·  ${type['size_sqm']} m²'}',
                        style: T.micro,
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '${room['floor'] ?? '—'}',
                  style: T.bodyMuted,
                ),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  formatMoney(type?['base_rate']),
                  style: T.numeral.copyWith(color: c(LamalivaColors.inkMuted)),
                ),
              ),
              SizedBox(
                width: 120,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(status: status),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room});

  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final type = (room['room_type'] as Map?)?.cast<String, dynamic>();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LamalivaSpace.sm,
        vertical: LamalivaSpace.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c(LamalivaColors.navy800),
              borderRadius: BorderRadius.circular(LamalivaShape.card),
            ),
            child: Center(
              child: Text(
                '${room['number'] ?? '—'}',
                style: T.numeral.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: LamalivaSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type?['name'] ?? 'Room'}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Floor ${room['floor'] ?? '—'}  ·  ${formatMoney(type?['base_rate'])}',
                  style: T.micro,
                ),
              ],
            ),
          ),
          StatusPill(status: '${room['status'] ?? ''}', compact: true),
        ],
      ),
    );
  }
}
