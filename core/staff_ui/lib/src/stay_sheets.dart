import 'dart:async';

import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import 'api.dart';
import 'invoice.dart';
import 'offline.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Stay vocabulary, shared by the dashboard, the room board and the sheets.
// ---------------------------------------------------------------------------

/// The server's state word, in the desk's words.
String stayStateLabel(String state) {
  switch (state) {
    case 'active':
      return 'In house';
    case 'checkout_approaching':
      return 'Checkout soon';
    case 'checkout_due':
      return 'Due now';
    case 'overdue':
      return 'Overdue';
    case 'checked_out':
      return 'Checked out';
    case 'reserved':
      return 'Reserved';
    default:
      return state.isEmpty ? 'In house' : StatusPill.labelFor(state);
  }
}

Color stayStateColor(String state) {
  switch (state) {
    case 'checkout_approaching':
    case 'checkout_due':
      return c(LamalivaColors.warning);
    case 'overdue':
      return c(LamalivaColors.danger);
    case 'checked_out':
      return c(LamalivaColors.inkMuted);
    case 'active':
      return c(LamalivaColors.info);
    default:
      return c(LamalivaColors.inkMuted);
  }
}

/// `2h 41m`, `18m`, `2d 4h` — the length of time, never signed.
String durationLabel(int minutes) {
  final m = minutes.abs();
  if (m < 60) return '${m}m';
  final hours = m ~/ 60;
  final rest = m % 60;
  if (hours < 24) return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  final days = hours ~/ 24;
  final rem = hours % 24;
  return rem == 0 ? '${days}d' : '${days}d ${rem}h';
}

/// `2026-11-22T12:00:00+01:00` → `12:00`. The server already sends hotel-local
/// time, so the string is read as text rather than converted to device time.
String clockTime(Object? iso) {
  final text = iso?.toString() ?? '';
  if (text.length < 16 || !text.contains('T')) return '—';
  return text.substring(11, 16);
}

String dayLabel(Object? iso) {
  final text = iso?.toString() ?? '';
  if (text.length < 10) return '—';
  return formatDate(text.substring(0, 10));
}

Map<String, dynamic> _map(Object? value) =>
    (value as Map?)?.cast<String, dynamic>() ?? const {};

bool _flag(Object? value) => value == true;

/// A countdown that ticks without trusting the device clock: the server sends
/// minutes remaining, and a local stopwatch carries it forward from there.
class StayCountdown extends StatefulWidget {
  const StayCountdown({
    super.key,
    required this.minutes,
    required this.overdue,
    this.style,
    this.prefix = '',
  });

  final int minutes;
  final bool overdue;
  final TextStyle? style;
  final String prefix;

  @override
  State<StayCountdown> createState() => _StayCountdownState();
}

class _StayCountdownState extends State<StayCountdown> {
  late final Stopwatch _watch = Stopwatch()..start();
  late final Timer _timer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var seconds = widget.minutes * 60 - _watch.elapsed.inSeconds;
    final overdue = widget.overdue || seconds < 0;
    seconds = seconds.abs();
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    final body = minutes < 60
        ? '${minutes}m ${rest.toString().padLeft(2, '0')}s'
        : durationLabel(minutes);
    final color = overdue
        ? c(LamalivaColors.danger)
        : widget.style?.color ?? c(LamalivaColors.ink);
    return Text(
      '${widget.prefix}$body',
      style: (widget.style ?? T.numeral).copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet chrome
// ---------------------------------------------------------------------------

/// A dialog on a wide window, a bottom sheet on a phone: the same card either
/// way, so the desk learns one surface.
Future<T?> _present<T>(
  BuildContext context,
  Widget Function(bool wide) builder,
) {
  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(LamalivaSpace.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Material(color: Colors.white, child: builder(true)),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: builder(false),
      ),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.wide, required this.children});

  final bool wide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        LamalivaSpace.lg,
        wide ? LamalivaSpace.lg : LamalivaSpace.sm,
        LamalivaSpace.lg,
        LamalivaSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!wide)
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: LamalivaSpace.md),
                decoration: BoxDecoration(
                  color: c(LamalivaColors.line),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: T.micro.copyWith(
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: c(LamalivaColors.orangeMid),
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: T.screenTitle.copyWith(fontSize: 26)),
              const SizedBox(height: 4),
              Text(subtitle, style: T.bodyMuted),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    this.tone = LamalivaColors.danger,
    this.icon = Icons.error_outline,
  });

  final String message;
  final ColorValue tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LamalivaSpace.sm),
      decoration: BoxDecoration(
        color: c(tone).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(LamalivaShape.card),
        border: Border.all(color: c(tone).withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c(tone)),
          const SizedBox(width: LamalivaSpace.xs),
          Expanded(
            child: Text(
              message,
              style: T.bodyMuted.copyWith(color: c(tone), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LamalivaSpace.xs),
      child: Text(
        label.toUpperCase(),
        style: T.micro.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: c(LamalivaColors.inkMuted),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.tone,
  });

  final String label;
  final String value;
  final bool emphasise;
  final ColorValue? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasise
                  ? T.body.copyWith(fontWeight: FontWeight.w600)
                  : T.bodyMuted,
            ),
          ),
          Text(
            value,
            style: (emphasise ? T.numeral.copyWith(fontSize: 15) : T.numeral)
                .copyWith(
                  fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                  color: tone == null ? null : c(tone!),
                ),
          ),
        ],
      ),
    );
  }
}

