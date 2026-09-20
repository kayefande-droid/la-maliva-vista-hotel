// ============================================================
// La-Maliva Vista Hotel — Native App (Flutter / Dart)
// Luxury navy/orange/cream theme, offline room cache,
// notification + storage permission flows, in-app booking.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

const String kBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'https://la-maliva-vista-hotel.onrender.com',
);
const String kAppVersion = '2.1.1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LamalivaApp());
}

// ------------------------------------------------------------
// Theme
// ------------------------------------------------------------
class AppColors {
  static const navy950 = Color(0xFF0A1628);
  static const navy900 = Color(0xFF0F2240);
  static const navy800 = Color(0xFF16305C);
  static const orange500 = Color(0xFFF08C2E);
  static const orange600 = Color(0xFFD97A2B);
  static const gold = Color(0xFFEEC37A);
  static const cream50 = Color(0xFFFDF9F2);
  static const cream100 = Color(0xFFF8F1E4);
  static const ink900 = Color(0xFF14202E);
  static const ink500 = Color(0xFF5B6B7D);
}

final ThemeData luxuryLight = ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  scaffoldBackgroundColor: AppColors.cream50,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.orange500,
    primary: AppColors.orange600,
    secondary: AppColors.navy900,
    surface: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.navy950,
    foregroundColor: AppColors.cream50,
    elevation: 0,
    centerTitle: false,
  ),
);

// ------------------------------------------------------------
// Root
// ------------------------------------------------------------
class LamalivaApp extends StatelessWidget {
  const LamalivaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La-Maliva Vista',
      debugShowCheckedModeBanner: false,
      theme: luxuryLight,
      home: const SplashGate(),
    );
  }
}

/// Splash → permissions (first launch only) → Home
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy950,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.gold, width: 3),
                boxShadow: [BoxShadow(color: AppColors.orange500.withOpacity(0.35), blurRadius: 40, spreadRadius: 4)],
              ),
              child: ClipOval(
                child: Image.asset('assets/logo.png', fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.hotel, size: 48, color: AppColors.gold)),
              ),
            ),
            const SizedBox(height: 22),
            const Text('LA-MALIVA VISTA',
                style: TextStyle(color: AppColors.cream50, fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('A TASTE OF PARADISE',
                style: TextStyle(color: AppColors.gold, fontSize: 10, letterSpacing: 5)),
            const SizedBox(height: 34),
            const SizedBox(
              width: 26, height: 26,
              child: CircularProgressIndicator(color: AppColors.orange500, strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    await _askPermissionsOnce();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
    // Warm the offline cache in the background
    RoomRepository.instance.refresh().catchError((_) => <Room>[]);
  }

  Future<void> _askPermissionsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('perms_asked') == true) return;
    await prefs.setBool('perms_asked', true);

    // Initialize notifications, then request the notification permission
    // (Android 13+ shows a system dialog; older versions just enable it).
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermission();
    await NotificationService.instance.welcome();
  }
}

// ------------------------------------------------------------
// Notifications
// ------------------------------------------------------------
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    final windows = (Platform.isWindows)
        ? const WindowsInitializationSettings(
            appName: 'La-Maliva Vista',
            appUserModelId: 'com.lamaliva.lamaliva_app',
            guid: '6A9F27B1-3C4E-4D8A-9B2F-1E5C7D8A0F31',
          )
        : null;
    await _plugin.initialize(
      settings: InitializationSettings(
        android: android,
        iOS: ios,
        windows: windows,
      ),
    );
    _ready = true;
  }

  /// Asks the user to allow notifications (system dialog on Android 13+).
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted =
          await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return true; // older Android versions grant by default
    }
  }

  Future<void> welcome() async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'general',
        'General',
        channelDescription: 'Booking updates and hotel news',
        importance: Importance.high,
        priority: Priority.high,
        color: AppColors.orange500,
      ),
    );
    try {
      await _plugin.show(
        id: 1,
        title: 'Welcome to La-Maliva Vista',
        body: 'Permissions granted — rooms are cached for offline use.',
        notificationDetails: details,
      );
    } catch (_) {}
  }
}

// ------------------------------------------------------------
// Data
// ------------------------------------------------------------
class Room {
  final int id;
  final String number;
  final String type;
  final double price;
  final String? description;
  final String? imageUrl;

