import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import 'api.dart';
import 'server_settings.dart';
import 'theme.dart';

/// Point this device at the hotel's server. Locked behind administrator
/// credentials: the address is only saved once that account signs in against
/// it and turns out to be an administrator there.
class ServerDialog extends StatefulWidget {
  const ServerDialog({super.key, required this.api, this.onSaved});

  final LamalivaApi api;
  final ValueChanged<String>? onSaved;

  @override
  State<ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<ServerDialog> {
  late final TextEditingController _url =
      TextEditingController(text: widget.api.baseUrl);
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final target = ServerSettings.normalise(_url.text);
    final problem = await ServerSettings.verifyAdmin(
      baseUrl: target,
      username: _username.text,
      password: _password.text,
      deviceName: widget.api.deviceName,
      platform: widget.api.platform,
    );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _busy = false;
        _error = problem;
      });
      return;
    }
    await ServerSettings.save(target);
    if (!mounted) return;
    widget.onSaved?.call(target);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LamalivaShape.panel),
      ),
      title: Text('Server address', style: T.screenTitle.copyWith(fontSize: 22)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This device talks to one hotel server. Enter its address, then confirm '
              'with an administrator password — only an administrator can change it.',
              style: T.bodyMuted,
            ),
            const SizedBox(height: LamalivaSpace.md),
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: '192.168.1.128:8000',
              ),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            TextField(
              controller: _username,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Administrator username'),
            ),
            const SizedBox(height: LamalivaSpace.sm),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Administrator password',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _busy ? null : _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: LamalivaSpace.sm),
              Text(
                _error!,
                style: T.bodyMuted.copyWith(color: c(LamalivaColors.danger)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save address'),
        ),
      ],
    );
  }
}
