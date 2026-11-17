import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Front desk registration: pick a room, capture genuine identification, and
/// the server seals the guest record and marks the room occupied.
class RegisterGuestScreen extends StatefulWidget {
  const RegisterGuestScreen({super.key, required this.api, this.onDone});

  final LamalivaApi api;
  final VoidCallback? onDone;

  @override
  State<RegisterGuestScreen> createState() => _RegisterGuestScreenState();
}

class _RegisterGuestScreenState extends State<RegisterGuestScreen> {
  late Future<List<dynamic>> _rooms = widget.api.rooms();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _idNumber = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _rate = TextEditingController();

  int? _roomId;
  String _idType = 'cni';
  int _nights = 1;
  int _adults = 1;
  int _children = 0;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _receipt;

  static const _idOptions = <(String, String, String)>[
    (
      'cni',
      'Cameroon national ID (CNI)',
      '9 to 12 digits as printed on the card',
    ),
    (
      'birth_certificate',
      'Birth certificate / kit number',
      'Letters and digits',
    ),
    ('passport', 'Passport', 'One or two letters, then six to eight digits'),
    (
      'residence_permit',
      'Residence permit',
      'Permit number, letters and digits',
    ),
  ];

  @override
  void dispose() {
    for (final c in [
      _first,
      _last,
      _phone,
      _email,
      _idNumber,
      _address,
      _notes,
      _rate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final roomId = _roomId;
    if (roomId == null) {
      setState(() => _error = 'Choose the room the guest is taking.');
      return;
    }
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      setState(() => _error = 'First and last name are required.');
      return;
    }
    if (_idNumber.text.trim().isEmpty) {
      setState(
        () => _error =
            'The identification number is required. Registration is final.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.registerGuest(
        roomId: roomId,
        nights: _nights,
        adults: _adults,
        children: _children,
        ratePerNight: widget.api.isAdmin && _rate.text.trim().isNotEmpty
            ? num.tryParse(_rate.text.trim())
            : null,
        notes: _notes.text,
        guest: {
          'first_name': _first.text.trim(),
          'last_name': _last.text.trim(),
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
          'address': _address.text.trim(),
          'id_type': _idType,
          'id_number': _idNumber.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _receipt = data);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _receipt == null ? _form() : _confirmation(_receipt!);
  }

  Widget _form() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg,
            ),
            children: [
              Panel(
                title: 'Room',
                child: FutureBuilder<List<dynamic>>(
                  future: _rooms,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const LoadingPanel(rows: 2);
                    }
                    if (snap.hasError) {
                      return ErrorPanel(
                        message: snap.error.toString(),
                        onRetry: () =>
                            setState(() => _rooms = widget.api.rooms()),
                      );
                    }
                    final rooms = (snap.data ?? const []).where((raw) {
                      if (raw is! Map) return false;
                      final status = '${raw['status'] ?? ''}';
                      return status != 'maintenance' && status != 'occupied';
                    }).toList();
                    if (rooms.isEmpty) {
                      return const EmptyPanel(
                        title: 'No free rooms',
                        body:
                            'Every room is occupied or blocked. Check a guest out first.',
                        icon: Icons.meeting_room_outlined,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: LamalivaSpace.xs,
                          runSpacing: LamalivaSpace.xs,
                          children: [
                            for (final raw in rooms)
                              _RoomChip(
                                room: raw as Map<String, dynamic>,
                                selected: _roomId == raw['id'],
                                onTap: () =>
                                    setState(() => _roomId = raw['id'] as int?),
                              ),
                          ],
                        ),
                        const SizedBox(height: LamalivaSpace.md),
                        Row(
                          children: [
                            Expanded(
                              child: _Stepper(
                                label: 'Nights',
                                value: _nights,
                                min: 1,
                                max: 365,
                                onChanged: (v) => setState(() => _nights = v),
                              ),
                            ),
                            const SizedBox(width: LamalivaSpace.sm),
                            Expanded(
                              child: _Stepper(
                                label: 'Adults',
                                value: _adults,
                                min: 1,
                                max: 12,
                                onChanged: (v) => setState(() => _adults = v),
                              ),
                            ),
                            const SizedBox(width: LamalivaSpace.sm),
                            Expanded(
                              child: _Stepper(
                                label: 'Children',
                                value: _children,
                                min: 0,
                                max: 12,
                                onChanged: (v) => setState(() => _children = v),
                              ),
                            ),
                          ],
                        ),
                        if (widget.api.isAdmin) ...[
                          const SizedBox(height: LamalivaSpace.sm),
                          TextField(
                            controller: _rate,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText:
                                  'Rate per night (admin override, optional)',
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: LamalivaSpace.md),
              Panel(
                title: 'Guest identification',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _first,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                            ),
                          ),
                        ),
                        const SizedBox(width: LamalivaSpace.sm),
                        Expanded(
                          child: TextField(
                            controller: _last,
                            decoration: const InputDecoration(
                              labelText: 'Last name',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LamalivaSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _idType,
                            decoration: const InputDecoration(
                              labelText: 'Document',
                            ),
                            items: [
                              for (final (value, label, _) in _idOptions)
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(label),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _idType = v ?? 'cni'),
                          ),
                        ),
                        const SizedBox(width: LamalivaSpace.sm),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _idNumber,
                            decoration: InputDecoration(
                              labelText: 'Original document number',
                              helperText: _idOptions
                                  .firstWhere(
                                    (o) => o.$1 == _idType,
                                    orElse: () => _idOptions.first,
                                  )
                                  .$3,
                            ),
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LamalivaSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              hintText: '+237 6XX XXX XXX',
                            ),
                          ),
                        ),
                        const SizedBox(width: LamalivaSpace.sm),
                        Expanded(
                          child: TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email (optional)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LamalivaSpace.sm),
                    TextField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'Address (optional)',
                      ),
                    ),
                    const SizedBox(height: LamalivaSpace.sm),
                    TextField(
                      controller: _notes,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    const SizedBox(height: LamalivaSpace.md),
                    Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 15,
                          color: c(LamalivaColors.warning),
                        ),
                        const SizedBox(width: LamalivaSpace.xs),
                        Expanded(
                          child: Text(
                            'This record is sealed when saved and cannot be edited afterwards. '
                            'The identification number is only visible to an administrator.',
                            style: T.micro,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: LamalivaSpace.md),
                Container(
                  padding: const EdgeInsets.all(LamalivaSpace.sm),
                  decoration: BoxDecoration(
                    color: c(LamalivaColors.dangerSoft).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(LamalivaShape.card),
                  ),
                  child: Text(
                    _error!,
                    style: T.bodyMuted.copyWith(
                      color: c(LamalivaColors.danger),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _actionBar(),
      ],
    );
  }

  /// The submit action stays on screen: on a 720p laptop the form is taller
  /// than the window, and a save button below the fold gets missed.
  Widget _actionBar() {
    return Container(
      decoration: BoxDecoration(
        color: c(LamalivaColors.cream),
        border: Border(
          top: BorderSide(
            color: c(LamalivaColors.line),
            width: LamalivaShape.hairline,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: LamalivaSpace.lg,
        vertical: LamalivaSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'The room is marked occupied the moment you register.',
              style: T.micro.copyWith(color: c(LamalivaColors.inkMuted)),
            ),
          ),
          const SizedBox(width: LamalivaSpace.md),
          SizedBox(
            width: 320,
            child: PrimaryButton(
              label: 'Register guest and occupy room',
              busy: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmation(Map<String, dynamic> receipt) {
    final guest =
        (receipt['guest'] as Map?)?.cast<String, dynamic>() ?? const {};
    final reservation =
        (receipt['reservation'] as Map?)?.cast<String, dynamic>() ?? const {};
    final room = (reservation['room'] as Map?)?.cast<String, dynamic>();
    final seal = '${guest['seal'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(LamalivaSpace.lg),
      children: [
        Panel(
          padding: const EdgeInsets.all(LamalivaSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.verified_outlined,
                size: 34,
                color: c(LamalivaColors.success),
              ),
              const SizedBox(height: LamalivaSpace.sm),
              Text(
                '${guest['display_name'] ?? 'Guest'} is in room ${room?['number'] ?? '—'}',
                style: T.screenTitle.copyWith(fontSize: 24),
              ),
              const SizedBox(height: LamalivaSpace.xs),
              Text(
                'Reference ${guest['reference'] ?? '—'}  ·  '
                '${reservation['nights'] ?? 0} night(s)  ·  '
                '${formatMoney(reservation['total_amount'])}',
                style: T.bodyMuted,
              ),
              const SizedBox(height: LamalivaSpace.md),
              Container(
                padding: const EdgeInsets.all(LamalivaSpace.sm),
                decoration: BoxDecoration(
                  color: c(LamalivaColors.cream),
                  borderRadius: BorderRadius.circular(LamalivaShape.card),
                  border: Border.all(color: c(LamalivaColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Record seal', style: T.label),
                    const SizedBox(height: 2),
                    SelectableText(
                      seal.isEmpty ? '—' : seal,
                      style: T.micro.copyWith(
                        fontFamily: LamalivaType.monoFamily,
                        color: c(LamalivaColors.inkMuted),
                      ),
                    ),
                    const SizedBox(height: LamalivaSpace.xxs),
                    Text(
                      'Store this against the paper registration card. '
                      'It proves the record has not been altered.',
                      style: T.micro,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LamalivaSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Register another guest',
                      icon: Icons.person_add_alt,
                      onPressed: () => setState(() {
                        _receipt = null;
                        _roomId = null;
                        _idNumber.clear();
                        _first.clear();
                        _last.clear();
                        _phone.clear();
                        _email.clear();
                        _address.clear();
                        _notes.clear();
                        _rooms = widget.api.rooms();
                      }),
                    ),
                  ),
                  const SizedBox(width: LamalivaSpace.sm),
                  Expanded(
                    child: GhostButton(
                      label: 'Done',
                      icon: Icons.check,
                      onPressed: () {
                        widget.onDone?.call();
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.room,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> room;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = (room['room_type'] as Map?)?['name'] ?? 'Room';
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: LamalivaMotion.quick,
          padding: const EdgeInsets.symmetric(
            horizontal: LamalivaSpace.sm,
            vertical: LamalivaSpace.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? c(LamalivaColors.navy800) : Colors.white,
            borderRadius: BorderRadius.circular(LamalivaShape.card),
            border: Border.all(
              color: selected
                  ? c(LamalivaColors.navy800)
                  : c(LamalivaColors.line),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${room['number']}',
                style: T.numeral.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : c(LamalivaColors.navy800),
                ),
              ),
              Text(
                '$type',
                style: T.micro.copyWith(
                  color: selected ? Colors.white70 : c(LamalivaColors.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.label),
        const SizedBox(height: LamalivaSpace.xxs),
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(LamalivaShape.input),
            border: Border.all(color: c(LamalivaColors.line)),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Decrease $label',
                onPressed: value > min ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: T.numeral.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Increase $label',
                onPressed: value < max ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