  Room({
    required this.id,
    required this.number,
    required this.type,
    required this.price,
    this.description,
    this.imageUrl,
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: (j['id'] as num).toInt(),
        number: (j['room_number'] ?? '').toString(),
        type: (j['room_type'] ?? '').toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        description: j['description'] as String?,
        imageUrl: j['image_url'] as String?,
      );
}

class RoomRepository {
  RoomRepository._();
  static final RoomRepository instance = RoomRepository._();

  static const _cacheKey = 'rooms_cache_v1';
  List<Room> rooms = [];
  bool fromCache = false;

  Future<List<Room>> load() async {
    if (rooms.isNotEmpty) return rooms;
    // 1) cache first (instant, offline-friendly)
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        rooms = list.map(Room.fromJson).toList();
        fromCache = true;
      } catch (_) {}
    }
    return rooms;
  }

  Future<List<Room>> refresh() async {
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/api/public-rooms'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        rooms = list.map(Room.fromJson).toList();
        fromCache = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _cacheKey,
          jsonEncode(rooms
              .map((r) => {
                    'id': r.id,
                    'room_number': r.number,
                    'room_type': r.type,
                    'price': r.price,
                    'description': r.description,
                    'image_url': r.imageUrl,
                  })
              .toList()),
        );
      }
    } catch (_) {
      fromCache = true;
    }
    return rooms;
  }
}

