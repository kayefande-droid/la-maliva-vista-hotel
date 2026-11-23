import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import '../api.dart';
import '../offline_credentials.dart';
import '../server_dialog.dart';
import '../theme.dart';
import '../widgets.dart';

/// One backdrop photograph and the place it shows.
class _LandingSlide {
  const _LandingSlide(this.asset, this.caption);

  final String asset;
  final String caption;
}

/// The property's own surroundings, at the highest resolution we hold them.
const List<_LandingSlide> _landingSlides = <_LandingSlide>[
  _LandingSlide(
    'assets/img/fako-buea-vista.jpg',
    'Buea from the Fako foothills',
  ),
  _LandingSlide(
    'assets/img/mount-cameroon-dawn.jpg',
    'Mount Cameroon at first light',
  ),
  _LandingSlide('assets/img/mount-cameroon-dusk.jpg', 'Dusk over the mountain'),
  _LandingSlide('assets/img/mount-cameroon-ndongo.jpg', 'Ndongo, above Buea'),
];

/// A slow carousel behind the sign-in form: each photograph cross-fades while
/// breathing on a gentle zoom, so the light changes without the interface
/// moving. Jumping is possible from the ticks, the sequence pauses when the app
/// leaves the foreground, and reduced-motion visitors get one still frame.
class _PhotoCarousel extends StatefulWidget {
  const _PhotoCarousel({required this.compact});

  /// Compact panels are too short for the headline, so the caption takes the
  /// empty bottom corner; wide panels put it opposite the logo instead.
  final bool compact;

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _hold = Duration(seconds: 9);
  static const Duration _fade = Duration(milliseconds: 1800);

  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  Timer? _timer;
  int _index = 0;
  bool _calm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final calm = MediaQuery.disableAnimationsOf(context);
    if (calm == _calm && (_calm || _timer != null)) return;
    _calm = calm;
    _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (_calm) {
      _drift.stop();
      if (_index != 0) setState(() => _index = 0);
      return;
    }
    if (!_drift.isAnimating) _drift.repeat(reverse: true);
    _timer = Timer.periodic(_hold, (_) => _advance());
  }

  void _advance() {
    if (!mounted) return;
    setState(() => _index = (_index + 1) % _landingSlides.length);
  }

  void _show(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    // A deliberate jump restarts the full dwell time on the chosen frame.
    if (!_calm) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
      return;
    }
    _timer?.cancel();
    _timer = null;
    _drift.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The hero is a photograph: dark status-bar glyphs vanish against the
    // mountain. Light glyphs with a transparent bar belong to this screen only.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dpr = MediaQuery.devicePixelRatioOf(context);
          // Decode only as wide as this panel can show: a 1920px photo behind a
          // 700px panel otherwise costs four times the texture memory.
          final decodeWidth = (constraints.maxWidth * dpr).round().clamp(
            480,
            2400,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var i = 0; i < _landingSlides.length; i++)
                      AnimatedOpacity(
                        opacity: i == _index ? 1 : 0,
                        duration: _calm ? Duration.zero : _fade,
                        curve: Curves.easeInOutCubic,
                        child: AnimatedBuilder(
                          animation: _drift,
                          builder: (context, child) => Transform.scale(
                            scale: _calm
                                ? 1
                                : 1.03 +
                                      0.055 *
                                          Curves.easeInOut.transform(
                                            _drift.value,
                                          ),
                            child: child,
                          ),
                          child: Image.asset(
                            _landingSlides[i].asset,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.high,
                            cacheWidth: decodeWidth,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Semantics(
                image: true,
                label:
                    'Photographs of Buea, the Fako foothills and Mount Cameroon',
                child: const SizedBox.expand(),
              ),
              // The transparent status bar draws white glyphs straight onto the
              // photograph; on the pale first-light frame they fell to ~2.5:1.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 132,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [Color(0x59000000), Color(0x00000000)],
                        stops: const [0, 1],
                      ),
                    ),
                  ),
                ),
              ),
              // A scrim, not decoration: the captions and page ticks sit over
              // whatever the photograph offers, and pale sky was swallowing them.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 240,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        // Measured against the pale first-light frame: the old
                        // two-stop ramp left only ~19% black behind the caption.
                        colors: const [
                          Color(0x00000000),
                          Color(0x8C000000),
                          Color(0xB3000000),
                        ],
                        stops: const [0.18, 0.62, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: LamalivaSpace.lg,
                bottom: LamalivaSpace.lg,
                // A fixed column width: AnimatedSwitcher lays its children out in
                // a loose Stack, and unconstrained text would overrun the panel.
                child: SizedBox(
                  width: 208,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _caption(),
                      const SizedBox(height: LamalivaSpace.xs),
                      _ticks(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _caption() {
    return AnimatedSwitcher(
      duration: _calm ? Duration.zero : const Duration(milliseconds: 700),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.22),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey<int>(_index),
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 208,
            child: Text(
              _landingSlides[_index].caption.toUpperCase(),
              textAlign: TextAlign.end,
              maxLines: 2,
              style: TextStyle(
                fontFamily: LamalivaType.uiFamily,
                fontSize: 11,
                height: 1.5,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: const [
                  Shadow(blurRadius: 16, color: Color(0x99000000)),
                  Shadow(blurRadius: 4, color: Color(0x66000000)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(width: 26, height: 1.5, color: c(LamalivaColors.orangeMid)),
        ],
      ),
    );
  }

  Widget _ticks() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _landingSlides.length; i++)
          Semantics(
            button: true,
            selected: i == _index,
            label: 'Photograph ${i + 1}: ${_landingSlides[i].caption}',
            onTap: () => _show(i),
            child: GestureDetector(
              onTap: () => _show(i),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 26,
                height: 32,
                child: Center(
                  child: AnimatedContainer(
                    duration: _calm
                        ? Duration.zero
                        : const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    width: i == _index ? 17 : 6,
                    height: 2,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: i == _index ? 1 : 0.55,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
      if (e.offline) {
        // The server is down, not the hotel. A device that has signed this
        // person in before can keep working from its own caches, with writes
        // held in the encrypted vault until the server returns.
        final saved = await OfflineCredentials.recognise(
          username: username,
          password: password,
        );
        if (saved != null) {
          widget.api.adoptOfflineSession(saved);
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Signed in from this device. The hotel server is unreachable, '
                  'so new work is held here until it returns.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          widget.onSignedIn();
          return;
        }
        setState(() {
          _error =
              'The hotel server cannot be reached, and this device has not '
              'signed this account in before. Connect to the hotel network '
              'once to enable offline sign-in.';
        });
        return;
      }
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
      builder: (_) =>
          ServerDialog(api: widget.api, onSaved: widget.onServerSelected),
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
    // Under roughly 600px of photograph the headline and the caption fight for
    // the same corner, so the image keeps only its label.
    final photoWidth = constraints.maxWidth * 0.56;
    return Row(
      children: [
        Expanded(
          flex: 56,
          child: _photoPanel(
            constraints.maxHeight,
            showHeadline: photoWidth >= 600,
          ),
        ),
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
          SizedBox(
            height: photoHeight,
            child: _photoPanel(photoHeight, compact: true),
          ),
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

  Widget _photoPanel(
    double height, {
    bool compact = false,
    bool showHeadline = true,
  }) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PhotoCarousel(compact: compact),
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
            padding: EdgeInsets.all(
              compact ? LamalivaSpace.lg : LamalivaSpace.xxl,
            ),
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
                if (!compact && showHeadline)
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
                      ],
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
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
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
              child: Text(
                'Change',
                style: T.micro.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
