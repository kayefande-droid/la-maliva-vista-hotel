import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../guidance.dart';
import '../theme.dart';
import '../widgets.dart';

/// Administrator tools: staff accounts and room rates. The rest of the console
/// hides this screen entirely, and the server refuses both actions to any
/// non-admin role regardless of what the app shows.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.api});

  final LamalivaApi api;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<List<dynamic>> _staff = widget.api.staffAccounts();
  late Future<List<dynamic>> _types = widget.api.roomTypes();
  late Future<List<dynamic>> _audit = widget.api.auditLog();

  void _reload() => setState(() {
    _staff = widget.api.staffAccounts();
    _types = widget.api.roomTypes();
    _audit = widget.api.auditLog();
  });

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LamalivaSpace.lg,
        LamalivaSpace.lg,
        LamalivaSpace.lg,
        LamalivaSpace.xl,
      ),
      children: [
        Panel(
          title: 'Staff accounts',
          trailing: GhostButton(
            label: 'New account',
            icon: Icons.person_add_alt_1,
            onPressed: _createStaff,
          ),
          child: FutureBuilder<List<dynamic>>(
            future: _staff,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LoadingPanel(rows: 3);
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
                  title: 'No staff accounts',
                  body:
                      'Create the first account; the person must change the password at first sign-in.',
                  icon: Icons.badge_outlined,
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(color: c(LamalivaColors.line), height: 1),
                    _StaffRow(row: rows[i] as Map<String, dynamic>),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        Panel(
          title: 'Room rates',
          child: FutureBuilder<List<dynamic>>(
            future: _types,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LoadingPanel(rows: 2);
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
                  title: 'No room types',
                  body:
                      'Room types carry the nightly rate that registration charges.',
                  icon: Icons.sell_outlined,
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(color: c(LamalivaColors.line), height: 1),
                    _RateRow(
                      row: rows[i] as Map<String, dynamic>,
                      onEdit: () => _editRate(rows[i] as Map<String, dynamic>),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        Panel(
          title: 'Guidance for the team',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Instructions appear at the top of screens and in Help. Only an '
                'administrator can hide them; staff keep their own language.',
                style: T.bodyMuted,
              ),
              const SizedBox(height: LamalivaSpace.sm),
              ValueListenableBuilder<bool>(
                valueListenable: AppSettings.guidance,
                builder: (context, on, _) => SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Show in-app guidance', style: T.body),
                  subtitle: Text(
                    on
                        ? 'Staff see how-to cards while they work.'
                        : 'Hidden on this device until you switch it back on.',
                    style: T.micro,
                  ),
                  value: on,
                  onChanged: (value) => AppSettings.setGuidance(value),
                ),
              ),
              Divider(color: c(LamalivaColors.line), height: 1),
              const SizedBox(height: LamalivaSpace.sm),
              Text('App language', style: T.body),
              const SizedBox(height: LamalivaSpace.xs),
              ValueListenableBuilder<String>(
                valueListenable: AppSettings.language,
                builder: (context, code, _) => Row(
                  children: [
                    for (final choice in const [
                      ('en', 'English'),
                      ('fr', 'Fran\u00e7ais'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: LamalivaSpace.xs),
                        child: ChoiceChip(
                          label: Text(choice.$2),
                          selected: code == choice.$1,
                          onSelected: (_) => AppSettings.setLanguage(choice.$1),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                'English and French are the working languages of the hotel; '
                'guidance switches too. Names, money and records never change.',
                style: T.micro,
              ),
            ],
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        Panel(
          title: 'Activity log',
          child: FutureBuilder<List<dynamic>>(
            future: _audit,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LoadingPanel(rows: 3);
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
                  title: 'Nothing recorded yet',
                  body:
                      'Payments, check-ins, stock moves and resets appear here.',
                  icon: Icons.history_outlined,
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < rows.length && i < 40; i++) ...[
                    if (i > 0)
                      Divider(color: c(LamalivaColors.line), height: 1),
                    _AuditRow(row: (rows[i] as Map).cast<String, dynamic>()),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        Panel(
          title: 'This device',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Clear this phone or computer: saved server address, cached '
                'screens and any work waiting to be sent. The hotel records on '
                'the server are not touched.',
                style: T.bodyMuted,
              ),
              const SizedBox(height: LamalivaSpace.sm),
              GhostButton(
                label: 'Reset this device',
                icon: Icons.restart_alt,
                onPressed: _resetDevice,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Two deliberate confirmations, the second typed, so a tired hand cannot
  /// wipe the device by accident.
  Future<void> _resetDevice() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset this device?'),
        content: const Text(
          'Saved server address, cached rooms and any payments waiting to be '
          'sent will be removed from this device. Hotel records on the server '
          'stay exactly as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep everything'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final typing = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Type RESET to confirm'),
        content: TextField(
          controller: typing,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'RESET'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              typing.text.trim().toUpperCase() == 'RESET',
            ),
            child: const Text('Reset now'),
          ),
        ],
      ),
    );
    typing.dispose();
    if (second != true || !mounted) return;

    await AppSettings.resetDevice();
    _toast('This device has been reset. Hotel records were not changed.');
  }

  Future<void> _createStaff() async {
    final username = TextEditingController();
    final fullName = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    String role = 'receptionist';
    const roles = [
      ('receptionist', 'Receptionist'),
      ('housekeeping', 'Housekeeping'),
      ('inventory', 'Inventory'),
      ('manager', 'Manager'),
      ('admin', 'Administrator'),
    ];

    final created = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LamalivaShape.panel),
          ),
          title: Text(
            'New staff account',
            style: T.screenTitle.copyWith(fontSize: 22),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: LamalivaSpace.sm),
                TextField(
                  controller: fullName,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: LamalivaSpace.sm),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                  ),
                ),
                const SizedBox(height: LamalivaSpace.sm),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final (value, label) in roles)
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? 'receptionist'),
                ),
                const SizedBox(height: LamalivaSpace.sm),
                TextField(
                  controller: password,
                  decoration: const InputDecoration(
                    labelText: 'Password (leave empty to generate one)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('create'),
              child: const Text('Create account'),
            ),
          ],
        ),
      ),
    );

    if (created != 'create' || !mounted) return;
    try {
      final res = await widget.api.createStaff(
        username: username.text.trim(),
        fullName: fullName.text.trim(),
        role: role,
        email: email.text,
        password: password.text,
      );
      final generated = ((res['meta'] as Map?)?['generated_password'])
          ?.toString();
      _reload();
      _toast(
        generated == null
            ? 'Account created.'
            : 'Account created. One-time password: $generated',
      );
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _editRate(Map<String, dynamic> row) async {
    final rate = TextEditingController(text: '${row['base_rate']}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LamalivaShape.panel),
        ),
        title: Text(
          '${row['name']} nightly rate',
          style: T.screenTitle.copyWith(fontSize: 22),
        ),
        content: TextField(
          controller: rate,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Rate per night (XAF)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save rate'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final value = num.tryParse(rate.text.trim());
    if (value == null || value < 0) {
      _toast('Enter a valid nightly rate.');
      return;
    }
    try {
      await widget.api.updateRoomType(row['id'] as int, baseRate: value);
      _reload();
      _toast('Room rate updated.');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c(LamalivaColors.navy800),
              borderRadius: BorderRadius.circular(LamalivaShape.card),
            ),
            child: Center(
              child: Text(
                '${row['full_name'] ?? row['username'] ?? '?'}'.characters.first
                    .toUpperCase(),
                style: T.numeral.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
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
                  '${row['full_name'] ?? row['username']}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '@${row['username']}  ·  ${row['email'] ?? 'no email'}',
                  style: T.micro,
                ),
              ],
            ),
          ),
          if (row['must_change_password'] == true)
            Padding(
              padding: const EdgeInsets.only(right: LamalivaSpace.xs),
              child: Text('must change password', style: T.micro),
            ),
          StatusPill(status: '${row['role'] ?? ''}', compact: true),
        ],
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({required this.row, required this.onEdit});

  final Map<String, dynamic> row;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LamalivaSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['name']}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Sleeps ${row['capacity'] ?? '—'}'
                  '${row['size_sqm'] == null ? '' : '  ·  ${row['size_sqm']} m²'}',
                  style: T.micro,
                ),
              ],
            ),
          ),
          Text(
            formatMoney(row['base_rate']),
            style: T.numeral.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: LamalivaSpace.xs),
          GhostButton(
            label: 'Edit rate',
            icon: Icons.edit_outlined,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.row});

  final Map<String, dynamic> row;

  String get _human {
    final action = '${row['action'] ?? ''}';
    final parts = action.split('.');
    if (parts.length == 2) {
      final what = parts[0].replaceAll('_', ' ');
      final how = parts[1].replaceAll('_', ' ');
      return '${what[0].toUpperCase()}${what.substring(1)} - $how';
    }
    return action.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final at = '${row['created_at'] ?? ''}';
    final when = at.length >= 16
        ? at.substring(0, 16).replaceFirst('T', ' ')
        : at;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_human, style: T.bodyMuted),
                Text(
                  '${row['actor_name'] ?? 'System'} - ${row['entity'] ?? ''}'
                  '${row['entity_id'] == null ? '' : ' #${row['entity_id']}'}',
                  style: T.micro,
                ),
              ],
            ),
          ),
          const SizedBox(width: LamalivaSpace.sm),
          Text(when, style: T.micro),
        ],
      ),
    );
  }
}