// ------------------------------------------------------------
// Home shell with bottom navigation
// ------------------------------------------------------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const RoomsPage(), const PerksPage(), const SettingsPage()];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        height: 66,
        backgroundColor: AppColors.navy950,
        indicatorColor: AppColors.orange600.withOpacity(0.25),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.king_bed_outlined), selectedIcon: Icon(Icons.king_bed), label: 'Rooms'),
          NavigationDestination(icon: Icon(Icons.local_offer_outlined), selectedIcon: Icon(Icons.local_offer), label: 'Perks'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Rooms page (offline-capable)
// ------------------------------------------------------------
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});
  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  bool _loading = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await RoomRepository.instance.load();
    if (mounted) {
      setState(() {
        _loading = false;
        _notice = RoomRepository.instance.fromCache ? 'Showing cached rates — offline' : null;
      });
    }
    await RoomRepository.instance.refresh();
    if (mounted) setState(() => _notice = null);
  }

  Future<void> _book(Room room) async {
    final ok = await launchUrl(Uri.parse('$kBaseUrl/login'), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the booking site')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = RoomRepository.instance.rooms;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: const [
          CircleAvatar(backgroundImage: AssetImage('assets/logo.png'), radius: 16),
          SizedBox(width: 10),
          Text('La-Maliva Vista', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await RoomRepository.instance.refresh();
          setState(() {});
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(onBookTap: () => _book(Room(id: 0, number: '', type: '', price: 0))),
            ),
            if (_notice != null)
              SliverToBoxAdapter(
                child: Container(
                  color: AppColors.gold.withOpacity(0.25),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(children: const [
                    Icon(Icons.wifi_off, size: 16, color: AppColors.navy900),
                    SizedBox(width: 8),
                    Expanded(child: Text('Showing cached rates — offline', style: TextStyle(fontSize: 12, color: AppColors.navy900))),
                  ]),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: AppColors.orange500)),
              )
            else if (rooms.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No rooms available right now', style: TextStyle(color: AppColors.ink500))),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _RoomCard(room: rooms[i], onBook: () => _book(rooms[i])),
                    childCount: rooms.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final VoidCallback onBookTap;
  const _Hero({required this.onBookTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy950, AppColors.navy800],
        ),
        boxShadow: [BoxShadow(color: AppColors.navy950.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('A TASTE OF PARADISE', style: TextStyle(color: AppColors.gold, fontSize: 10, letterSpacing: 4)),
          const SizedBox(height: 10),
          const Text('Where paradise\nfeels like home.',
              style: TextStyle(color: Colors.white, fontSize: 26, height: 1.2, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onBookTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange500,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('RESERVE NOW', style: TextStyle(letterSpacing: 1.5, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onBook;
  const _RoomCard({required this.room, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.navy950.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(children: [
              SizedBox(
                height: 170,
                width: double.infinity,
                child: room.imageUrl != null && room.imageUrl!.isNotEmpty
                    ? Image.network(room.imageUrl!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imgFallback())
                    : _imgFallback(),
              ),
              Positioned(
                top: 10, left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(999)),
                  child: Text('ROOM ${room.number}',
                      style: const TextStyle(fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: AppColors.navy900)),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(room.type, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(room.description ?? 'Thoughtfully appointed comfort.',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.ink500, fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                RichText(text: TextSpan(children: [
                  const TextSpan(text: 'FCFA ', style: TextStyle(color: AppColors.orange600, fontSize: 10, fontWeight: FontWeight.w700)),
                  TextSpan(text: room.price.toStringAsFixed(0), style: const TextStyle(color: AppColors.navy900, fontSize: 20, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' / night', style: TextStyle(color: AppColors.ink500, fontSize: 11)),
                ])),
                ElevatedButton(
                  onPressed: onBook,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('RESERVE', style: TextStyle(fontSize: 11, letterSpacing: 1.2)),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _imgFallback() => Container(
        color: AppColors.cream100,
        child: const Center(child: Icon(Icons.hotel, size: 44, color: AppColors.orange500)),
      );
}

// ------------------------------------------------------------
// Perks page
// ------------------------------------------------------------
class PerksPage extends StatelessWidget {
  const PerksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final perks = [
      (Icons.wifi, 'Fibre Wi-Fi', 'Fast, free connectivity everywhere.'),
      (Icons.restaurant, 'Garden Restaurant', 'Local & continental dishes daily.'),
      (Icons.phone_android, 'MoMo Payments', 'Pay securely with MTN MoMo.'),
      (Icons.hiking, 'Mountain Treks', 'Guided Mount Cameroon excursions.'),
      (Icons.support_agent, '24/7 Concierge', 'We are always awake for you.'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Hotel Perks')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: perks.length,
        itemBuilder: (context, i) {
          final p = perks[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.navy950.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: AppColors.orange500.withOpacity(0.12), borderRadius: BorderRadius.circular(13)),
                child: Icon(p.$1, color: AppColors.orange600),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 3),
                Text(p.$3, style: const TextStyle(color: AppColors.ink500, fontSize: 12.5)),
              ])),
            ]),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------
// Settings / account page
// ------------------------------------------------------------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              backgroundImage: AssetImage('assets/logo.png'),
              radius: 40,
              backgroundColor: AppColors.cream100,
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: Text('La-Maliva Vista', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          const Center(child: Text('Native App v$kAppVersion', style: TextStyle(color: AppColors.ink500, fontSize: 12))),
          const SizedBox(height: 24),
          _SettingsTile(
            icon: Icons.notifications_active_outlined,
            title: 'Notification permissions',
            subtitle: 'Manage booking alerts',
            onTap: () async {
              await NotificationService.instance.init();
              await NotificationService.instance.welcome();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Test notification sent — if you did not see it, enable notifications in system settings')),
                );
              }
            },
          ),
          _SettingsTile(
            icon: Icons.notifications_active_outlined,
            title: 'Notification permission',
            subtitle: 'Re-request booking alerts',
            onTap: () async {
              final granted = await NotificationService.instance.requestPermission();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(granted ? 'Notifications are enabled' : 'Notifications remain disabled — enable them in system settings')),
                );
              }
            },
          ),
          _SettingsTile(
            icon: Icons.language,
            title: 'Open full website',
            subtitle: kBaseUrl,
            onTap: () => launchUrl(Uri.parse(kBaseUrl), mode: LaunchMode.externalApplication),
          ),
          _SettingsTile(
            icon: Icons.support_agent,
            title: 'Call reception',
            subtitle: '(+237) 679-915-967',
            onTap: () => launchUrl(Uri.parse('tel:+237679915967')),
          ),
          const SizedBox(height: 20),
          const Center(child: Text('© La-Maliva Vista Hotel · Buea, Cameroon',
              style: TextStyle(color: AppColors.ink500, fontSize: 11))),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.navy900.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.navy900),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.ink500, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.ink500),
            ]),
          ),
        ),
      ),
    );
  }
}
