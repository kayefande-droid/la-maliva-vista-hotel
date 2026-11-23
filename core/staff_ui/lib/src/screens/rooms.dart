import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../stay_sheets.dart';
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
  /// The board joins the rooms to the stays holding them, so an occupied room
  /// shows who is in it and when they are due out — not just a blue pill.
  late Future<(List<dynamic>, Map<int, Map<String, dynamic>>)> _board = _load();
  final _search = TextEditingController();
  String _query = '';
  String? _status;

  Future<(List<dynamic>, Map<int, Map<String, dynamic>>)> _load() async {
    final results = await Future.wait([
      widget.api.rooms(byUsage: true),
      widget.api.stayMonitor(),
    ]);
    final stays =
        (results[1] as Map<String, dynamic>)['stays'] as List? ?? const [];
    final byRoom = <int, Map<String, dynamic>>{};
    for (final raw in stays) {
      if (raw is! Map) continue;
      final room = raw['room'];
      if (room is! Map) continue;
      final id = (room['id'] as num?)?.toInt();
      if (id == null) continue;
      byRoom[id] = raw.cast<String, dynamic>();
    }
    return (results[0] as List<dynamic>, byRoom);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _board = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<dynamic>, Map<int, Map<String, dynamic>>)>(
      future: _board,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final all = snap.data?.$1 ?? const <dynamic>[];
        final stays = snap.data?.$2 ?? const <int, Map<String, dynamic>>{};
        final statuses = <String>{
          for (final r in all)
            if (r is Map && r['status'] != null) r['status'].toString(),
        }.toList()..sort();

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
            await _board;
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
                          ? _table(filtered, stays)
                          : _cards(filtered, stays);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _table(List<dynamic> rooms, Map<int, Map<String, dynamic>> stays) {
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
              SizedBox(width: 64, child: Text('Room', style: T.label)),
              Expanded(flex: 3, child: Text('Type', style: T.label)),
              SizedBox(width: 72, child: Text('Floor', style: T.label)),
              SizedBox(width: 140, child: Text('Rate', style: T.label)),
              SizedBox(width: 132, child: Text('Status', style: T.label)),
            ],
          ),
        ),
        Divider(color: c(LamalivaColors.line), height: 1),
        for (var i = 0; i < rooms.length; i++) ...[
          if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
          Reveal(
            delay: Duration(milliseconds: (i * 24).clamp(0, 300)),
            offset: 8,
            child: _RoomRow(
              api: widget.api,
              room: rooms[i] as Map<String, dynamic>,
              stay: stays[(rooms[i]['id'] as num?)?.toInt()],
              onChanged: _reload,
            ),
          ),
        ],
      ],
    );
  }

  Widget _cards(List<dynamic> rooms, Map<int, Map<String, dynamic>> stays) {
    return Column(
      children: [
        for (var i = 0; i < rooms.length; i++) ...[
          if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
          Reveal(
            delay: Duration(milliseconds: (i * 24).clamp(0, 300)),
            offset: 8,
            child: _RoomCard(
              api: widget.api,
              room: rooms[i] as Map<String, dynamic>,
              stay: stays[(rooms[i]['id'] as num?)?.toInt()],
              onChanged: _reload,
            ),
          ),
        ],
      ],
    );
  }
}

/// The guest and the checkout clock for a room that is currently held.
class _OccupiedLine extends StatelessWidget {
  const _OccupiedLine({required this.stay});

  final Map<String, dynamic> stay;

