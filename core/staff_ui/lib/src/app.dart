import 'package:flutter/material.dart';

import 'package:lamaliva_design/lamaliva_design.dart';

import 'api.dart';
import 'screens/admin.dart';
import 'screens/guests.dart';
import 'screens/inventory.dart';
import 'screens/login.dart';
import 'screens/register_guest.dart';
import 'screens/overview.dart';
import 'screens/reservations.dart';
import 'screens/rooms.dart';
import 'server_settings.dart';
import 'theme.dart';

/// The staff console. One implementation, two shells: a navy rail on a wide
/// window, a bottom bar on a phone.
class StaffApp extends StatefulWidget {
  const StaffApp({
    super.key,
    required this.apiBaseUrl,
    required this.deviceName,
    required this.platform,
  });

  final String apiBaseUrl;
  final String deviceName;
  final String platform;

  @override
  State<StaffApp> createState() => _StaffAppState();
}

class _StaffAppState extends State<StaffApp> {
  late LamalivaApi _api;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _api = _createApi(widget.apiBaseUrl);
    _restoreServer();
  }

  LamalivaApi _createApi(String baseUrl) => LamalivaApi(
        baseUrl: baseUrl,
        deviceName: widget.deviceName,
        platform: widget.platform,
      );

  /// A server address chosen earlier on this device wins over the build default.
  Future<void> _restoreServer() async {
    final saved = await ServerSettings.read();
    if (!mounted || saved == null || saved == _api.baseUrl) return;
    setState(() => _api = _createApi(saved));
  }

  void _useServer(String baseUrl) {
    setState(() {
      _api = _createApi(baseUrl);
      _signedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La Maliva Vista — Staff',
      debugShowCheckedModeBanner: false,
      theme: buildStaffTheme(),
      home: AnimatedSwitcher(
        duration: LamalivaMotion.page,
        child: _signedIn
            ? SessionShell(
                key: const ValueKey('session'),
                api: _api,
                onSignOut: () async {
                  await _api.logout();
                  if (mounted) setState(() => _signedIn = false);
                },
              )
            : LoginScreen(
                key: const ValueKey('login'),
                api: _api,
                onSignedIn: () => setState(() => _signedIn = true),
                onServerSelected: _useServer,
              ),
      ),
    );
  }
}

