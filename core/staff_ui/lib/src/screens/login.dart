import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../server_dialog.dart';
import '../theme.dart';
import '../widgets.dart';

/// A 24-second drift across the photograph. Sells the place without moving the
/// interface, and holds still when reduced motion is requested.
class _SlowZoom extends StatefulWidget {
  const _SlowZoom({required this.child});

  final Widget child;

  @override
  State<_SlowZoom> createState() => _SlowZoomState();
}

class _SlowZoomState extends State<_SlowZoom>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: 1.0 + 0.055 * Curves.easeInOut.transform(_controller.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// The front door: Mount Cameroon at dusk on the left, the form on the right.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onSignedIn,
    this.onServerSelected,
  });

  final LamalivaApi api;
  final VoidCallback onSignedIn;

  /// Called after an administrator points this device at another server.
  final ValueChanged<String>? onServerSelected;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _user.text.trim();
    final password = _pass.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.login(username: username, password: password);
      if (!mounted) return;
      widget.onSignedIn();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Only an administrator can repoint this device: the dialog signs in against
  /// the candidate address and saves it only for an admin account.
  Future<void> _changeServer() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ServerDialog(
        api: widget.api,
        onSaved: widget.onServerSelected,
      ),
    );
    if (mounted) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: c(LamalivaColors.cream),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= LamalivaBreakpoints.medium;
          return wide ? _wide(constraints) : _compact(constraints);
        },
      ),
    );
  }

  Widget _wide(BoxConstraints constraints) {
    return Row(
      children: [
        Expanded(flex: 56, child: _photoPanel(constraints.maxHeight)),
        Expanded(
          flex: 44,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: LamalivaSpace.xxl,
                vertical: LamalivaSpace.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 392),
                child: _form(onPhoto: false),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _compact(BoxConstraints constraints) {
    final photoHeight = (constraints.maxHeight * 0.36).clamp(210.0, 320.0);
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: photoHeight, child: _photoPanel(photoHeight, compact: true)),
          Padding(
            padding: EdgeInsets.fromLTRB(
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg,
              LamalivaSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: _form(onPhoto: false),
          ),
        ],
      ),
    );
  }

  Widget _photoPanel(double height, {bool compact = false}) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _SlowZoom(
            child: Image(
              image: AssetImage('assets/img/buea-sunset.jpg'),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              alignment: Alignment.center,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  c(LamalivaColors.navy900).withValues(alpha: 0.72),
                  c(LamalivaColors.navy900).withValues(alpha: 0.18),
                  c(LamalivaColors.navy900).withValues(alpha: 0.86),
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? LamalivaSpace.lg : LamalivaSpace.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Semantics(
                      image: true,
                      label: 'La Maliva Vista hotel logo',
                      child: Image.asset(
                        'assets/logo.png',
                        width: compact ? 44 : 54,
                        height: compact ? 44 : 54,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    const SizedBox(width: LamalivaSpace.sm),
                    Expanded(
                      child: Text(
                        'La Maliva Vista',
                        style: TextStyle(
                          fontFamily: LamalivaType.displayFamily,
                          fontSize: compact ? 22 : 26,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!compact)
                  Reveal(
                    delay: const Duration(milliseconds: 120),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A taste of paradise\nabove the coast',
                        style: TextStyle(
                          fontFamily: LamalivaType.displayFamily,
                          fontSize: 42,
                          height: 1.12,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: LamalivaSpace.md),
                      Container(
                        width: 56,
                        height: 2,
                        color: c(LamalivaColors.orangeMid),
                      ),
                      const SizedBox(height: LamalivaSpace.sm),
                      Text(
                        'Buea  ·  Mount Cameroon',
                        style: TextStyle(
                          fontFamily: LamalivaType.uiFamily,
                          fontSize: 12.5,
                          letterSpacing: 0.2,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                    ),
                  ),
                if (compact)
                  Text(
                    'Buea  ·  Mount Cameroon',
                    style: TextStyle(
                      fontFamily: LamalivaType.uiFamily,
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _form({required bool onPhoto}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Staff sign-in',
          style: T.label.copyWith(color: c(LamalivaColors.orangeMid)),
        ),
        const SizedBox(height: LamalivaSpace.xxs),
        Text('Welcome back', style: T.screenTitle),
        const SizedBox(height: LamalivaSpace.xs),
        Text(
          'Manage rooms, guests and bookings for the hotel.',
          style: T.bodyMuted,
        ),
        const SizedBox(height: LamalivaSpace.xl),
        TextField(
          controller: _user,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Username or email',
            prefixIcon: Icon(Icons.person_outline, size: 18),
          ),
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          onSubmitted: (_) => _passFocus.requestFocus(),
        ),
        const SizedBox(height: LamalivaSpace.sm),
        TextField(
          controller: _pass,
          focusNode: _passFocus,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
        ),
        AnimatedSize(
          duration: LamalivaMotion.standard,
          alignment: Alignment.topCenter,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: LamalivaSpace.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: LamalivaSpace.sm,
                    vertical: LamalivaSpace.xs,
                  ),
                  decoration: BoxDecoration(
                    color: c(LamalivaColors.dangerSoft).withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(LamalivaShape.input),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: c(LamalivaColors.danger),
                      ),
                      const SizedBox(width: LamalivaSpace.xs),
                      Expanded(
                        child: Text(
                          _error!,
                          style: T.bodyMuted.copyWith(
                            color: c(LamalivaColors.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: LamalivaSpace.lg),
        PrimaryButton(
          label: 'Sign in',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: LamalivaSpace.md),
        Row(
          children: [
            Icon(
              Icons.shield_outlined,
              size: 14,
              color: c(LamalivaColors.inkFaint),
            ),
            const SizedBox(width: LamalivaSpace.xs),
            Expanded(
              child: Text(
                'Staff and management only. This device is registered when you sign in.',
                style: T.micro,
              ),
            ),
          ],
        ),
        const SizedBox(height: LamalivaSpace.xxs),
        Row(
          children: [
            Expanded(
              child: Text(
                'Server  ${widget.api.baseUrl}',
                style: T.micro.copyWith(color: c(LamalivaColors.inkFaint)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _changeServer,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Change', style: T.micro.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ],
    );
  }
}
