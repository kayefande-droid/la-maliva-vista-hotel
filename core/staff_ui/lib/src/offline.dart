import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as aes;
import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'theme.dart';

/// Whether the hotel server answered the last request.
///
/// The app never silently decides it is offline: the first transport failure
/// flips this flag, the banner explains what happened, and a background probe
/// flips it back the moment the server returns.
class NetworkStatus {
  NetworkStatus._();

  static final ValueNotifier<bool> reachable = ValueNotifier<bool>(true);
}

/// The last good answer from the server, kept so a desk with no signal can
/// still see the house instead of an error page.
class OfflineCache {
  OfflineCache._();

  static String _key(String name) => 'lamaliva.cache.$name';

  static Future<void> put(String name, Object? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(name), jsonEncode(value));
    } catch (_) {
      // A failed cache write must never break a live request.
    }
  }

  static Future<Object?> read(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key(name));
      if (text == null || text.isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}

/// One write made while the server was unreachable. It is replayed in order,
/// through the same endpoints the online app uses.
class HeldAction {
  const HeldAction({
    required this.id,
    required this.label,
    required this.path,
    required this.body,
    required this.at,
  });

  final String id;
  final String label;
  final String path;
  final Map<String, dynamic> body;
  final DateTime at;

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'path': path,
    'body': body,
    'at': at.toIso8601String(),
  };

  static HeldAction fromMap(Map<String, dynamic> map) => HeldAction(
    id: '${map['id']}',
    label: '${map['label'] ?? 'Action'}',
    path: '${map['path']}',
    body: (map['body'] as Map?)?.cast<String, dynamic>() ?? const {},
    at: DateTime.tryParse('${map['at']}') ?? DateTime.now(),
  );
}

/// Held actions live encrypted on the device, under the admin passkey.
///
/// The queue is encrypted with a key derived from the passkey, so a lost or
/// stolen tablet does not expose guest names and money. It cannot be read or
/// replayed without that passkey, and the server verifies it again before a
/// single held action is accepted.
class OfflineVault {
  OfflineVault._();

  static const _blobKey = 'lamaliva.held.v1';
  static const _countKey = 'lamaliva.held.count';

  static String? _pass;
  static final ValueNotifier<int> pending = ValueNotifier<int>(0);

  static bool get unlocked => _pass != null;

  static aes.Key _derive(String pass) => aes.Key(
    Uint8List.fromList(
      sha256.convert(utf8.encode('lamaliva-vault|$pass')).bytes,
    ),
  );

  static aes.Encrypter _cipher(String pass) =>
      aes.Encrypter(aes.AES(_derive(pass), mode: aes.AESMode.cbc));