  @override
  Widget build(BuildContext context) {
    final clock = (stay['clock'] as Map?)?.cast<String, dynamic>() ?? const {};
    final guest = (stay['guest'] as Map?)?.cast<String, dynamic>() ?? const {};
    final overdue = clock['is_overdue'] == true;
    final money = (stay['money'] as Map?)?.cast<String, dynamic>() ?? const {};
    final balance = (money['balance'] as num?)?.toDouble() ?? 0;
    return Text(
      '${guest['display_name'] ?? 'Guest'}  ·  out ${clockTime(clock['expected_checkout_local'])}'
      '${balance > 0 ? '  ·  ${formatMoney(balance)} due' : ''}'
      '${overdue ? '  ·  overdue' : ''}',
      style: T.micro.copyWith(
        color: overdue ? c(LamalivaColors.danger) : null,
        fontWeight: overdue ? FontWeight.w600 : null,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _RoomRow extends StatefulWidget {
  const _RoomRow({
    required this.api,
    required this.room,
    required this.stay,
    required this.onChanged,
  });

  final LamalivaApi api;
  final Map<String, dynamic> room;
  final Map<String, dynamic>? stay;
  final VoidCallback onChanged;

  @override
  State<_RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<_RoomRow> {
  bool _hover = false;
  bool _cleaning = false;

  /// Housekeeping's one tap: the room is done and goes back to available.
  Future<void> _markCleaned() async {
    if (_cleaning) return;
    setState(() => _cleaning = true);
    try {
      await widget.api.markRoomCleaned(widget.room['id'] as int);
      widget.onChanged();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _open() async {
    final stay = widget.stay;
    if (stay == null) return;
    await showStaySheet(
      context,
      api: widget.api,
      stay: stay,
      onChanged: widget.onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final stay = widget.stay;
    final type = (room['room_type'] as Map?)?.cast<String, dynamic>();
    final status = '${room['status'] ?? ''}';
    final clock = (stay?['clock'] as Map?)?.cast<String, dynamic>() ?? const {};
    final overdue = clock['is_overdue'] == true;
    final remaining = (clock['minutes_remaining'] as num?)?.toInt() ?? 0;
    return MouseRegion(
      cursor: stay == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: stay == null ? null : _open,
        child: AnimatedContainer(
          duration: LamalivaMotion.instant,
          color: _hover && stay != null
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
                      if (stay != null)
                        _OccupiedLine(stay: stay)
                      else if (type?['capacity'] != null)
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
                  child: Text('${room['floor'] ?? '—'}', style: T.bodyMuted),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    formatMoney(type?['base_rate']),
                    style: T.numeral.copyWith(
                      color: c(LamalivaColors.inkMuted),
                    ),
                  ),
                ),
                if (status == 'cleaning')
                  SizedBox(
                    width: 148,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _cleaning ? null : _markCleaned,
                        icon: _cleaning
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Mark cleaned'),
                        style: TextButton.styleFrom(
                          foregroundColor: c(LamalivaColors.navy800),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: 132,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusPill(status: status),
                        if (stay != null &&
                            clock['minutes_remaining'] != null) ...[
                          const SizedBox(height: 4),
                          StayCountdown(
                            minutes: remaining,
                            overdue: overdue,
                            prefix: overdue ? '+' : '',
                            style: T.micro.copyWith(
                              color: overdue
                                  ? c(LamalivaColors.danger)
                                  : c(LamalivaColors.inkMuted),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.api,
    required this.room,
    required this.stay,
    required this.onChanged,
  });

  final LamalivaApi api;
  final Map<String, dynamic> room;
  final Map<String, dynamic>? stay;
  final VoidCallback onChanged;

  Future<void> _open(BuildContext context) async {
    final current = stay;
    if (current == null) return;
    await showStaySheet(context, api: api, stay: current, onChanged: onChanged);
  }

  @override
  Widget build(BuildContext context) {
    final type = (room['room_type'] as Map?)?.cast<String, dynamic>();
    final clock = (stay?['clock'] as Map?)?.cast<String, dynamic>() ?? const {};
    final overdue = clock['is_overdue'] == true;
    final remaining = (clock['minutes_remaining'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: stay == null ? null : () => _open(context),
      child: Padding(
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
                  if (stay != null)
                    _OccupiedLine(stay: stay!)
                  else
                    Text(
                      'Floor ${room['floor'] ?? '—'}  ·  ${formatMoney(type?['base_rate'])}',
                      style: T.micro,
                    ),
                ],
              ),
            ),
            const SizedBox(width: LamalivaSpace.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusPill(status: '${room['status'] ?? ''}', compact: true),
                if (stay != null && clock['minutes_remaining'] != null) ...[
                  const SizedBox(height: 3),
                  StayCountdown(
                    minutes: remaining,
                    overdue: overdue,
                    prefix: overdue ? '+' : '',
                    style: T.micro.copyWith(
                      color: overdue
                          ? c(LamalivaColors.danger)
                          : c(LamalivaColors.inkMuted),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
