import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// The guest book: who has stayed, and how to reach them.
class GuestsScreen extends StatefulWidget {
  const GuestsScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  late Future<List<dynamic>> _rows = widget.api.guests();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _rows = widget.api.guests());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _rows,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final all = snap.data ?? const <dynamic>[];
        final rows = all.where((raw) {
          if (raw is! Map) return false;
          if (_query.isEmpty) return true;
          final hay =
              '${raw['display_name'] ?? ''} ${raw['first_name'] ?? ''} '
                      '${raw['last_name'] ?? ''} ${raw['phone'] ?? ''} '
                      '${raw['email'] ?? ''} ${raw['reference'] ?? ''}'
                  .toLowerCase();
          return hay.contains(_query);
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
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Search name, phone or email',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
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
                Panel(
                  child: EmptyPanel(
                    title: all.isEmpty ? 'No guests yet' : 'No guests match',
                    body: all.isEmpty
                        ? 'Guests are added when the front desk records a booking.'
                        : 'Try a different name, phone number or reference.',
                    icon: Icons.people_outline,
                  ),
                )
              else
                Panel(
                  padding: const EdgeInsets.all(LamalivaSpace.xs),
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= 720
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
        const Padding(
          padding: EdgeInsets.fromLTRB(
            LamalivaSpace.md,
            LamalivaSpace.xs,
            LamalivaSpace.md,
            LamalivaSpace.xs,
          ),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('Guest', style: T.label)),
              SizedBox(width: 100, child: Text('Reference', style: T.label)),
              Expanded(flex: 2, child: Text('Phone', style: T.label)),
              Expanded(flex: 3, child: Text('Email', style: T.label)),
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
              child: _GuestRow(row: rows[i] as Map<String, dynamic>),
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
            child: _GuestCard(row: rows[i] as Map<String, dynamic>),
          ),
        ],
      ],
    );
  }
}

String _name(Map<String, dynamic> guest) {
  final display = guest['display_name'];
  if (display is String && display.trim().isNotEmpty) return display;
  final first = '${guest['first_name'] ?? ''}'.trim();
  final last = '${guest['last_name'] ?? ''}'.trim();
  final joined = '$first $last'.trim();
  return joined.isEmpty ? 'Guest' : joined;
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LamalivaSpace.md,
        vertical: LamalivaSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _name(row),
                    style: T.body.copyWith(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (row['vip'] == true)
                  Padding(
                    padding: const EdgeInsets.only(left: LamalivaSpace.xs),
                    child: StatusPill(status: 'vip', compact: true),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              '${row['reference'] ?? '—'}',
              style: T.numeral.copyWith(color: c(LamalivaColors.inkMuted)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${row['phone'] ?? '—'}', style: T.bodyMuted),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${row['email'] ?? '—'}',
              style: T.bodyMuted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(LamalivaSpace.sm),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c(LamalivaColors.creamDeep),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _name(row).characters.first.toUpperCase(),
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
                  _name(row),
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${row['phone'] ?? row['email'] ?? 'No contact detail'}',
                  style: T.micro,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (row['vip'] == true) StatusPill(status: 'vip', compact: true),
        ],
      ),
    );
  }
}