  static Future<bool> hasVault() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_blobKey) ?? '').isNotEmpty;
  }

  /// Re-reads the queue size for the banner, without unlocking it.
  static Future<void> loadCount() async {
    final prefs = await SharedPreferences.getInstance();
    pending.value = prefs.getInt(_countKey) ?? 0;
  }

  /// `null` means the passkey does not open this device's queue.
  static Future<List<HeldAction>?> _read(String pass) async {
    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getString(_blobKey);
    if (blob == null || blob.isEmpty) return const [];
    try {
      final raw = base64Decode(blob);
      if (raw.length < 18) return null;
      final iv = aes.IV(raw.sublist(0, 16));
      final text = _cipher(
        pass,
      ).decrypt(aes.Encrypted(raw.sublist(16)), iv: iv);
      final list = jsonDecode(text) as List;
      return [
        for (final item in list)
          HeldAction.fromMap((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  static Future<bool> unlock(String pass) async {
    final list = await _read(pass);
    if (list == null) return false;
    _pass = pass;
    pending.value = list.length;
    return true;
  }

  static Future<bool> verify(String pass) async => (await _read(pass)) != null;

  static Future<void> lock() async {
    _pass = null;
  }

  static Future<List<HeldAction>> actions() async {
    final pass = _pass;
    if (pass == null) return const [];
    return await _read(pass) ?? const [];
  }

  static Future<void> _write(List<HeldAction> list) async {
    final pass = _pass;
    if (pass == null) throw StateError('The held actions are locked.');
    final prefs = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      await prefs.remove(_blobKey);
    } else {
      final iv = aes.IV.fromSecureRandom(16);
      final encrypted = _cipher(
        pass,
      ).encrypt(jsonEncode([for (final item in list) item.toMap()]), iv: iv);
      await prefs.setString(
        _blobKey,
        base64Encode([...iv.bytes, ...encrypted.bytes]),
      );
    }
    await prefs.setInt(_countKey, list.length);
    pending.value = list.length;
  }

  static Future<void> hold(HeldAction action) async {
    final list = await actions();
    await _write([...list, action]);
  }

  static Future<void> remove(String id) async {
    final list = await actions();
    await _write(list.where((item) => item.id != id).toList());
  }

  static Future<void> clear() async {
    await _write(const []);
  }
}

/// Builds a stable id for a held action, so a retried tap never doubles it.
String heldActionId(String path) =>
    '${DateTime.now().microsecondsSinceEpoch}-${path.hashCode.abs()}';

/// A short reference the server uses to recognise a replayed payment.
String heldPaymentReference() {
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  return 'APP-${stamp.toUpperCase()}';
}

// ---------------------------------------------------------------------------
// Passkey UI
// ---------------------------------------------------------------------------

class _Credentials {
  const _Credentials(this.username, this.password);
  final String username;
  final String password;
}

/// Asks for the staff passkey. [creating] adds a confirmation field the first
/// time a device starts holding actions.
Future<_Credentials?> _askPasskey(
  BuildContext context, {
  required String title,
  required String description,
  String username = '',
  bool creating = false,
}) {
  return showDialog<_Credentials>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasskeyDialog(
      title: title,
      description: description,
      username: username,
      creating: creating,
    ),
  );
}

class _PasskeyDialog extends StatefulWidget {
  const _PasskeyDialog({
    required this.title,
    required this.description,
    required this.username,
    required this.creating,
  });

  final String title;
  final String description;
  final String username;
  final bool creating;

  @override
  State<_PasskeyDialog> createState() => _PasskeyDialogState();
}

class _PasskeyDialogState extends State<_PasskeyDialog> {
  late final TextEditingController _user = TextEditingController(
    text: widget.username,
  );
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final pass = _pass.text;
    if (_user.text.trim().isEmpty) {
      setState(() => _error = 'Enter the staff username.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'The passkey is at least 6 characters.');
      return;
    }
    if (widget.creating && pass != _confirm.text) {
      setState(() => _error = 'The two passkeys do not match.');
      return;
    }
    Navigator.of(context).pop(_Credentials(_user.text.trim(), pass));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LamalivaShape.sheet),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ADMIN PASSKEY',
            style: T.micro.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
              color: c(LamalivaColors.orangeMid),
            ),
          ),
          const SizedBox(height: 4),
          Text(widget.title, style: T.panelTitle),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description, style: T.bodyMuted),
            const SizedBox(height: LamalivaSpace.md),
            TextField(
              controller: _user,
              autofocus: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Staff username',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            TextField(
              controller: _pass,
              autofocus: true,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Passkey',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show passkey' : 'Hide passkey',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              ),
            ),
            if (widget.creating) ...[
              const SizedBox(height: LamalivaSpace.sm),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm passkey',
                  prefixIcon: Icon(Icons.lock_reset_outlined, size: 20),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: LamalivaSpace.sm),
              Text(
                _error!,
                style: T.micro.copyWith(color: c(LamalivaColors.danger)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Unlock')),
      ],
    );
  }
}

/// Holds one action on the device. Returns `true` when it is safely stored.
///
/// The first hold on a device asks for the admin passkey twice and encrypts the
/// queue with it; later holds reuse the unlocked vault.
Future<bool> holdOfflineAction(
  BuildContext context, {
  required LamalivaApi api,
  required String path,
  required Map<String, dynamic> body,
  required String label,
}) async {
  if (!OfflineVault.unlocked) {
    final creating = !await OfflineVault.hasVault();
    final creds = await _askPasskey(
      context,
      title: creating ? 'Lock the held actions' : 'Unlock held actions',
      description: creating
          ? 'The server cannot be reached. Held actions are encrypted on this '
                'device with the admin passkey; enter it twice to start.'
          : 'Held actions already exist on this device. Enter the passkey that '
                'locked them.',
      username: api.username,
      creating: creating,
    );
    if (creds == null) return false;
    if (!await OfflineVault.unlock(creds.password)) {
      if (context.mounted) {
        _toast(
          context,
          'That passkey does not unlock the actions held on this device.',
          tone: LamalivaColors.danger,
        );
      }
      return false;
    }
  }
  await OfflineVault.hold(
    HeldAction(
      id: heldActionId(path),
      label: label,
      path: path,
      body: body,
      at: DateTime.now(),
    ),
  );
  if (context.mounted) {
    _toast(
      context,
      '$label held on this device — it will sync when the server returns.',
      tone: LamalivaColors.warning,
    );
  }
  return true;
}