class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const options = <(String, String)>[
    ('cash', 'Cash'),
    ('mobile_money', 'Mobile money'),
    ('card', 'Card'),
    ('transfer', 'Transfer'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LamalivaSpace.xs,
      runSpacing: LamalivaSpace.xs,
      children: [
        for (final (key, label) in options)
          GestureDetector(
            onTap: () => onChanged(key),
            child: AnimatedContainer(
              duration: LamalivaMotion.quick,
              padding: const EdgeInsets.symmetric(
                horizontal: LamalivaSpace.sm,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: value == key
                    ? c(LamalivaColors.navy800)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(LamalivaShape.input),
                border: Border.all(
                  color: value == key
                      ? c(LamalivaColors.navy800)
                      : c(LamalivaColors.line),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: LamalivaType.uiFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: value == key
                      ? Colors.white
                      : c(LamalivaColors.navy800),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The money keyboard: no characters, at most two decimals.
TextInputType get _moneyKeyboard =>
    const TextInputType.numberWithOptions(decimal: true);

// ---------------------------------------------------------------------------
// Detail sheet: the stay, its money, its extension and every action.
// ---------------------------------------------------------------------------

/// Opens the stay sheet. Returns `true` when anything changed on the server, so
/// the caller can refresh its list.
Future<void> showStaySheet(
  BuildContext context, {
  required LamalivaApi api,
  required Map<String, dynamic> stay,
  VoidCallback? onChanged,
}) {
  return _present<void>(
    context,
    (wide) => _StayDetailSheet(
      api: api,
      stay: stay,
      wide: wide,
      onChanged: onChanged,
    ),
  );
}

class _StayDetailSheet extends StatefulWidget {
  const _StayDetailSheet({
    required this.api,
    required this.stay,
    required this.wide,
    this.onChanged,
  });

  final LamalivaApi api;
  final Map<String, dynamic> stay;
  final bool wide;
  final VoidCallback? onChanged;

  @override
  State<_StayDetailSheet> createState() => _StayDetailSheetState();
}

class _StayDetailSheetState extends State<_StayDetailSheet> {
  late Map<String, dynamic> _stay = widget.stay;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _clock => _map(_stay['clock']);
  Map<String, dynamic> get _money => _map(_stay['money']);
  Map<String, dynamic> get _guest => _map(_stay['guest']);
  Map<String, dynamic> get _room => _map(_stay['room']);
  Map<String, dynamic> get _extension => _map(_stay['extension']);
  Map<String, dynamic> get _reservation => _map(_stay['reservation']);

  void _apply(Map<String, dynamic> stay) {
    setState(() {
      _stay = stay;
      _busy = false;
      _error = null;
    });
    widget.onChanged?.call();
  }

  void _fail(Object error) {
    setState(() {
      _busy = false;
      _error = error.toString();
    });
  }

  /// A meal or a drink taken by the guest: recorded against the room bill.
  Future<void> _addCharge() async {
    final draft = await _present<_ChargeDraft>(
      context,
      (wide) => _ChargeForm(wide: wide, stay: _stay),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.addStayCharge(
        _idValue,
        category: draft.category,
        description: draft.description,
        quantity: draft.quantity,
        unitPrice: draft.unitPrice,
      );
      _apply(_map(res));
      _toast(
        '${draft.description} added to room ${_room['number'] ?? ''}. '
        'It is now on the bill.',
      );
    } on ApiException catch (error) {
      _fail(error.message);
    }
  }

  Future<void> _addPayment() async {
    final draft = await _present<_PaymentDraft>(
      context,
      (wide) => _PaymentForm(
        wide: wide,
        stay: _stay,
        balance: (_money['balance'] as num?)?.toDouble() ?? 0,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.addPayment(
        _idValue,
        amount: draft.amount,
        method: draft.method,
        kind: draft.kind,
        reference: draft.reference,
      );
      _apply(_map(res['stay']));
      _toast(
        draft.kind == 'refund'
            ? 'Refund recorded against ${_guest['display_name'] ?? 'the guest'}.'
            : 'Payment recorded.',
      );
    } on ApiException catch (error) {
      if (error.offline) {
        await _holdPayment(draft);
        return;
      }
      _fail(error.message);
    }
  }

  /// The server took no payment, but the desk did. Keep the money safe, under
  /// the passkey, and replay it the moment the server returns.
  Future<void> _holdPayment(_PaymentDraft draft) async {
    final reference =
        (draft.reference != null && draft.reference!.trim().isNotEmpty)
        ? draft.reference!.trim()
        : heldPaymentReference();
    final held = await holdOfflineAction(
      context,
      api: widget.api,
      path: '/stays/$_idValue/payments',
      label:
          '${draft.kind == 'refund' ? 'Refund' : 'Payment'} '
          '${formatMoney(draft.amount)} · '
          'Room ${_room['number'] ?? '—'}',
      body: {
        'amount': draft.amount,
        'kind': draft.kind,
        'method': draft.method,
        'reference': reference,
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (held) {
      _toast(
        '${draft.kind == 'refund' ? 'Refund' : 'Payment'} held on this device. '
        'A manager syncs it when the server returns.',
      );
    }
  }

  Future<void> _extend() async {
    final draft = await _present<_ExtensionDraft>(
      context,
      (wide) => _ExtensionForm(
        wide: wide,
        stay: _stay,
        canApprove: widget.api.canApprove,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.requestExtension(
        _idValue,
        minutes: draft.hours * 60,
        note: draft.note,
        autoApprove: draft.autoApprove,
      );
      final stay = _map(res['data']?['stay'] ?? res['stay']);
      if (stay.isNotEmpty) _apply(stay);
      final approval = _map(res['meta'])['approval_required'] == true;
      _toast(
        approval
            ? 'Extension requested — a manager must approve it.'
            : 'Stay extended to ${clockTime(_clock['expected_checkout_local'])}.',
      );
    } on ApiException catch (error) {
      if (error.offline) {
        final held = await holdOfflineAction(
          context,
          api: widget.api,
          path: '/stays/$_idValue/extensions',
          label: 'Extension ${draft.hours}h · Room ${_room['number'] ?? '—'}',
          body: {
            'minutes': draft.hours * 60,
            'auto_approve': draft.autoApprove,
            if (draft.note != null && draft.note!.trim().isNotEmpty)
              'note': draft.note!.trim(),
          },
        );
        if (!mounted) return;
        setState(() => _busy = false);
        if (held) _toast('Extension held on this device for sync.');
        return;
      }
      _fail(error.message);
    }
  }

  Future<void> _decideExtension(
    int extensionId, {
    required bool approve,
  }) async {
    setState(() => _busy = true);
    try {
      final stay = approve
          ? await widget.api.approveExtension(_idValue, extensionId)
          : await widget.api.rejectExtension(_idValue, extensionId);
      _apply(stay);
      _toast(approve ? 'Extension approved.' : 'Extension declined.');
    } on ApiException catch (error) {
      if (error.offline) {
        final held = await holdOfflineAction(
          context,
          api: widget.api,
          path:
              '/stays/$_idValue/extensions/$extensionId/'
              '${approve ? 'approve' : 'reject'}',
          label:
              '${approve ? 'Approve' : 'Decline'} extension · '
              'Room ${_room['number'] ?? '—'}',
          body: const {},
        );
        if (!mounted) return;
        setState(() => _busy = false);
        if (held) {
          _toast(
            '${approve ? 'Approval' : 'Decision'} held on this device for sync.',
          );
        }
        return;
      }
      _fail(error.message);
    }
  }

  Future<void> _checkout() async {
    final draft = await _present<_CheckoutDraft>(
      context,
      (wide) => _CheckoutForm(
        wide: wide,
        stay: _stay,
        canApprove: widget.api.canApprove,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await widget.api.checkoutStay(
        _idValue,
        payments: draft.payments,
        authoriseOutstanding: draft.authoriseOutstanding,
        note: draft.note,
      );
      if (!mounted) return;
      final receipt = _map(res['receipt']);
      setState(() {
        _busy = false;
      });
      widget.onChanged?.call();
      // A checkout hands the guest paper: print the sealed invoice now, and
      // keep the dialog as the fallback when no printer is attached.
      String? printedTo;
      String? printError;
      try {
        final bytes = await InvoicePdf.build(receipt);
        printedTo = await InvoicePrinter.print(
          bytes,
          jobName: 'Invoice ${receipt['receipt_reference'] ?? ''}',
          fallbackToDialog: false,
        );
      } catch (_) {
        printError = 'The invoice is ready but could not be sent to a printer.';
      }
      if (!mounted) return;
      await _present<void>(
        context,
        (wide) => _ReceiptSheet(
          wide: wide,
          receipt: receipt,
          printedTo: printedTo,
          printError: printError,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (error.offline) {
        await _holdCheckout(draft);
        return;
      }
      _fail(error.message);
    }
  }

  /// A checkout taken at a desk with no server. The guest still leaves with an
  /// invoice, clearly marked provisional, and the sealed receipt follows once
  /// a manager syncs.
  Future<void> _holdCheckout(_CheckoutDraft draft) async {
    final held = await holdOfflineAction(
      context,
      api: widget.api,
      path: '/stays/$_idValue/checkout',
      label: 'Checkout · ${_guest['display_name'] ?? 'Guest'}',
      body: {
        'payments': draft.payments,
        'authorise_outstanding': draft.authoriseOutstanding,
        if (draft.note != null && draft.note!.trim().isNotEmpty)
          'note': draft.note!.trim(),
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!held) return;
    widget.onChanged?.call();
    final receipt = _provisionalReceipt(
      draft.payments,
      draft.authoriseOutstanding,
    );
    String? printedTo;
    String? printError;
    try {
      final bytes = await InvoicePdf.build(receipt, provisional: true);
      printedTo = await InvoicePrinter.print(
        bytes,
        jobName: 'Provisional invoice ${receipt['receipt_reference']}',
        fallbackToDialog: false,
      );
    } catch (_) {
      printError = 'The provisional invoice could not be sent to a printer.';
    }
    if (!mounted) return;
    await _present<void>(
      context,
      (wide) => _ReceiptSheet(
        wide: wide,
        receipt: receipt,
        printedTo: printedTo,
        printError: printError,
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Map<String, dynamic> _provisionalReceipt(
    List<Map<String, dynamic>> payments,
    bool authorised,
  ) {
    final money = Map<String, dynamic>.from(_money);
    final total = (money['total_charges'] as num?)?.toDouble() ?? 0;
    var paid = (money['net_paid'] as num?)?.toDouble() ?? 0;
    final rows = <Map<String, dynamic>>[];
    for (final raw in payments) {
      final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
      final refund = '${raw['kind']}' == 'refund';
      paid += refund ? -amount : amount;
      rows.add({
        'kind': refund ? 'refund' : 'payment',
        'amount': amount,
        'method': raw['method'],
        'reference': raw['reference'],
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    final balance = total - paid;
    money['net_paid'] = paid;
    money['balance'] = balance < 0 ? 0 : balance;
    return {
      'receipt_reference': 'PR-${_reservation['reference'] ?? _idValue}',
      'hotel': {
        'name': 'LA-MALIVA VISTA HOTEL',
        'address': 'Buea, South-West Region, Cameroon',
        'phone': '+237 6 77 00 00 00',
        'currency': 'XAF',
      },
      'stay': {
        'reference': _reservation['reference'],
        'guest': _guest['display_name'],
        'room': _room['number'],
        'arrival': _reservation['arrival'],
        'departure': _reservation['departure'],
        'nights': _reservation['nights'],
        'checked_out_local': null,
      },
      'money': money,
      'payments': rows,
      'settled': balance <= 0.001,
      'outstanding_authorised_by': authorised ? 'held' : null,
      'issued_at': DateTime.now().toIso8601String(),
      'provisional': true,
      'offline': true,
    };
  }

  int get _idValue => int.tryParse('${_reservation['id'] ?? ''}') ?? 0;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = '${_clock['state'] ?? 'active'}';
    final overdue = _flag(_clock['is_overdue']);
    final remaining = (_clock['minutes_remaining'] as num?)?.toInt() ?? 0;
    final pending = _map(_extension['pending']);
    final history = (_extension['history'] as List?) ?? const [];
    final balance = (_money['balance'] as num?)?.toDouble() ?? 0;
    final checkedOut = state == 'checked_out';

    return _SheetFrame(
      wide: widget.wide,
      children: [
        _SheetHeader(
          eyebrow: 'Stay ${_reservation['reference'] ?? ''}',
          title: '${_guest['display_name'] ?? 'Guest'}',
          subtitle:
              'Room ${_room['number'] ?? '—'} · ${_reservation['nights'] ?? 1} night'
              '${(_reservation['nights'] as num?) == 1 ? '' : 's'} · '
              '${_reservation['status'] ?? state}',
        ),
        const SizedBox(height: LamalivaSpace.md),
        Container(
          padding: const EdgeInsets.all(LamalivaSpace.md),
          decoration: BoxDecoration(
            color: c(LamalivaColors.cream),
            borderRadius: BorderRadius.circular(LamalivaShape.card),
            border: Border.all(color: c(LamalivaColors.line)),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: stayStateColor(state),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: LamalivaSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stayStateLabel(state),
                      style: T.label.copyWith(
                        color: stayStateColor(state),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      checkedOut
                          ? 'Closed ${clockTime(_clock['checked_out_at'])}'
                          : 'Checkout ${clockTime(_clock['expected_checkout_local'])} · '
                                '${dayLabel(_clock['expected_checkout_local'])}',
                      style: T.micro,
                    ),
                  ],
                ),
              ),
              if (!checkedOut && _clock['minutes_remaining'] != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StayCountdown(
                      minutes: remaining,
                      overdue: overdue,
                      prefix: overdue ? '+' : '',
                      style: T.numeral.copyWith(fontSize: 18),
                    ),
                    Text(
                      overdue ? 'past checkout' : 'remaining',
                      style: T.micro,
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        _SectionLabel('Money'),
        _SummaryRow(
          label:
              'Room ${_map(_stay['pricing'])['type'] == 'hourly' ? 'hours' : 'charge'}',
          value: formatMoney(_money['room_charge']),
        ),
        if (((_money['extension_charges'] as num?) ?? 0) > 0)
          _SummaryRow(
            label: 'Approved extensions',
            value: formatMoney(_money['extension_charges']),
          ),
        if (((_money['extra_charges'] as num?) ?? 0) > 0)
          _SummaryRow(
            label: 'Meals and drinks',
            value: formatMoney(_money['extra_charges']),
          ),
        _SummaryRow(
          label: 'Total charges',
          value: formatMoney(_money['total_charges']),
        ),
        _SummaryRow(label: 'Paid', value: formatMoney(_money['net_paid'])),
        Divider(color: c(LamalivaColors.line), height: LamalivaSpace.md),
        _SummaryRow(
          label: balance > 0 ? 'Balance due' : 'Settled',
          value: balance > 0 ? formatMoney(balance) : 'Paid in full',
          emphasise: true,
          tone: balance > 0 ? LamalivaColors.danger : LamalivaColors.success,
        ),
        const SizedBox(height: LamalivaSpace.md),
        _SectionLabel('Bought by this room'),
        if ((_stay['charges'] as List?)?.isEmpty ?? true)
          Text(
            'No breakfast, lunch, supper or drink has been added yet.',
            style: T.micro,
          )
        else
          for (final row in (_stay['charges'] as List))
            _ChargeLine(row: (row as Map).cast<String, dynamic>()),
        if (!checkedOut && _reservation['status'] == 'checked_in')
          Padding(
            padding: const EdgeInsets.only(top: LamalivaSpace.sm),
            child: GhostButton(
              label: 'Add breakfast, food or drink',
              icon: Icons.add,
              onPressed: _busy ? null : _addCharge,
            ),
          ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: LamalivaSpace.md),
          Container(
            padding: const EdgeInsets.all(LamalivaSpace.sm),
            decoration: BoxDecoration(
              color: c(LamalivaColors.warningSoft).withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(LamalivaShape.card),
              border: Border.all(
                color: c(LamalivaColors.warning).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Extension waiting for approval',
                  style: T.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c(LamalivaColors.warning),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '+${durationLabel((pending['minutes'] as num?)?.toInt() ?? 0)} · '
                  'new checkout ${clockTime(pending['new_checkout_local'])} · '
                  '${formatMoney(pending['additional_charge'])}',
                  style: T.micro.copyWith(color: c(LamalivaColors.inkMuted)),
                ),
                if (widget.api.canApprove) ...[
                  const SizedBox(height: LamalivaSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GhostButton(
                          label: 'Decline',
                          icon: Icons.close,
                          onPressed: _busy
                              ? null
                              : () => _decideExtension(
                                  int.tryParse('${pending['id']}') ?? 0,
                                  approve: false,
                                ),
                        ),
                      ),
                      const SizedBox(width: LamalivaSpace.xs),
                      Expanded(
                        child: GhostButton(
                          label: 'Approve',
                          icon: Icons.check,
                          onPressed: _busy
                              ? null
                              : () => _decideExtension(
                                  int.tryParse('${pending['id']}') ?? 0,
                                  approve: true,
                                ),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'A manager approves extensions.',
                      style: T.micro,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: LamalivaSpace.sm),
          _Notice(message: _error!),
        ],
        const SizedBox(height: LamalivaSpace.lg),
        if (!checkedOut) ...[
          PrimaryButton(
            label:
                'Check out  ·  ${formatMoney(balance > 0 ? balance : 0)} due',
            icon: Icons.logout,
            busy: _busy,
            onPressed: _busy ? null : _checkout,
          ),
          const SizedBox(height: LamalivaSpace.xs),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Add payment',
                  icon: Icons.payments_outlined,
                  onPressed: _busy ? null : _addPayment,
                ),
              ),
              const SizedBox(width: LamalivaSpace.xs),
              Expanded(
                child: GhostButton(
                  label: 'Extend stay',
                  icon: Icons.more_time,
                  onPressed: _busy ? null : _extend,
                ),
              ),
            ],
          ),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: LamalivaSpace.lg),
          _SectionLabel('Extension history · ${history.length}'),
          for (final raw in history.reversed.take(4))
            _HistoryLine(entry: _map(raw)),
        ],
      ],
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final status = '${entry['status'] ?? ''}';
    final tone = status == 'approved'
        ? LamalivaColors.success
        : status == 'pending'
        ? LamalivaColors.warning
        : LamalivaColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c(tone), shape: BoxShape.circle),
          ),
          const SizedBox(width: LamalivaSpace.xs),
          Expanded(
            child: Text(
              '+${durationLabel((entry['minutes'] as num?)?.toInt() ?? 0)} · '
              'to ${clockTime(entry['new_checkout_local'])}',
              style: T.bodyMuted,
            ),
          ),
          Text(
            '${formatMoney(entry['additional_charge'])}  ·  '
            '${StatusPill.labelFor(status)}',
            style: T.micro.copyWith(
              color: c(tone),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment
// ---------------------------------------------------------------------------

class _PaymentDraft {
  _PaymentDraft({
    required this.amount,
    required this.method,
    required this.kind,
    this.reference,
  });

  final double amount;
  final String method;
  final String kind;
  final String? reference;
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({
    required this.wide,
    required this.stay,
    required this.balance,
  });

  final bool wide;
  final Map<String, dynamic> stay;
  final double balance;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late final _amount = TextEditingController(
    text: widget.balance > 0 ? widget.balance.toStringAsFixed(0) : '',
  );
  final _reference = TextEditingController();
  String _method = 'cash';
  String _kind = 'payment';
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_amount.text.replaceAll(',', '.').trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    Navigator.of(context).pop(
      _PaymentDraft(
        amount: value,
        method: _method,
        kind: _kind,
        reference: _reference.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = _map(widget.stay['money']);
    final guest = _map(widget.stay['guest']);
    final room = _map(widget.stay['room']);
    return _SheetFrame(
      wide: widget.wide,
      children: [
        _SheetHeader(
          eyebrow: 'Room ${room['number'] ?? '—'}',
          title: 'Record a payment',
          subtitle:
              '${guest['display_name'] ?? 'Guest'} · '
              'balance ${formatMoney(money['balance'])}',
        ),
        const SizedBox(height: LamalivaSpace.md),
        Row(
          children: [
            Expanded(
              child: _KindChip(
                label: 'Payment',
                selected: _kind == 'payment',
                onTap: () => setState(() => _kind = 'payment'),
              ),
            ),
            const SizedBox(width: LamalivaSpace.xs),
            Expanded(
              child: _KindChip(
                label: 'Refund',
                selected: _kind == 'refund',
                onTap: () => setState(() => _kind = 'refund'),
              ),
            ),
          ],
        ),
        const SizedBox(height: LamalivaSpace.md),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: _moneyKeyboard,
          style: T.numeral.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Amount',
            suffixText: '${money['currency'] ?? 'XAF'}',
            errorText: _error,
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        _SectionLabel('Method'),
        _MethodPicker(
          value: _method,
          onChanged: (value) => setState(() => _method = value),
        ),
        const SizedBox(height: LamalivaSpace.md),
        TextField(
          controller: _reference,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Reference (optional)',
            hintText: 'MoMo ID, card slip…',
          ),
        ),
        const SizedBox(height: LamalivaSpace.lg),
        PrimaryButton(
          label: _kind == 'refund' ? 'Record refund' : 'Record payment',
          icon: Icons.check,
          onPressed: _submit,
        ),
        const SizedBox(height: LamalivaSpace.xs),
        Text(
          'Payments are append-only: a mistake is corrected with a refund, never edited.',
          style: T.micro,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: LamalivaMotion.quick,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c(LamalivaColors.creamDeep) : Colors.white,
          borderRadius: BorderRadius.circular(LamalivaShape.input),
          border: Border.all(
            color: selected
                ? c(LamalivaColors.navy600)
                : c(LamalivaColors.line),
          ),
        ),
        child: Text(
          label,
          style: T.body.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

class _ExtensionDraft {
  _ExtensionDraft({required this.hours, required this.autoApprove, this.note});

  final int hours;
  final bool autoApprove;
  final String? note;
}

class _ExtensionForm extends StatefulWidget {
  const _ExtensionForm({
    required this.wide,
    required this.stay,
    required this.canApprove,
  });

  final bool wide;
  final Map<String, dynamic> stay;
  final bool canApprove;

  @override
  State<_ExtensionForm> createState() => _ExtensionFormState();
}

class _ExtensionFormState extends State<_ExtensionForm> {
  late final _custom = TextEditingController();
  final _note = TextEditingController();
  int _hours = 1;
  bool _autoApprove = false;
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _rate {
    final pricing = _map(widget.stay['pricing']);
    final nightly = (pricing['rate_per_night'] as num?)?.toDouble() ?? 0;
    final percent = (pricing['hourly_rate_percent'] as num?)?.toInt() ?? 30;
    return nightly * percent / 100;
  }

  void _submit() {
    final custom = int.tryParse(_custom.text.trim());
    final hours = custom ?? _hours;
    if (hours <= 0) {
      setState(() => _error = 'Choose how long the guest is staying on.');
      return;
    }
    Navigator.of(context).pop(
      _ExtensionDraft(
        hours: hours,
        autoApprove: _autoApprove,
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clock = _map(widget.stay['clock']);
    final room = _map(widget.stay['room']);
    final guest = _map(widget.stay['guest']);
    return _SheetFrame(
      wide: widget.wide,
      children: [
        _SheetHeader(
          eyebrow:
              'Room ${room['number'] ?? '—'} · '
              'checkout ${clockTime(clock['expected_checkout_local'])}',
          title: 'Extend the stay',
          subtitle:
              '${guest['display_name'] ?? 'Guest'} keeps the room for '
              '${durationLabel(_hours * 60)} more.',
        ),
        const SizedBox(height: LamalivaSpace.md),
        _SectionLabel('Additional time'),
        Wrap(
          spacing: LamalivaSpace.xs,
          runSpacing: LamalivaSpace.xs,
          children: [
            for (final hours in const [1, 2, 3, 6])
              _KindChip(
                label: hours == 1 ? '1 hour' : '$hours hours',
                selected: _custom.text.trim().isEmpty && _hours == hours,
                onTap: () => setState(() {
                  _hours = hours;
                  _custom.clear();
                  _error = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: LamalivaSpace.sm),
        TextField(
          controller: _custom,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Or a custom number of hours',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: LamalivaSpace.md),
        Container(
          padding: const EdgeInsets.all(LamalivaSpace.sm),
          decoration: BoxDecoration(
            color: c(LamalivaColors.cream),
            borderRadius: BorderRadius.circular(LamalivaShape.card),
          ),
          child: Row(
            children: [
              Expanded(child: Text('Estimated charge', style: T.bodyMuted)),
              Text(
                '${formatMoney(_rate * _hours)}  ·  ${durationLabel(_hours * 60)}',
                style: T.numeral.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        TextField(
          controller: _note,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Flight delayed, wedding party…',
          ),
        ),
        if (widget.canApprove) ...[
          const SizedBox(height: LamalivaSpace.sm),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _autoApprove,
            onChanged: (value) => setState(() => _autoApprove = value),
            title: Text(
              'Approve it now',
              style: T.body.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Moves the checkout time immediately, with your name on it.',
              style: T.micro,
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: LamalivaSpace.sm),
            child: _Notice(
              message:
                  'A manager approves extensions. The current checkout time stands until then.',
              tone: LamalivaColors.warning,
              icon: Icons.schedule,
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: LamalivaSpace.sm),
          _Notice(message: _error!),
        ],
        const SizedBox(height: LamalivaSpace.md),
        PrimaryButton(
          label: widget.canApprove && _autoApprove
              ? 'Extend and approve'
              : 'Request extension',
          icon: Icons.more_time,
          onPressed: _submit,
        ),
        const SizedBox(height: LamalivaSpace.xs),
        Text(
          'The original stay stays on record; an approval adds a new checkout '
          'time and its own charge.',
          style: T.micro,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Checkout
// ---------------------------------------------------------------------------

class _CheckoutDraft {
  _CheckoutDraft({
    required this.payments,
    required this.authoriseOutstanding,
    this.note,
  });

  final List<Map<String, dynamic>> payments;
  final bool authoriseOutstanding;
  final String? note;
}

class _CheckoutForm extends StatefulWidget {
  const _CheckoutForm({
    required this.wide,
    required this.stay,
    required this.canApprove,
  });

  final bool wide;
  final Map<String, dynamic> stay;
  final bool canApprove;

  @override
  State<_CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends State<_CheckoutForm> {
  late final Map<String, dynamic> _money = _map(widget.stay['money']);
  late final double _balance = (_money['balance'] as num?)?.toDouble() ?? 0;
  late final _amount = TextEditingController(
    text: _balance > 0 ? _balance.toStringAsFixed(0) : '',
  );
  final _note = TextEditingController();
  String _method = 'cash';
  bool _authorise = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = double.tryParse(_amount.text.replaceAll(',', '.').trim());
    final payments = <Map<String, dynamic>>[];
    if (_balance > 0) {
      if (typed == null || typed < 0) {
        setState(() => _error = 'Enter the amount being settled.');
        return;
      }
      if (typed > 0) {
        payments.add({'amount': typed, 'method': _method, 'kind': 'payment'});
      }
      final settled = typed >= _balance - 0.005;
      if (!settled && !_authorise) {
        setState(
          () => _error = widget.canApprove
              ? 'Collect the balance, or authorise leaving it on the account.'
              : 'The balance must be collected before checkout.',
        );
        return;
      }
      if (!settled && !widget.canApprove) {
        setState(
          () => _error = 'Only a manager can authorise an outstanding balance.',
        );
        return;
      }
    }
    Navigator.of(context).pop(
      _CheckoutDraft(
        payments: payments,
        authoriseOutstanding: _authorise && _balance > 0,
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = _money;
    final guest = _map(widget.stay['guest']);
    final room = _map(widget.stay['room']);
    final clock = _map(widget.stay['clock']);
    final overdue = _flag(clock['is_overdue']);
    final remaining = (clock['minutes_remaining'] as num?)?.toInt() ?? 0;
    return _SheetFrame(
      wide: widget.wide,
      children: [
        _SheetHeader(
          eyebrow: 'Room ${room['number'] ?? '—'} · checkout',
          title: 'Close this stay',
          subtitle:
              '${guest['display_name'] ?? 'Guest'} · '
              '${overdue ? '${durationLabel((clock['overdue_minutes'] as num?)?.toInt() ?? 0)} past the agreed time' : '${durationLabel(remaining)} left on the clock'}',
        ),
        const SizedBox(height: LamalivaSpace.md),
        Container(
          padding: const EdgeInsets.all(LamalivaSpace.md),
          decoration: BoxDecoration(
            color: c(LamalivaColors.cream),
            borderRadius: BorderRadius.circular(LamalivaShape.card),
            border: Border.all(color: c(LamalivaColors.line)),
          ),
          child: Column(
            children: [
              _SummaryRow(
                label: 'Room charge',
                value: formatMoney(money['room_charge']),
              ),
              if (((money['extension_charges'] as num?) ?? 0) > 0)
                _SummaryRow(
                  label: 'Extensions',
                  value: formatMoney(money['extension_charges']),
                ),
              Divider(color: c(LamalivaColors.line), height: LamalivaSpace.md),
              _SummaryRow(
                label: 'Total',
                value: formatMoney(money['total_charges']),
                emphasise: true,
              ),
              _SummaryRow(
                label: 'Already paid',
                value: formatMoney(money['net_paid']),
              ),
              _SummaryRow(
                label: 'Balance',
                value: formatMoney(_balance),
                emphasise: true,
                tone: _balance > 0
                    ? LamalivaColors.danger
                    : LamalivaColors.success,
              ),
            ],
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        if (_balance > 0) ...[
          _SectionLabel('Final payment'),
          TextField(
            controller: _amount,
            keyboardType: _moneyKeyboard,
            style: T.numeral.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: 'Amount collected',
              suffixText: '${money['currency'] ?? 'XAF'}',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: LamalivaSpace.sm),
          _MethodPicker(
            value: _method,
            onChanged: (value) => setState(() => _method = value),
          ),
          const SizedBox(height: LamalivaSpace.sm),
          if (widget.canApprove)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _authorise,
              onChanged: (value) => setState(() {
                _authorise = value;
                _error = null;
              }),
              title: Text(
                'Authorise the remaining balance',
                style: T.body.copyWith(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'The debt stays on record against your name and blocks nothing.',
                style: T.micro,
              ),
            )
          else
            _Notice(
              message:
                  'The balance has to be collected here. A manager can authorise '
                  'checkout with a balance still owed.',
              tone: LamalivaColors.warning,
              icon: Icons.account_balance_wallet_outlined,
            ),
        ] else
          _Notice(
            message: 'Paid in full. Nothing more to collect.',
            tone: LamalivaColors.success,
            icon: Icons.check_circle_outline,
          ),
        const SizedBox(height: LamalivaSpace.md),
        TextField(
          controller: _note,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Handover note (optional)',
            hintText: 'Left a jacket, room needs deep clean…',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: LamalivaSpace.sm),
          _Notice(message: _error!),
        ],
        const SizedBox(height: LamalivaSpace.md),
        PrimaryButton(
          label: 'Check out and issue receipt',
          icon: Icons.receipt_long,
          onPressed: _submit,
        ),
        const SizedBox(height: LamalivaSpace.xs),
        Text(
          'The room goes to housekeeping; the stay and its payments stay on record.',
          style: T.micro,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt
// ---------------------------------------------------------------------------

class _ReceiptSheet extends StatefulWidget {
  const _ReceiptSheet({
    required this.wide,
    required this.receipt,
    this.printedTo,
    this.printError,
  });

  final bool wide;
  final Map<String, dynamic> receipt;
  final String? printedTo;
  final String? printError;

  @override
  State<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<_ReceiptSheet> {
  bool _printing = false;
  late String? _printedTo = widget.printedTo;

  bool get _provisional =>
      widget.receipt['provisional'] == true ||
      widget.receipt['offline'] == true;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final bytes = await InvoicePdf.build(
        widget.receipt,
        provisional: _provisional,
      );
      final printer = await InvoicePrinter.print(
        bytes,
        jobName: 'Invoice ${widget.receipt['receipt_reference'] ?? ''}',
      );
      if (!mounted) return;
      setState(() {
        _printing = false;
        _printedTo = printer ?? 'the system print dialog';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _printing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not print the invoice. Check the printer and try again.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final hotel = _map(receipt['hotel']);
    final stay = _map(receipt['stay']);
    final money = _map(receipt['money']);
    final payments = (receipt['payments'] as List?) ?? const [];
    final authorised = receipt['outstanding_authorised_by'] != null;
    final balance = (money['balance'] as num?)?.toDouble() ?? 0;
    return _SheetFrame(
      wide: widget.wide,
      children: [
        _SheetHeader(
          eyebrow: '${receipt['receipt_reference'] ?? 'Receipt'}',
          title: _provisional ? 'Checked out · held' : 'Checked out',
          subtitle:
              '${hotel['name'] ?? 'La Maliva Vista Hotel'} · '
              '${stay['guest'] ?? 'Guest'} · Room ${stay['room'] ?? '—'}',
        ),
        const SizedBox(height: LamalivaSpace.md),
        Container(
          padding: const EdgeInsets.all(LamalivaSpace.md),
          decoration: BoxDecoration(
            color: c(LamalivaColors.cream),
            borderRadius: BorderRadius.circular(LamalivaShape.card),
            border: Border.all(color: c(LamalivaColors.line)),
          ),
          child: Column(
            children: [
              _SummaryRow(
                label: 'Stay',
                value:
                    '${dayLabel(stay['arrival'])} → ${dayLabel(stay['departure'])}',
              ),
              _SummaryRow(label: 'Nights', value: '${stay['nights'] ?? '—'}'),
              Divider(color: c(LamalivaColors.line), height: LamalivaSpace.md),
              _SummaryRow(
                label: 'Room charge',
                value: formatMoney(money['room_charge']),
              ),
              if (((money['extension_charges'] as num?) ?? 0) > 0)
                _SummaryRow(
                  label: 'Extensions',
                  value: formatMoney(money['extension_charges']),
                ),
              _SummaryRow(
                label: 'Total',
                value: formatMoney(money['total_charges']),
              ),
              _SummaryRow(label: 'Paid', value: formatMoney(money['net_paid'])),
              if (((money['refunded'] as num?) ?? 0) > 0)
                _SummaryRow(
                  label: 'Refunded',
                  value: formatMoney(money['refunded']),
                ),
              Divider(color: c(LamalivaColors.line), height: LamalivaSpace.md),
              _SummaryRow(
                label: balance > 0 ? 'Balance outstanding' : 'Settled',
                value: balance > 0 ? formatMoney(balance) : 'Paid in full',
                emphasise: true,
                tone: balance > 0
                    ? LamalivaColors.danger
                    : LamalivaColors.success,
              ),
            ],
          ),
        ),
        if (payments.isNotEmpty) ...[
          const SizedBox(height: LamalivaSpace.md),
          _SectionLabel('Payments'),
          for (final raw in payments)
            _SummaryRow(
              label:
                  '${_methodLabel('${_map(raw)['method']}')} · '
                  '${clockTime(_map(raw)['created_at'])}',
              value: formatMoney(_map(raw)['amount']),
            ),
        ],
        const SizedBox(height: LamalivaSpace.md),
        // ------- The official seal -------
        Container(
          padding: const EdgeInsets.all(LamalivaSpace.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(LamalivaShape.card),
            border: Border.all(color: c(LamalivaColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InvoiceStamp(
                settled: receipt['settled'] == true || balance <= 0.001,
                provisional: _provisional,
                authorised: authorised,
                reference: '${receipt['receipt_reference'] ?? '—'}',
                issuedOn: invoiceDateLabel(receipt['issued_at']),
                size: widget.wide ? 128 : 104,
              ),
              const SizedBox(width: LamalivaSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _provisional ? 'PROVISIONAL INVOICE' : 'OFFICIAL STAMP',
                      style: T.micro.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: _provisional
                            ? c(LamalivaColors.orangeMid)
                            : c(LamalivaColors.inkMuted),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _provisional
                          ? 'The seal is pressed on the printed invoice, but '
                                'stays provisional until a manager syncs this '
                                'checkout to the hotel server.'
                          : 'The guest\'s A4 invoice carries this same '
                                'seal, with every charge and payment, ready '
                                'to print for the front desk file.',
                      style: T.bodyMuted.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LamalivaSpace.md),
        _Notice(
          message: _printedTo != null
              ? 'Invoice sent to $_printedTo.'
              : widget.printError ??
                    'No printer detected yet — print the invoice to choose one.',
          tone: _printedTo != null
              ? LamalivaColors.success
              : widget.printError != null
              ? LamalivaColors.warning
              : LamalivaColors.info,
          icon: _printedTo != null
              ? Icons.print_outlined
              : Icons.print_disabled_outlined,
        ),
        const SizedBox(height: LamalivaSpace.md),
        _Notice(
          message: authorised && balance > 0
              ? 'Room ${stay['room'] ?? '—'} is with housekeeping. '
                    '${formatMoney(balance)} remains authorised on the account.'
              : 'Room ${stay['room'] ?? '—'} is with housekeeping. '
                    'Issued ${clockTime(receipt['issued_at'])}.',
          tone: authorised ? LamalivaColors.warning : LamalivaColors.success,
          icon: Icons.cleaning_services_outlined,
        ),
        const SizedBox(height: LamalivaSpace.lg),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: _printing
                    ? 'Preparing…'
                    : _printedTo == null
                    ? 'Print invoice'
                    : 'Print again',
                icon: Icons.print_outlined,
                onPressed: _printing ? null : _print,
              ),
            ),
            const SizedBox(width: LamalivaSpace.sm),
            Expanded(
              child: PrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard: every stay holding a room, with its live countdown.
// ---------------------------------------------------------------------------

/// The occupancy monitor: what the server says the house holds right now, and
/// how long each stay has left. Countdowns tick locally from the server's
/// number, so a wrong device clock cannot invent or hide an overdue stay.
class StaysMonitorPanel extends StatelessWidget {
  const StaysMonitorPanel({
    super.key,
    required this.api,
    required this.monitor,
    this.onChanged,
  });

  final LamalivaApi api;
  final Map<String, dynamic> monitor;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final counts = _map(monitor['counts']);
    final stays = (monitor['stays'] as List?) ?? const [];
    final policy = _map(monitor['policy']);

    int count(String key) => (counts[key] as num?)?.toInt() ?? 0;

    if (stays.isEmpty) {
      return const Panel(
        title: 'Stays in the house',
        child: EmptyPanel(
          title: 'No room is held',
          body: 'A stay appears here the moment the desk checks a guest in. ',
          icon: Icons.hotel_outlined,
        ),
      );
    }

    return Panel(
      title: 'Stays in the house',
      trailing: Reference('${stays.length}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: LamalivaSpace.md,
            runSpacing: LamalivaSpace.xs,
            children: [
              _MonitorCount(
                label: 'In house',
                value: '${count('in_house')}',
                tone: LamalivaColors.ink,
              ),
              if (count('overdue') > 0)
                _MonitorCount(
                  label: 'Overdue',
                  value: '${count('overdue')}',
                  tone: LamalivaColors.danger,
                ),
              if (count('due') > 0)
                _MonitorCount(
                  label: 'Due now',
                  value: '${count('due')}',
                  tone: LamalivaColors.warning,
                ),
              _MonitorCount(
                label: 'Due today',
                value: '${count('due_today')}',
                tone: LamalivaColors.inkMuted,
              ),
              if (count('extension_pending') > 0)
                _MonitorCount(
                  label: 'Extensions',
                  value: '${count('extension_pending')}',
                  tone: LamalivaColors.warning,
                ),
              if (count('outstanding_balance') > 0)
                _MonitorCount(
                  label: 'Still owed',
                  value: formatMoney(count('outstanding_balance')),
                  tone: LamalivaColors.danger,
                ),
            ],
          ),
          const SizedBox(height: LamalivaSpace.sm),
          Divider(color: c(LamalivaColors.line), height: 1),
          for (var i = 0; i < stays.length; i++) ...[
            if (i > 0) Divider(color: c(LamalivaColors.line), height: 1),
            Reveal(
              delay: Duration(milliseconds: (i * 30).clamp(0, 240)),
              offset: 6,
              child: _StayBoardRow(
                api: api,
                stay: _map(stays[i]),
                onChanged: onChanged,
              ),
            ),
          ],
          if (policy['checkout_time'] != null)
            Padding(
              padding: const EdgeInsets.only(top: LamalivaSpace.sm),
              child: Text(
                'Hotel time · checkout ${policy['checkout_time']} · '
                '${policy['grace_minutes'] ?? 0} min grace · '
                '${policy['timezone'] ?? 'Africa/Douala'}',
                style: T.micro,
              ),
            ),
        ],
      ),
    );
  }
}

class _MonitorCount extends StatelessWidget {
  const _MonitorCount({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final ColorValue tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: T.numeral.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: c(tone),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: T.micro),
      ],
    );
  }
}

class _StayBoardRow extends StatelessWidget {
  const _StayBoardRow({required this.api, required this.stay, this.onChanged});

  final LamalivaApi api;
  final Map<String, dynamic> stay;
  final VoidCallback? onChanged;
  Future<void> _open(BuildContext context) async {
    await showStaySheet(context, api: api, stay: stay, onChanged: onChanged);
  }

  @override
  Widget build(BuildContext context) {
    final clock = _map(stay['clock']);
    final money = _map(stay['money']);
    final guest = _map(stay['guest']);
    final room = _map(stay['room']);
    final reservation = _map(stay['reservation']);
    final pending = _map(_map(stay['extension'])['pending']);
    final state = '${clock['state'] ?? 'active'}';
    final overdue = _flag(clock['is_overdue']);
    final due = state == 'checkout_due' || state == 'checkout_approaching';
    final balance = (money['balance'] as num?)?.toDouble() ?? 0;
    final remaining = (clock['minutes_remaining'] as num?)?.toInt() ?? 0;
    final tone = overdue
        ? LamalivaColors.danger
        : due
        ? LamalivaColors.warning
        : LamalivaColors.info;

    return Semantics(
      button: true,
      label:
          'Room ${room['number']}, ${guest['display_name']}, ${stayStateLabel(state)}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(context),
          child: HoverRow(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LamalivaSpace.xs,
                vertical: LamalivaSpace.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c(tone).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(LamalivaShape.card),
                      border: Border.all(
                        color: c(tone).withValues(alpha: 0.28),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${room['number'] ?? '—'}',
                        style: T.numeral.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c(tone),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: LamalivaSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${guest['display_name'] ?? 'Guest'}',
                                style: T.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (pending.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: c(LamalivaColors.warningSoft),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'EXT',
                                  style: T.micro.copyWith(
                                    fontSize: 9.5,
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w700,
                                    color: c(LamalivaColors.warning),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Checkout ${clockTime(clock['expected_checkout_local'])}'
                          '  ·  ${reservation['nights'] ?? 1} night'
                          '${(reservation['nights'] as num?) == 1 ? '' : 's'}'
                          '${balance > 0 ? '  ·  ${formatMoney(balance)} due' : '  ·  paid'}',
                          style: T.micro,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: LamalivaSpace.xs),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StayCountdown(
                        minutes: remaining,
                        overdue: overdue,
                        prefix: overdue ? '+' : '',
                        style: T.numeral.copyWith(fontSize: 14.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        overdue
                            ? 'Overdue'
                            : due
                            ? stayStateLabel(state)
                            : 'on the clock',
                        style: T.micro.copyWith(
                          color: c(tone),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: c(LamalivaColors.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _methodLabel(String method) {
  switch (method) {
    case 'mobile_money':
      return 'Mobile money';
    case 'card':
      return 'Card';
    case 'transfer':
      return 'Transfer';
    case 'cash':
      return 'Cash';
    default:
      return StatusPill.labelFor(method);
  }
}

class _ChargeDraft {
  _ChargeDraft({
    required this.category,
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String category;
  final String description;
  final double quantity;
  final double unitPrice;
}

class _ChargeLine extends StatelessWidget {
  const _ChargeLine({required this.row});

  final Map<String, dynamic> row;

  static const _names = {
    'breakfast': 'Breakfast',
    'lunch': 'Lunch',
    'supper': 'Supper',
    'drink': 'Drink',
    'other': 'Other',
  };

  @override
  Widget build(BuildContext context) {
    final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_names[row['category']] ?? 'Item'} - ${row['description'] ?? ''}',
              style: T.bodyMuted,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              'x${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)}',
              style: T.micro,
            ),
          ),
          Text(formatMoney(row['total']), style: T.numeral),
        ],
      ),
    );
  }
}

/// Add a meal or drink to an in-house guest's bill.
class _ChargeForm extends StatefulWidget {
  const _ChargeForm({required this.wide, required this.stay});

  final bool wide;
  final Map<String, dynamic> stay;

  @override
  State<_ChargeForm> createState() => _ChargeFormState();
}

class _ChargeFormState extends State<_ChargeForm> {
  static const _choices = [
    ('breakfast', 'Breakfast', Icons.free_breakfast_outlined),
    ('lunch', 'Lunch', Icons.lunch_dining_outlined),
    ('supper', 'Supper', Icons.dinner_dining_outlined),
    ('drink', 'Drink', Icons.local_bar_outlined),
    ('other', 'Other', Icons.room_service_outlined),
  ];

  String _category = 'breakfast';
  final _what = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _what.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  double get _total =>
      (double.tryParse(_qty.text.trim()) ?? 0) *
      (double.tryParse(_price.text.trim()) ?? 0);

  void _submit() {
    final name = _what.text.trim();
    final qty = double.tryParse(_qty.text.trim());
    final price = double.tryParse(_price.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Write what was taken, for example Omelette.');
      return;
    }
    if (qty == null || qty <= 0) {
      setState(() => _error = 'How many? Give a number above zero.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Give the menu price for one.');
      return;
    }
    Navigator.of(context).pop(
      _ChargeDraft(
        category: _category,
        description: name,
        quantity: qty,
        unitPrice: price,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = '${_map(widget.stay['money'])['currency'] ?? 'XAF'}';
    return _SheetFrame(
      wide: widget.wide,
      children: [
        _SheetHeader(
          eyebrow: 'Room ${_map(widget.stay['room'])['number'] ?? ''}',
          title: 'Add room purchase',
          subtitle:
              'Breakfast, lunch, supper or a drink. It joins the bill and is '
              'collected at check-out.',
        ),
        const SizedBox(height: LamalivaSpace.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: LamalivaSpace.xs,
              runSpacing: LamalivaSpace.xs,
              children: [
                for (final choice in _choices)
                  ChoiceChip(
                    label: Text(choice.$2),
                    avatar: Icon(choice.$3, size: 15),
                    selected: _category == choice.$1,
                    onSelected: (_) => setState(() => _category = choice.$1),
                  ),
              ],
            ),
            const SizedBox(height: LamalivaSpace.sm),
            TextField(
              controller: _what,
              decoration: const InputDecoration(
                labelText: 'What was taken',
                hintText: 'Omelette, Malta, grilled fish',
              ),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: _moneyKeyboard,
                    decoration: const InputDecoration(labelText: 'How many'),
                  ),
                ),
                const SizedBox(width: LamalivaSpace.sm),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _price,
                    keyboardType: _moneyKeyboard,
                    decoration: InputDecoration(
                      labelText: 'Price for one',
                      suffixText: currency,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LamalivaSpace.sm),
            Text(
              'Total to add: ${formatMoney(_total)}',
              style: T.numeral.copyWith(fontWeight: FontWeight.w700),
            ),
            if (_error != null) ...[
              const SizedBox(height: LamalivaSpace.xs),
              Text(
                _error ?? '',
                style: T.micro.copyWith(color: c(LamalivaColors.danger)),
              ),
            ],
            const SizedBox(height: LamalivaSpace.md),
            PrimaryButton(label: 'Add to room bill', onPressed: _submit),
          ],
        ),
      ],
    );
  }
}