class _Destination {
  const _Destination(
    this.label,
    this.icon,
    this.selectedIcon,
    this.title,
    this.subtitle, {
    this.adminOnly = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String subtitle;
  final bool adminOnly;
}

const _destinations = <_Destination>[
  _Destination(
    'Overview',
    Icons.dashboard_outlined,
    Icons.dashboard,
    'Today',
    'Arrivals, departures and the state of the house.',
  ),
  _Destination(
    'Rooms',
    Icons.meeting_room_outlined,
    Icons.meeting_room,
    'Rooms',
    'Fourteen rooms across two floors, with rates and housekeeping state.',
  ),
  _Destination(
    'Bookings',
    Icons.event_note_outlined,
    Icons.event_note,
    'Bookings',
    'Every stay on record, from enquiry to check-out.',
  ),
  _Destination(
    'Guests',
    Icons.people_outline,
    Icons.people,
    'Guests',
    'The guest book, with the details the front desk needs.',
  ),
  _Destination(
    'Stock',
    Icons.inventory_2_outlined,
    Icons.inventory_2,
    'Stock',
    'What the store room holds, and every movement in or out.',
  ),
  _Destination(
    'Admin',
    Icons.admin_panel_settings_outlined,
    Icons.admin_panel_settings,
    'Admin tools',
    'Staff accounts and the nightly rate of each room type.',
    adminOnly: true,
  ),
];

class SessionShell extends StatefulWidget {
  const SessionShell({super.key, required this.api, required this.onSignOut});

  final LamalivaApi api;
  final Future<void> Function() onSignOut;

  @override
  State<SessionShell> createState() => _SessionShellState();
}

class _SessionShellState extends State<SessionShell> {
  int _index = 0;
  int _refresh = 0;

  List<_Destination> get _items => widget.api.isAdmin
      ? _destinations
      : _destinations.where((d) => !d.adminOnly).toList();

  Widget _screen() {
    final key = ValueKey('${_index}_$_refresh');
    switch (_index) {
      case 0:
        return OverviewScreen(key: key, api: widget.api);
      case 1:
        return RoomsScreen(key: key, api: widget.api);
      case 2:
        return ReservationsScreen(key: key, api: widget.api);
      case 3:
        return GuestsScreen(key: key, api: widget.api);
      case 4:
        return InventoryScreen(key: key, api: widget.api);
      default:
        return AdminScreen(key: key, api: widget.api);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= LamalivaBreakpoints.medium;
        return Scaffold(
          backgroundColor: c(LamalivaColors.cream),
          appBar: wide ? null : _mobileBar(),
          body: wide
              ? Row(
                  children: [
                    _Rail(
                      index: _index,
                      api: widget.api,
                      onSelect: (i) => setState(() => _index = i),
                      onSignOut: widget.onSignOut,
                    ),
                    Expanded(child: _content(wide: true)),
                  ],
                )
              : _content(wide: false),
          bottomNavigationBar: wide ? null : _mobileNav(),
        );
      },
    );
  }

  Widget _content({required bool wide}) {
    final destination = _items[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            wide ? LamalivaSpace.xl : LamalivaSpace.lg,
            wide ? LamalivaSpace.lg : LamalivaSpace.md,
            wide ? LamalivaSpace.xl : LamalivaSpace.md,
            LamalivaSpace.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination.title, style: T.screenTitle),
                    const SizedBox(height: 2),
                    Text(
                      destination.subtitle,
                      style: T.bodyMuted,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LamalivaSpace.sm),
              if (wide && widget.api.staffRole != 'housekeeping')
                Padding(
                  padding: const EdgeInsets.only(right: LamalivaSpace.xs),
                  child: GhostButton(
                    label: 'Register guest',
                    icon: Icons.person_add_alt,
                    onPressed: _openRegister,
                  ),
                ),
              if (wide)
                GhostButton(
                  label: 'Refresh',
                  icon: Icons.refresh,
                  onPressed: () => setState(() => _refresh++),
                )
              else
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => setState(() => _refresh++),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: LamalivaMotion.page,
            switchInCurve: const Cubic(0.16, 1.0, 0.3, 1.0),
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.012),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _screen(),
          ),
        ),
      ],
    );
  }

  Future<void> _openRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: c(LamalivaColors.cream),
          appBar: AppBar(
            backgroundColor: c(LamalivaColors.navy900),
            foregroundColor: Colors.white,
            title: const Text('Register guest'),
          ),
          body: RegisterGuestScreen(
            api: widget.api,
            onDone: () => setState(() => _refresh++),
          ),
        ),
      ),
    );
    if (mounted) setState(() => _refresh++);
  }

  PreferredSizeWidget _mobileBar() {
    return AppBar(
      backgroundColor: c(LamalivaColors.navy900),
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 58,
      titleSpacing: LamalivaSpace.md,
      title: Row(
        children: [
          Semantics(
            image: true,
            label: 'La Maliva Vista hotel logo',
            child: Image.asset(
              'assets/logo.png',
              width: 30,
              height: 30,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: LamalivaSpace.xs),
          Expanded(
            child: Text(
              'La Maliva Vista',
              style: TextStyle(
                fontFamily: LamalivaType.displayFamily,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => widget.onSignOut(),
          icon: const Icon(Icons.logout, size: 20),
        ),
        const SizedBox(width: LamalivaSpace.xxs),
      ],
    );
  }

  Widget _mobileNav() {
    final items = _items;
    return Container(
      decoration: BoxDecoration(
        color: c(LamalivaColors.navy900),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTap(
                    onTap: () => setState(() => _index = i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _index == i
                              ? items[i].selectedIcon
                              : items[i].icon,
                          size: 20,
                          color: _index == i
                              ? c(LamalivaColors.orangeStart)
                              : Colors.white.withValues(alpha: 0.66),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontFamily: LamalivaType.uiFamily,
                            fontSize: 11,
                            fontWeight: _index == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _index == i
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.66),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.api,
    required this.onSelect,
    required this.onSignOut,
  });

  final int index;
  final LamalivaApi api;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final items = api.isAdmin
        ? _destinations
        : _destinations.where((d) => !d.adminOnly).toList();
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: c(LamalivaColors.navy900),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LamalivaSpace.lg,
                LamalivaSpace.lg,
                LamalivaSpace.md,
                LamalivaSpace.xl,
              ),
              child: Row(
                children: [
                  Semantics(
                    image: true,
                    label: 'La Maliva Vista hotel logo',
                    child: Image.asset(
                      'assets/logo.png',
                      width: 40,
                      height: 40,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: LamalivaSpace.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'La Maliva Vista',
                          style: TextStyle(
                            fontFamily: LamalivaType.displayFamily,
                            fontSize: 19,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Staff console',
                          style: TextStyle(
                            fontFamily: LamalivaType.uiFamily,
                            fontSize: 11.5,
                            color: c(LamalivaColors.sky300).withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LamalivaSpace.sm,
                  vertical: 2,
                ),
                child: _RailItem(
                  destination: items[i],
                  selected: index == i,
                  onTap: () => onSelect(i),
                ),
              ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.all(LamalivaSpace.sm),
              padding: const EdgeInsets.all(LamalivaSpace.sm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.045),
                borderRadius: BorderRadius.circular(LamalivaShape.card),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: c(LamalivaColors.orangeMid),
                    child: Text(
                      api.staffName.isEmpty
                          ? 'S'
                          : api.staffName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: LamalivaType.uiFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: LamalivaSpace.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          api.staffName,
                          style: const TextStyle(
                            fontFamily: LamalivaType.uiFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          api.staffRole,
                          style: TextStyle(
                            fontFamily: LamalivaType.uiFamily,
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onSignOut(),
                    icon: Icon(
                      Icons.logout,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: selected,
          child: AnimatedContainer(
            duration: LamalivaMotion.quick,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: LamalivaSpace.sm),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.09)
                  : _hover
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(LamalivaShape.input),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: LamalivaMotion.quick,
                  width: 3,
                  height: selected ? 18 : 0,
                  margin: const EdgeInsets.only(right: LamalivaSpace.xs),
                  decoration: BoxDecoration(
                    color: c(LamalivaColors.orangeMid),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  selected ? widget.destination.selectedIcon : widget.destination.icon,
                  size: 18,
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.62),
                ),
                const SizedBox(width: LamalivaSpace.sm),
                Text(
                  widget.destination.label,
                  style: TextStyle(
                    fontFamily: LamalivaType.uiFamily,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.72),
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

class _NavTap extends StatelessWidget {
  const _NavTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}