/// Pushes every held action, after the server accepts an admin passkey.
///
/// Returns `null` when the passkey was rejected, otherwise a report the caller
/// can show. A `409` means the server already applied the action, so the held
/// copy is dropped rather than replayed twice.
Future<SyncOutcome?> pushHeldActions(
  BuildContext context, {
  required LamalivaApi api,
  required String Function(int sent) describe,
}) async {
  final creds = await _askPasskey(
    context,
    title: 'Push held actions',
    description:
        'A manager or administrator passkey is required to write the '
        '${OfflineVault.pending.value} action(s) held on this device to the '
        'hotel server.',
    username: api.username,
  );
  if (creds == null) return null;

  final probe = LamalivaApi(
    baseUrl: api.baseUrl,
    deviceName: api.deviceName,
    platform: api.platform,
    appVersion: api.appVersion,
  );
  try {
    await probe.login(username: creds.username, password: creds.password);
  } on ApiException catch (error) {
    if (context.mounted) {
      _toast(context, error.message, tone: LamalivaColors.danger);
    }
    return null;
  }
  if (!probe.canApprove) {
    await probe.logout();
    if (context.mounted) {
      _toast(
        context,
        'Only a manager or administrator can authorise a held sync.',
        tone: LamalivaColors.danger,
      );
    }
    return null;
  }

  if (!OfflineVault.unlocked && !await OfflineVault.unlock(creds.password)) {
    await probe.logout();
    if (context.mounted) {
      _toast(
        context,
        'That passkey does not unlock the actions held on this device.',
        tone: LamalivaColors.danger,
      );
    }
    return null;
  }

  var sent = 0;
  String? failure;
  final held = await OfflineVault.actions();
  for (final action in held) {
    try {
      await probe.postRaw(action.path, action.body);
      await OfflineVault.remove(action.id);
      sent++;
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        // The server already has this write; never apply it twice.
        await OfflineVault.remove(action.id);
        sent++;
        continue;
      }
      failure = error.offline
          ? 'The server dropped out again — the rest stay held.'
          : '${action.label}: ${error.message}';
      break;
    }
  }
  final remaining = OfflineVault.pending.value;
  await probe.logout();
  if (context.mounted) {
    _toast(
      context,
      failure ??
          (remaining == 0
              ? describe(sent)
              : '$sent pushed · $remaining still held.'),
      tone: failure != null ? LamalivaColors.warning : LamalivaColors.success,
    );
  }
  return SyncOutcome(sent: sent, remaining: remaining, failure: failure);
}

class SyncOutcome {
  const SyncOutcome({
    required this.sent,
    required this.remaining,
    this.failure,
  });

  final int sent;
  final int remaining;
  final String? failure;

  bool get complete => failure == null && remaining == 0;
}

// ---------------------------------------------------------------------------
// Banner
// ---------------------------------------------------------------------------

/// The strip that tells the desk the truth about the server, and holds the one
/// button that matters: push the held work once the passkey is given.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({
    super.key,
    required this.online,
    required this.held,
    required this.syncing,
    required this.onSync,
  });

  final bool online;
  final int held;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    if (online && held == 0) return const SizedBox.shrink();
    final tone = online ? LamalivaColors.success : LamalivaColors.warning;
    final soft = online
        ? LamalivaColors.successSoft
        : LamalivaColors.warningSoft;
    final message = online
        ? held == 1
              ? 'Server is back — 1 action is held on this device.'
              : 'Server is back — $held actions are held on this device.'
        : held == 0
        ? 'Server unreachable. You can keep working; new actions are held '
              'and encrypted on this device.'
        : 'Server unreachable. Keep working — $held action'
              '${held == 1 ? '' : 's'} held on this device.';
    return Container(
      margin: const EdgeInsets.fromLTRB(
        LamalivaSpace.lg,
        LamalivaSpace.sm,
        LamalivaSpace.lg,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: c(soft).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(LamalivaShape.card),
        border: Border.all(color: c(tone).withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            size: 18,
            color: c(tone),
          ),
          const SizedBox(width: LamalivaSpace.xs),
          Expanded(
            child: Text(
              message,
              style: T.micro.copyWith(color: c(tone), fontSize: 12),
            ),
          ),
          if (held > 0)
            TextButton.icon(
              onPressed: syncing ? null : onSync,
              style: TextButton.styleFrom(
                foregroundColor: c(tone),
                textStyle: const TextStyle(
                  fontFamily: LamalivaType.uiFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                visualDensity: VisualDensity.compact,
              ),
              icon: syncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : const Icon(Icons.key_outlined, size: 16),
              label: Text(online ? 'Sync with passkey' : 'Unlock'),
            ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message, {ColorValue? tone}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: tone == null ? null : c(tone),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
