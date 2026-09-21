// ============================================================
// La-Maliva Vista Hotel — Native App (Flutter / Dart)
// API client of the website backend (same database):
//   • token auth (guest / staff / admin)
//   • rooms + snackbar + bookings straight from the site API
//   • offline cache for rooms, menu, hotel info
//   • offline staff tools: register guests + print invoices
//   • admin: feature toggles, staff accounts, menu uploads
//   • payments + snackbar sections gated by admin toggles
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const String kBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'https://la-maliva-vista-hotel.onrender.com',
);
const String kAppVersion = '2.3.4';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LamalivaApp());
}

// ------------------------------------------------------------
// Theme — luxury navy / burnt orange / cream, light + dark
// ------------------------------------------------------------
// ------------------------------------------------------------
// Design styles — 6 switchable luxury packs. Every color in the app
// reads from the active palette, so picking a style re-skins the whole
// app (themes, waves, cards, nav bar) instantly.
// ------------------------------------------------------------
class AppColors {
  static Map<String, Color> _p = LuxTheme.palettes['royal']!;
  static void apply(Map<String, Color> palette) => _p = palette;

  static Color get navy950 => _p['navy950']!;
  static Color get brandNavy => _p['brandNavy']!;
  static Color get navy900 => _p['navy900']!;
  static Color get navy800 => _p['navy800']!;
  static Color get orange500 => _p['orange500']!;
  static Color get orange600 => _p['orange600']!;
  static Color get gold => _p['gold']!;
  static Color get cream50 => _p['cream50']!;
  static Color get cream100 => _p['cream100']!;
  static Color get ink900 => _p['ink900']!;
  static Color get ink500 => _p['ink500']!;
}

class LuxTheme {
  /// Style currently applied (drives the ambient background variant too).
  static String currentId = 'royal';

  static const Map<String, Map<String, Color>> palettes = {
    'royal': {
      'navy950': Color(0xFF0A1628), 'brandNavy': Color(0xFF08123A),
      'navy900': Color(0xFF0F2240), 'navy800': Color(0xFF16305C),
      'orange500': Color(0xFFF08C2E), 'orange600': Color(0xFFD97A2B),
      'gold': Color(0xFFEEC37A), 'cream50': Color(0xFFFDF9F2),
      'cream100': Color(0xFFF8F1E4), 'ink900': Color(0xFF14202E), 'ink500': Color(0xFF5B6B7D),
    },
    'sunset': {
      'navy950': Color(0xFF1C1210), 'brandNavy': Color(0xFF2A1812),
      'navy900': Color(0xFF362017), 'navy800': Color(0xFF4A2C1D),
      'orange500': Color(0xFFFFA94D), 'orange600': Color(0xFFE8853B),
      'gold': Color(0xFFFFD08A), 'cream50': Color(0xFFFFF8EF),
      'cream100': Color(0xFFF9EADB), 'ink900': Color(0xFF2B1B12), 'ink500': Color(0xFF8A7362),
    },
    'emerald': {
      'navy950': Color(0xFF06231C), 'brandNavy': Color(0xFF07352A),
      'navy900': Color(0xFF0A4436), 'navy800': Color(0xFF0E5A47),
      'orange500': Color(0xFFF0A22E), 'orange600': Color(0xFFD9842B),
      'gold': Color(0xFFE8C97A), 'cream50': Color(0xFFF6FBF7),
      'cream100': Color(0xFFE9F4EC), 'ink900': Color(0xFF122720), 'ink500': Color(0xFF5F7A6F),
    },
    'plum': {
      'navy950': Color(0xFF1E0A1E), 'brandNavy': Color(0xFF2E0F2C),
      'navy900': Color(0xFF3D1440), 'navy800': Color(0xFF571C55),
      'orange500': Color(0xFFF0752E), 'orange600': Color(0xFFD65F2B),
      'gold': Color(0xFFE9BFB3), 'cream50': Color(0xFFFDF6F7),
      'cream100': Color(0xFFF7E8ED), 'ink900': Color(0xFF2A1220), 'ink500': Color(0xFF7D6472),
    },
    'ocean': {
      'navy950': Color(0xFF061E2A), 'brandNavy': Color(0xFF073041),
      'navy900': Color(0xFF0A4155), 'navy800': Color(0xFF0E566E),
      'orange500': Color(0xFFF09A2E), 'orange600': Color(0xFFD97F2B),
      'gold': Color(0xFF7FD4D8), 'cream50': Color(0xFFF4FBFD),
      'cream100': Color(0xFFE5F2F6), 'ink900': Color(0xFF102630), 'ink500': Color(0xFF5E7A85),
    },
    'noir': {
      'navy950': Color(0xFF0D0F12), 'brandNavy': Color(0xFF16191E),
      'navy900': Color(0xFF1E2228), 'navy800': Color(0xFF2B313A),
      'orange500': Color(0xFFF08C2E), 'orange600': Color(0xFFD97A2B),
      'gold': Color(0xFFE0B36A), 'cream50': Color(0xFFF7F7F5),
      'cream100': Color(0xFFEBEBE8), 'ink900': Color(0xFF17191C), 'ink500': Color(0xFF6E747D),
    },
  };

  static const List<Map<String, String>> meta = [
    {'id': 'royal', 'name': 'Royal Navy', 'tag': 'The classic brand'},
    {'id': 'sunset', 'name': 'Sunset Amber', 'tag': 'Warm & golden'},
    {'id': 'emerald', 'name': 'Emerald Royale', 'tag': 'Deep green luxury'},
    {'id': 'plum', 'name': 'Plum Noir', 'tag': 'Velvet evening'},
    {'id': 'ocean', 'name': 'Ocean Teal', 'tag': 'Cool & calm'},
    {'id': 'noir', 'name': 'Graphite Noir', 'tag': 'Slate minimal'},
  ];

  static void apply(String id) {
    AppColors.apply(palettes[id] ?? palettes['royal']!);
    currentId = palettes.containsKey(id) ? id : 'royal';
  }

  /// Ambient background motion per design style — each pack gets its own
  /// animated backdrop (waves, embers, orbs, petals, streaks, rings).
  static String get ambient => const {
        'royal': 'waves',
        'sunset': 'embers',
        'emerald': 'petals',
        'plum': 'orbs',
        'ocean': 'bubbles',
        'noir': 'streaks',
      }[currentId] ?? 'waves';
}

ThemeData buildLight() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.cream50,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.orange500,
      primary: AppColors.orange600,
      secondary: AppColors.navy900,
      surface: Colors.white,
      brightness: Brightness.light,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.navy950,
      foregroundColor: AppColors.cream50,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.navy950,
      indicatorColor: AppColors.orange600.withOpacity(0.25),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? AppColors.orange500 : AppColors.cream50.withOpacity(0.8))),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 11.5,
          color: states.contains(WidgetState.selected) ? AppColors.gold : AppColors.cream50.withOpacity(0.75))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.navy900,
      contentTextStyle: TextStyle(color: AppColors.cream50),
      behavior: SnackBarBehavior.floating,
    ),
    // Consistent, comfortable input boxes on every screen & platform
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.navy800.withOpacity(0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.navy800.withOpacity(0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.orange500, width: 1.6),
      ),
      labelStyle: TextStyle(color: AppColors.ink500, fontSize: 13.5),
    ),
  );
}

ThemeData buildDark() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.brandNavy,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.orange500,
      primary: AppColors.orange500,
      secondary: AppColors.gold,
      surface: AppColors.navy900,
      brightness: Brightness.dark,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.navy950,
      foregroundColor: AppColors.cream50,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.navy950,
      indicatorColor: AppColors.orange600.withOpacity(0.25),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? AppColors.orange500 : AppColors.cream50.withOpacity(0.8))),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 11.5,
          color: states.contains(WidgetState.selected) ? AppColors.gold : AppColors.cream50.withOpacity(0.75))),
    ),
    cardTheme: CardThemeData(color: AppColors.navy900),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.orange600,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      filled: true,
      fillColor: AppColors.navy800.withOpacity(0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.cream50.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.cream50.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.orange500, width: 1.6),
      ),
      labelStyle: TextStyle(color: AppColors.cream50.withOpacity(0.75), fontSize: 13.5),
    ),
  );
}

// ------------------------------------------------------------
// Root
// ------------------------------------------------------------
class LamalivaApp extends StatefulWidget {
  const LamalivaApp({super.key});
  static _LamalivaAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_LamalivaAppState>()!;

  @override
  State<LamalivaApp> createState() => _LamalivaAppState();
}

class _LamalivaAppState extends State<LamalivaApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.light;
  String _styleId = 'royal';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppFx.load();
    _loadTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Battery: freeze every ambient animation while the app is not visible.
    AppFx.appPaused.value =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode') ?? 'light';
    final style = prefs.getString('style_id') ?? 'royal';
    LuxTheme.apply(style); // palette must be live before first build
    if (!mounted) return;
    setState(() {
      _styleId = style;
      _themeMode =
          mode == 'dark' ? ThemeMode.dark : mode == 'system' ? ThemeMode.system : ThemeMode.light;
    });
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode',
        mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.system ? 'system' : 'light');
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  Future<void> setStyle(String id) async {
    LuxTheme.apply(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('style_id', id);
    if (!mounted) return;
    setState(() => _styleId = id);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La-Maliva Vista',
      debugShowCheckedModeBanner: false,
      theme: buildLight(),
      darkTheme: buildDark(),
      themeMode: _themeMode,
      home: const SplashGate(),
    );
  }
}

/// Enhanced splash → permissions (first launch) → Home
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  late final Animation<double> _badgeScale =
      CurvedAnimation(parent: _ctl, curve: const Interval(0.0, 0.55, curve: Curves.elasticOut));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctl, curve: const Interval(0.35, 0.9, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandNavy,
      body: WavyBackground(
        dark: true,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Glowing rotating ring + badge
              ScaleTransition(
                scale: _badgeScale,
                child: SizedBox(
                  width: 132,
                  height: 132,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 132,
                      height: 132,
                      child: RotationTransition(
                        turns: _fade,
                        child: CircularProgressIndicator(
                          color: AppColors.gold,
                          strokeWidth: 1.6,
                          value: 0.78,
                        ),
                      ),
                    ),
                    Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.orange500.withOpacity(0.4),
                              blurRadius: 46,
                              spreadRadius: 6),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset('assets/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.hotel, size: 48, color: AppColors.gold)),
                      ),
                    ),
                  ]),
                ),
              ),
              SizedBox(height: 26),
              FadeTransition(
                opacity: _fade,
                child: Column(children: [
                  Text('LA-MALIVA VISTA',
                      style: TextStyle(
                          color: AppColors.cream50,
                          fontSize: 21,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 7),
                  Text('A  T A S T E  O F  P A R A D I S E',
                      style: TextStyle(color: AppColors.gold, fontSize: 10, letterSpacing: 3)),
                  SizedBox(height: 40),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                        color: AppColors.orange500,
                        backgroundColor: AppColors.navy800,
                        minHeight: 2.6,
                        borderRadius: BorderRadius.all(Radius.circular(3))),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _boot() async {
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1900)),
      SessionService.instance.bootstrap(),
    ]);
    if (!mounted) return;
    await _askPermissionsOnce();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 420),
      ),
    );
    // Warm caches in the background (rooms, menu, features, hotel info)
    RoomRepository.instance.refresh().catchError((_) => <Room>[]);
    SnackbarRepository.instance.refresh().catchError((_) {});
    SessionService.instance.refreshFeatures().catchError((_) {});
  }

  Future<void> _askPermissionsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('perms_asked') == true) return;
    await prefs.setBool('perms_asked', true);
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
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: android,
          iOS: ios,
          windows: windows,
        ),
      );
      _ready = true;
    } catch (_) {}
  }

  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> notify(String title, String body) async {
    NotificationFeed.instance.addLocal(title, body);
    if (!_ready) return;
    final details = NotificationDetails(
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
      await _plugin.show(id: DateTime.now().millisecondsSinceEpoch % 100000,
          title: title, body: body, notificationDetails: details);
    } catch (_) {}
  }

  Future<void> welcome() => notify(
      'Welcome to La-Maliva Vista', 'Rooms are cached for offline use. Karibu!');
}

// ------------------------------------------------------------
// Notification feed — everything shown to the user is kept here:
// developer-team posts + hotel admin announcements (server) and
// local alerts (bookings, syncs, updates). Powers the bell page.
// ------------------------------------------------------------
class FeedItem {
  final String title;
  final String body;
  final DateTime at;
  final String source; // 'team' | 'admin' | 'app'
  FeedItem({required this.title, required this.body, required this.at, required this.source});

  Map<String, dynamic> toMap() => {'title': title, 'body': body, 'at': at.toIso8601String(), 'source': source};
  factory FeedItem.fromMap(Map<String, dynamic> m) => FeedItem(
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      at: DateTime.tryParse((m['at'] ?? '').toString()) ?? DateTime.now(),
      source: (m['source'] ?? 'app').toString());
}

class NotificationFeed {
  NotificationFeed._();
  static final NotificationFeed instance = NotificationFeed._();

  static const _key = 'notif_feed_v1';
  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  final List<FeedItem> _items = [];
  DateTime? _lastServerFetch;

  List<FeedItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _items
          ..clear()
          ..addAll(((jsonDecode(raw) as List).cast<Map<String, dynamic>>())
              .map(FeedItem.fromMap));
      } catch (_) {}
    }
    _recount();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key,
        jsonEncode(_items.take(120).map((e) => e.toMap()).toList()));
  }

  void _recount() {
    // "Unread" = items from the last 48h window the feed was opened since.
    final since = _lastServerFetch ?? DateTime.now().subtract(const Duration(hours: 48));
    unread.value = _items.where((i) => i.at.isAfter(since)).length;
  }

  Future<void> markAllRead() async {
    _lastServerFetch = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_last_read', _lastServerFetch!.toIso8601String());
    _recount();
  }

  Future<void> _lastReadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('notif_last_read');
    if (raw != null) _lastServerFetch = DateTime.tryParse(raw);
  }

  void addLocal(String title, String body) {
    _items.insert(0, FeedItem(title: title, body: body, at: DateTime.now(), source: 'app'));
    _persist();
    _recount();
  }

  /// Pull developer-team + admin announcements from the website backend.
  Future<void> refreshFromServer() async {
    await _lastReadFromPrefs();
    try {
      final res = await Api.get('/api/announcements');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final posts = (data['announcements'] as List? ?? []).cast<Map<String, dynamic>>();
      var added = false;
      for (final p in posts) {
        final title = '[La-Maliva] ${p['title']}';
        if (_items.any((i) => i.title == title && i.source != 'app')) continue;
        _items.insert(0, FeedItem(
            title: title,
            body: (p['body'] ?? '').toString(),
            at: DateTime.tryParse((p['created_at'] ?? '').toString()) ?? DateTime.now(),
            source: 'admin'));
        added = true;
      }
      // Developer-team standing welcome note (always at the top of the inbox)
      const teamTitle = 'Welcome from the La-Maliva team';
      const teamBody =
          'Thanks for using the official La-Maliva Vista app. Book rooms, view your receipts and reach reception — even offline. Karibu!';
      _items.removeWhere((i) => i.title == teamTitle);
      _items.insert(0, FeedItem(
          title: teamTitle,
          body: teamBody,
          at: DateTime.now().subtract(const Duration(hours: 30)),
          source: 'team'));
      await _persist();
      _recount();
      if (added) {
        await NotificationService.instance.notify(
            'New from La-Maliva', 'New announcements are waiting in your inbox.');
      }
    } catch (_) {/* offline — keep the cached feed */}
  }
}

// ------------------------------------------------------------
// App updates — Check for updates (Account page) + silent startup check.
// Compares against /api/version; downloads the matching bundle for this
// platform and pings the user when a newer build is available.
// ------------------------------------------------------------
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final ValueNotifier<String> status = ValueNotifier<String>('');
  /// Newest version available (null = up to date). The app shell listens to
  /// this and shows the proactive update banner before the user ever checks.
  final ValueNotifier<String?> latest = ValueNotifier<String?>(null);

  /// Returns the newest version string if an update is available, else null.
  Future<String?> check({bool notifyIfUpToDate = false}) async {
    try {
      status.value = 'Checking…';
      final res = await Api.get('/api/version').timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw 'x';
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newest = (data['version'] ?? '').toString();
      final newer = _isNewer(newest, kAppVersion);
      status.value = '';
      if (newer) {
        latest.value = newest;
        await NotificationFeed.instance.addLocalIfNew(
            'Update available — v$newest',
            'La-Maliva v$newest is ready. Open Account → Check for updates to install.');
        await NotificationService.instance.notify('La-Maliva update v$newest',
            'A newer app version is available. Tap Account → Check for updates.');
        return newest;
      }
      latest.value = null;
      if (notifyIfUpToDate) {
        await NotificationFeed.instance.addLocalIfNew(
            'You are up to date', 'La-Maliva v$kAppVersion is the latest version.');
      }
      return null;
    } catch (_) {
      status.value = '';
      return null;
    }
  }

  /// Semantic-ish comparison: 2.3.0 > 2.2.10.
  bool _isNewer(String candidate, String current) {
    List<int> parse(String v) => v
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final a = parse(candidate);
    final b = parse(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Opens the exact download for this platform from the website.
  Future<void> downloadLatest(BuildContext context) async {
    final url = Platform.isWindows
        ? '$kBaseUrl/downloads/windows'
        : '$kBaseUrl/downloads/android';
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Download started — install it when it finishes')));
    }
  }
}

extension UpdateFeedExtras on NotificationFeed {
  Future<void> addLocalIfNew(String title, String body) async {
    if (items.any((i) => i.title == title)) return;
    addLocal(title, body);
  }
}

// ------------------------------------------------------------
// Changelog — "What's new" entries served by the website backend,
// cached on-device so the screen also opens offline.
// ------------------------------------------------------------
class ChangelogEntry {
  final String version;
  final String date;
  final List<String> highlights;
  final List<String> notes;
  ChangelogEntry({
    required this.version,
    required this.date,
    required this.highlights,
    required this.notes,
  });

  factory ChangelogEntry.fromMap(Map<String, dynamic> m) => ChangelogEntry(
        version: (m['version'] ?? '').toString(),
        date: (m['date'] ?? '').toString(),
        highlights: ((m['highlights'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        notes: ((m['notes'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  Map<String, dynamic> toMap() => {
        'version': version,
        'date': date,
        'highlights': highlights,
        'notes': notes,
      };
}

class ChangelogRepository {
  ChangelogRepository._();
  static final ChangelogRepository instance = ChangelogRepository._();

  static const _cacheKey = 'changelog_cache_v1';
  final ValueNotifier<List<ChangelogEntry>> entries =
      ValueNotifier<List<ChangelogEntry>>([]);
  bool _loaded = false;

  /// Cached entries immediately; server refresh when online.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        entries.value = ((jsonDecode(raw) as List)
                .cast<Map<String, dynamic>>())
            .map(ChangelogEntry.fromMap)
            .toList();
      } catch (_) {}
    }
    refresh();
  }

  Future<void> refresh() async {
    try {
      final res = await Api.get('/api/changelog');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = ((data['changelog'] as List?) ?? const [])
          .map((e) => ChangelogEntry.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
      if (list.isEmpty) return;
      entries.value = list;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey,
          jsonEncode(list.map((e) => e.toMap()).toList()));
    } catch (_) {
      // offline — cached entries stay available
    }
  }

  /// Notes for a specific version (used by the update banner / update tile).
  ChangelogEntry? forVersion(String v) {
    for (final e in entries.value) {
      if (e.version == v) return e;
    }
    return null;
  }
}

// ------------------------------------------------------------
// API core — every call talks to the WEBSITE backend
// ------------------------------------------------------------
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool needsMfa; // server demands a TOTP code — prompt and retry
  ApiException(this.message, {this.statusCode, this.needsMfa = false});
  @override
  String toString() => message;
}

class Api {
  static Future<http.Response> get(String path, {bool auth = false}) async {
    final headers = <String, String>{};
    if (auth && SessionService.instance.token != null) {
      headers['Authorization'] = 'Bearer ${SessionService.instance.token}';
    }
    final res = await http
        .get(Uri.parse('$kBaseUrl$path'), headers: headers)
        .timeout(const Duration(seconds: 15));
    return res;
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth && SessionService.instance.token != null) {
      headers['Authorization'] = 'Bearer ${SessionService.instance.token}';
    }
    final res = await http
        .post(Uri.parse('$kBaseUrl$path'), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }

  static Future<http.Response> postRaw(String path, Map<String, String> fields,
      {XFile? file, bool auth = false}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl$path'));
    fields.forEach((k, v) => req.fields[k] = v);
    if (auth && SessionService.instance.token != null) {
      req.headers['Authorization'] = 'Bearer ${SessionService.instance.token}';
    }
    if (file != null) {
      req.files.add(await http.MultipartFile.fromPath('image', file.path));
    }
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    return await http.Response.fromStream(streamed);
  }
}

// ------------------------------------------------------------
// Connectivity — real internet detection (Wi-Fi/mobile data may be on
// but the hotel API can be unreachable), probe + auto-retry + broadcast
// ------------------------------------------------------------
class NetService {
  NetService._();
  static final NetService instance = NetService._();

  final ValueNotifier<bool> online = ValueNotifier<bool>(true);
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  Stream<bool> get onChange => _changes.stream;
  Timer? _retry;
  int _failures = 0;
  bool _probing = false;

  /// Cheap reachability check against the hotel backend's health endpoint.
  Future<bool> probe() async {
    if (_probing) return online.value;
    _probing = true;
    try {
      final res = await http
          .get(Uri.parse('$kBaseUrl/api/health'))
          .timeout(const Duration(seconds: 8));
      _setOnline(res.statusCode < 500);
    } catch (_) {
      _setOnline(false);
    } finally {
      _probing = false;
    }
    return online.value;
  }

  void noteSuccess() => _setOnline(true);

  void noteFailure() {
    _failures++;
    if (_failures >= 2 && !online.value) return;
    if (_failures >= 2) {
      _setOnline(false);
      _startRetry();
    }
  }

  void _setOnline(bool value) {
    if (value) {
      _failures = 0;
      _retry?.cancel();
      _retry = null;
    }
    if (online.value != value) {
      online.value = value;
      _changes.add(value);
      if (!value) _startRetry();
    }
  }

  /// Auto-retry every 12s while offline so the app re-syncs on its own
  /// the moment the network returns (no user action needed).
  void _startRetry() {
    if (_retry != null) return;
    _retry = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (await probe()) _retry?.cancel();
    });
  }

  void dispose() {
    _retry?.cancel();
    _changes.close();
  }
}

/// Blanket HTTP + response-error interceptor: routes through [NetService]
/// so every screen knows the true connectivity state.
mixin NetAware {
  Future<http.Response> netGet(String path, {bool auth = false}) async {
    try {
      final res = await Api.get(path, auth: auth);
      NetService.instance.noteSuccess();
      return res;
    } catch (_) {
      NetService.instance.noteFailure();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> netPost(String path, Map<String, dynamic> body,
      {bool auth = false}) async {
    try {
      final data = await Api.post(path, body, auth: auth);
      NetService.instance.noteSuccess();
      return data;
    } catch (_) {
      NetService.instance.noteFailure();
      rethrow;
    }
  }
}

/// Battery & performance gate for all ambient effects.
///
/// • When the app is backgrounded, every looping animation freezes (the OS
///   would otherwise keep painting frames — the #1 hidden battery drain).
/// • 'Battery saver' (Settings → Battery saver) drops ambient motion
///   entirely while keeping the static gradient look.
/// • Respects the OS 'remove animations' accessibility setting too.
class AppFx {
  AppFx._();
  static final ValueNotifier<bool> appPaused = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> batterySaver = ValueNotifier<bool>(false);
  static bool _osReduceMotion = false;
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      batterySaver.value = prefs.getBool('battery_saver') ?? false;
      _osReduceMotion = WidgetsBinding
          .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    } catch (_) {}
  }

  static void setBatterySaver(bool on) {
    batterySaver.value = on;
    SharedPreferences.getInstance().then((p) => p.setBool('battery_saver', on));
  }

  /// True → ambient controllers should stand still.
  static bool get still =>
      appPaused.value || batterySaver.value || _osReduceMotion;

  /// Save-helpers used by the account page toggle.
  static bool get saverOn => batterySaver.value;
}

/// Ambient animated brand background — the motion style follows the active
/// design pack: Royal=waves, Sunset=embers, Emerald=petals, Plum=orbs,
/// Ocean=bubbles, Noir=streaks. Battery-aware: freezes when backgrounded
/// or when Battery saver is on.
class WavyBackground extends StatefulWidget {
  final Widget? child;
  final bool dark; // navy variant (headers/splash) vs cream variant
  const WavyBackground({super.key, this.child, this.dark = true});

  @override
  State<WavyBackground> createState() => _WavyBackgroundState();
}

class _WavyBackgroundState extends State<WavyBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    AppFx.appPaused.addListener(_syncMotion);
    AppFx.batterySaver.addListener(_syncMotion);
    _syncMotion();
  }

  void _syncMotion() {
    if (AppFx.still) {
      _ctl.stop(canceled: false);
    } else if (!_ctl.isAnimating) {
      _ctl.repeat();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppFx.appPaused.removeListener(_syncMotion);
    AppFx.batterySaver.removeListener(_syncMotion);
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.dark ? AppColors.brandNavy : AppColors.cream50;
    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: base)),
      Positioned.fill(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.55, end: 1.0).animate(_ctl),
          child: AnimatedBuilder(
            animation: _ctl,
            builder: (context, _) => CustomPaint(
              painter: _AmbientPainter(
                phase: _ctl.value * 2 * math.pi,
                dark: widget.dark,
                variant: LuxTheme.ambient,
              ),
            ),
          ),
        ),
      ),
      if (widget.child != null) widget.child!,
    ]);
  }
}

class _AmbientPainter extends CustomPainter {
  final double phase;
  final bool dark;
  final String variant;
  _AmbientPainter({required this.phase, required this.dark, required this.variant});

  List<Color> get _tones => dark
      ? [AppColors.navy800, AppColors.orange600, AppColors.gold]
      : [const Color(0xFFE8DFC9), AppColors.orange500, const Color(0xFFDCE6F5)];

  @override
  void paint(Canvas canvas, Size size) {
    switch (variant) {
      case 'embers': _paintParticles(canvas, size, rising: true, big: false); break;
      case 'bubbles': _paintParticles(canvas, size, rising: true, big: true); break;
      case 'petals': _paintPetals(canvas, size); break;
      case 'orbs': _paintOrbs(canvas, size); break;
      case 'streaks': _paintStreaks(canvas, size); break;
      default: _paintWaves(canvas, size);
    }
  }

  void _paintWaves(Canvas canvas, Size size) {
    final tones = _tones;
    for (var i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = tones[i].withOpacity(dark ? 0.16 : 0.22)
        ..style = PaintingStyle.fill;
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 14) {
        final y = size.height * (0.62 + 0.09 * i) +
            (18 + 7.0 * i) *
                math.sin(x / (110 + 34.0 * i) + phase + i * 2.1) +
            10 * math.sin(x / 47 + phase * 1.7);
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _paintParticles(Canvas canvas, Size size,
      {required bool rising, required bool big}) {
    final tones = _tones;
    final count = big ? 12 : 22;
    final rnd = math.Random(7);
    for (var i = 0; i < count; i++) {
      final seedX = rnd.nextDouble();
      final speed = 0.15 + rnd.nextDouble() * 0.5;
      final radius = big ? 10 + rnd.nextDouble() * 22 : 1.6 + rnd.nextDouble() * 4.2;
      final drift = math.sin(phase + i * 1.7) * (big ? 26 : 12);
      final travel = (phase / (2 * math.pi)) * size.height * speed;
      final y = rising
          ? size.height + 40 - ((travel + seedX * size.height) % (size.height + 80))
          : (seedX * size.height + travel) % (size.height + 40) - 20;
      final x = seedX * size.width + drift;
      final tone = tones[i % tones.length];
      final paint = Paint()
        ..style = big ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = big ? 1.4 : 0;
      if (big) {
        paint.color = tone.withOpacity(dark ? 0.14 : 0.20);
        canvas.drawCircle(Offset(x % (size.width + 40) - 20, y), radius, paint);
      } else {
        paint.color = tone.withOpacity(dark ? 0.20 : 0.30);
        canvas.drawCircle(Offset(x % (size.width + 30) - 15, y), radius, paint);
      }
    }
  }

  void _paintPetals(Canvas canvas, Size size) {
    final tones = _tones;
    final rnd = math.Random(21);
    for (var i = 0; i < 14; i++) {
      final seedX = rnd.nextDouble();
      final speed = 0.10 + rnd.nextDouble() * 0.35;
      final r = 5 + rnd.nextDouble() * 9;
      final travel = (phase / (2 * math.pi)) * size.height * speed;
      final y = (seedX * size.height + travel) % (size.height + 60) - 30;
      final x = seedX * size.width + math.sin(phase * 0.8 + i) * 34;
      final paint = Paint()
        ..color = tones[i % tones.length].withOpacity(dark ? 0.16 : 0.24)
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(x % (size.width + 50) - 25, y);
      canvas.rotate(phase + i);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 2, height: r), paint);
      canvas.restore();
    }
  }

  void _paintOrbs(Canvas canvas, Size size) {
    final tones = _tones;
    final rnd = math.Random(11);
    for (var i = 0; i < 7; i++) {
      final cx = rnd.nextDouble() * size.width;
      final cy = rnd.nextDouble() * size.height;
      final r = 60 + rnd.nextDouble() * 110;
      final wobble = math.sin(phase + i * 1.3) * 18;
      final tone = tones[i % tones.length];
      final paint = Paint()
        ..shader = ui.Gradient.radial(
            Offset(cx + wobble, cy + wobble * 0.6), r,
            [tone.withOpacity(dark ? 0.13 : 0.18), tone.withOpacity(0.0)])
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(cx + wobble, cy + wobble * 0.6), r, paint);
    }
  }

  void _paintStreaks(Canvas canvas, Size size) {
    final tones = _tones;
    for (var i = 0; i < 9; i++) {
      final y = size.height * (0.08 + 0.11 * i) + math.sin(phase + i * 1.9) * 14;
      final paint = Paint()
        ..shader = ui.Gradient.linear(
            Offset(-40, y), Offset(size.width * 0.7, y + 26),
            [tones[i % tones.length].withOpacity(dark ? 0.16 : 0.22), tones[i % tones.length].withOpacity(0.0)])
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(-40, y)
        ..quadraticBezierTo(size.width * 0.35, y - 30, size.width * 0.75, y + 8)
        ..lineTo(size.width * 0.75, y + 16)
        ..quadraticBezierTo(size.width * 0.35, y - 18, -40, y + 12)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.variant != variant || oldDelegate.dark != dark;
}

// ------------------------------------------------------------
// Models
// ------------------------------------------------------------
class Room {
  final int id;
  final String number;
  final String type;
  final double price;
  final String? description;
  final String? imageUrl;
  final String status;

  Room({
    required this.id,
    required this.number,
    required this.type,
    required this.price,
    this.description,
    this.imageUrl,
    this.status = 'Available',
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: (j['id'] as num).toInt(),
        number: (j['room_number'] ?? '').toString(),
        type: (j['room_type'] ?? '').toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        description: j['description'] as String?,
        imageUrl: j['image_url'] as String?,
        status: (j['status'] ?? 'Available').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'room_number': number,
        'room_type': type,
        'price': price,
        'description': description,
        'image_url': imageUrl,
        'status': status,
      };
}

class SnackItem {
  final int id;
  final String name;
  final String category;
  final double price;
  final String? imageUrl;

  SnackItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.imageUrl,
  });

  factory SnackItem.fromJson(Map<String, dynamic> j) => SnackItem(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '').toString(),
        category: (j['category'] ?? 'Drinks').toString(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        imageUrl: j['image_url'] as String?,
      );
}

class Booking {
  final int id;
  final String? room;
  final String? roomType;
  final String checkIn;
  final String checkOut;
  final String status;
  final double amount;
  final String? guestName;

  Booking({
    required this.id,
    this.room,
    this.roomType,
    required this.checkIn,
    required this.checkOut,
    required this.status,
    required this.amount,
    this.guestName,
  });

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: (j['id'] as num).toInt(),
        room: j['room']?.toString(),
        roomType: j['room_type']?.toString(),
        checkIn: (j['check_in'] ?? '').toString(),
        checkOut: (j['check_out'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        guestName: j['guest_name']?.toString(),
      );
}

class UserProfile {
  final int id;
  final String username;
  final String email;
  final String role;
  final bool mustChangePassword;
  final bool mustEnrollMfa;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.mustChangePassword = false,
    this.mustEnrollMfa = false,
  });

  bool get isStaff => role == 'staff' || role == 'admin';
  bool get isAdmin => role == 'admin';

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: (j['id'] as num).toInt(),
        username: (j['username'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        role: (j['role'] ?? 'user').toString(),
        mustChangePassword: j['must_change_password'] == true,
        mustEnrollMfa: j['must_enroll_mfa'] == true,
      );
}

class Features {
  final String hotelName;
  final String hotelAddress;
  final String mapsUrl;
  final bool paymentsActive;
  final bool snackbarActive;
  final String version;

  Features({
    this.hotelName = 'LA-MALIVA VISTA HOTEL',
    this.hotelAddress = 'Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon',
    this.mapsUrl = 'https://www.google.com/maps/search/?api=1&query=Fako+Heart+Entrance+GRA+Bokwaongo+Buea+Cameroon',
    this.paymentsActive = false,
    this.snackbarActive = false,
    this.version = kAppVersion,
  });

  factory Features.fromJson(Map<String, dynamic> j) => Features(
        hotelName: ((j['hotel'] ?? const {})['name'] ?? 'LA-MALIVA VISTA HOTEL').toString(),
        hotelAddress: ((j['hotel'] ?? const {})['address'] ?? '').toString(),
        mapsUrl: ((j['hotel'] ?? const {})['maps_url'] as String?)?.isNotEmpty == true
            ? (j['hotel']['maps_url'] as String)
            : 'https://www.google.com/maps/search/?api=1&query=Fako+Heart+Entrance+GRA+Bokwaongo+Buea+Cameroon',
        paymentsActive: j['payments_active'] == true,
        snackbarActive: j['snackbar_active'] == true,
        version: (j['version'] ?? kAppVersion).toString(),
      );
}

// ------------------------------------------------------------
// Session — auth + features, persisted for offline-aware startup
// ------------------------------------------------------------
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  String? token;
  UserProfile? user;
  Features features = Features();

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('api_token');
    final cachedFeatures = prefs.getString('features_cache');
    if (cachedFeatures != null) {
      try {
        features = Features.fromJson(jsonDecode(cachedFeatures) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (token != null) {
      try {
        final res = await Api.get('/api/auth/me', auth: true);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          user = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
        } else {
          await _clearToken();
        }
      } catch (_) {/* offline: keep remembered session */}
    }
  }

  Future<void> refreshFeatures() async {
    try {
      final res = await Api.get('/api/features');
      if (res.statusCode == 200) {
        features = Features.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('features_cache', jsonEncode({
          'hotel': {
            'name': features.hotelName,
            'address': features.hotelAddress,
            'maps_url': features.mapsUrl,
          },
          'payments_active': features.paymentsActive,
          'snackbar_active': features.snackbarActive,
          'version': features.version,
        }));
      }
    } catch (_) {/* keep cached */}
  }

  /// Sign in. Throws [ApiException] with `needsMfa` set when the account
  /// requires a TOTP code — retry with [otp] filled in.
  Future<UserProfile> login(String identifier, String password, {String? otp}) async {
    final data = await Api.post('/api/auth/login', {
      'username': identifier,
      'password': password,
      if (otp != null) 'otp': otp,
    });
    if (data['ok'] != true) {
      if (data['needs_mfa'] == true) {
        throw ApiException((data['error'] ?? 'MFA code required').toString(), needsMfa: true);
      }
      throw ApiException((data['error'] ?? 'Login failed').toString());
    }
    token = data['token'] as String?;
    user = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_token', token!);
    await refreshFeatures();
    return user!;
  }

  Future<void> changePassword(String currentPw, String newPw) async {
    final data = await Api.post('/api/auth/change-password', {
      'current_password': currentPw,
      'new_password': newPw,
    }, auth: true);
    if (data['ok'] != true) {
      throw ApiException((data['error'] ?? 'Could not change password').toString());
    }
    user = UserProfile(
        id: user!.id, username: user!.username, email: user!.email, role: user!.role);
  }

  Future<void> logout() async {
    try {
      await Api.post('/api/auth/logout', {}, auth: true);
    } catch (_) {}
    await _clearToken();
  }

  Future<void> _clearToken() async {
    token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_token');
  }

  void updateToggles({bool? payments, bool? snackbar}) {
    features = Features(
      hotelName: features.hotelName,
      hotelAddress: features.hotelAddress,
      mapsUrl: features.mapsUrl,
      paymentsActive: payments ?? features.paymentsActive,
      snackbarActive: snackbar ?? features.snackbarActive,
      version: features.version,
    );
  }
}

// ------------------------------------------------------------
// Repositories with offline caches
// ------------------------------------------------------------
class RoomRepository {
  RoomRepository._();
  static final RoomRepository instance = RoomRepository._();

  static const _cacheKey = 'rooms_cache_v2';
  List<Room> rooms = [];
  bool fromCache = false;

  Future<List<Room>> load() async {
    if (rooms.isNotEmpty) return rooms;
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
      final res = await Api.get('/api/public-rooms');
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        rooms = list.map(Room.fromJson).toList();
        fromCache = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _cacheKey, jsonEncode(rooms.map((r) => r.toMap()).toList()));
        NetService.instance.noteSuccess();
      }
    } catch (_) {
      fromCache = true;
      NetService.instance.noteFailure();
    }
    return rooms;
  }
}

class SnackbarRepository {
  SnackbarRepository._();
  static final SnackbarRepository instance = SnackbarRepository._();

  static const _cacheKey = 'snackbar_cache_v1';
  List<SnackItem> items = [];
  bool active = false;
  bool fromCache = false;

  Future<void> load() async {
    if (items.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        active = data['active'] == true;
        items = ((data['items'] ?? []) as List)
            .cast<Map<String, dynamic>>()
            .map(SnackItem.fromJson)
            .toList();
        fromCache = true;
      } catch (_) {}
    }
  }

  Future<void> refresh() async {
    try {
      final res = await Api.get('/api/snackbar');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        active = data['active'] == true;
        items = ((data['items'] ?? []) as List)
            .cast<Map<String, dynamic>>()
            .map(SnackItem.fromJson)
            .toList();
        fromCache = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode({
          'active': active,
          'items': items
              .map((i) => {
                    'id': i.id,
                    'name': i.name,
                    'category': i.category,
                    'price': i.price,
                    'image_url': i.imageUrl,
                  })
              .toList(),
        }));
        NetService.instance.noteSuccess();
      }
    } catch (_) {
      fromCache = true;
      NetService.instance.noteFailure();
    }
  }
}

/// A guest registered by staff while the office is offline.
class OfflineRegistration {
  final int id;
  final String name;
  final String phone;
  final String email;
  final String roomLabel;
  final int nights;
  final double rate;
  final String createdAt;

  OfflineRegistration({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.roomLabel,
    required this.nights,
    required this.rate,
    required this.createdAt,
  });

  double get total => rate * nights;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'room_label': roomLabel,
        'nights': nights,
        'rate': rate,
        'created_at': createdAt,
      };

  factory OfflineRegistration.fromMap(Map<String, dynamic> m) => OfflineRegistration(
        id: (m['id'] as num).toInt(),
        name: (m['name'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        email: (m['email'] ?? '').toString(),
        roomLabel: (m['room_label'] ?? '').toString(),
        nights: (m['nights'] as num?)?.toInt() ?? 1,
        rate: (m['rate'] as num?)?.toDouble() ?? 0,
        createdAt: (m['created_at'] ?? '').toString(),
      );
}

class OfflineRegStore {
  OfflineRegStore._();
  static final OfflineRegStore instance = OfflineRegStore._();
  static const _key = 'offline_regs_v1';

  Future<List<OfflineRegistration>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return ((jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          .map(OfflineRegistration.fromMap)
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(OfflineRegistration reg) async {
    final prefs = await SharedPreferences.getInstance();
    final list = ((jsonDecode(prefs.getString(_key) ?? '[]') as List).cast<Map<String, dynamic>>());
    list.add(reg.toMap());
    await prefs.setString(_key, jsonEncode(list));
  }

  Future<void> remove(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = ((jsonDecode(prefs.getString(_key) ?? '[]') as List).cast<Map<String, dynamic>>())
        .where((m) => (m['id'] as num).toInt() != id)
        .toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}

// ------------------------------------------------------------
// Invoice PDF (works offline — pure Dart)
// ------------------------------------------------------------
class Invoice {
  static Future<Uint8List> build({
    required String guestName,
    required String phone,
    required String email,
    required String roomLabel,
    required int nights,
    required double rate,
    required String reference,
    required String issuedOn,
  }) async {
    final hotel = SessionService.instance.features;
    final total = rate * nights;
    final navy = PdfColor.fromHex('#08123A');
    final orange = PdfColor.fromHex('#D97A2B');
    final cream = PdfColor.fromHex('#F8F1E4');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ------- Brand masthead band -------
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: pw.BoxDecoration(
                color: navy,
                borderRadius: const pw.BorderRadius.only(
                  bottomLeft: pw.Radius.circular(14),
                  bottomRight: pw.Radius.circular(14),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('LA-MALIVA VISTA HOTEL',
                        style: pw.TextStyle(fontSize: 18.5, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white, letterSpacing: 1.1)),
                    pw.SizedBox(height: 2),
                    pw.Text('A TASTE OF PARADISE · BUEA, CAMEROON',
                        style: pw.TextStyle(fontSize: 8.2, color: PdfColor.fromHex('#EEC37A'),
                            letterSpacing: 2.2)),
                  ]),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: pw.BoxDecoration(
                      color: orange,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
                    ),
                    child: pw.Text('INVOICE',
                        style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white, letterSpacing: 1.4)),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            // ------- Guest / meta grid -------
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: pw.Container(
                padding: const pw.EdgeInsets.all(13),
                decoration: pw.BoxDecoration(
                    color: cream, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('BILLED TO', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700, letterSpacing: 1.6)),
                  pw.SizedBox(height: 5),
                  pw.Text(guestName, style: pw.TextStyle(fontSize: 14.5, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  pw.Text('Phone: $phone', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                  pw.Text('Email: ${email.isEmpty ? "—" : email}',
                      style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                ]),
              )),
              pw.SizedBox(width: 12),
              pw.Expanded(child: pw.Container(
                padding: const pw.EdgeInsets.all(13),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('INVOICE DETAILS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700, letterSpacing: 1.6)),
                  pw.SizedBox(height: 5),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Reference', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                      pw.Text(reference, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ]),
                  pw.SizedBox(height: 3),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Issued', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                      pw.Text(issuedOn, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ]),
                  pw.SizedBox(height: 3),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Stay', style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
                      pw.Text('$nights night${nights > 1 ? 's' : ''}',
                          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ]),
                ]),
              )),
            ]),
            pw.SizedBox(height: 18),
            // ------- Line items table -------
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5,
                  color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: navy,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              headerPadding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#FBF7EE')),
              headers: ['Description', 'Qty', 'Rate (FCFA)', 'Amount (FCFA)'],
              data: [
                ['Room: $roomLabel', '$nights night${nights > 1 ? 's' : ''}',
                    rate.toStringAsFixed(0), total.toStringAsFixed(0)],
              ],
            ),
            pw.SizedBox(height: 16),
            // ------- Total band -------
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 250,
                padding: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                decoration: pw.BoxDecoration(
                  color: cream,
                  border: pw.Border.all(color: orange, width: 1.1),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text('FCFA ${total.toStringAsFixed(0)}', style: const pw.TextStyle(fontSize: 10)),
                  ]),
                  pw.SizedBox(height: 5),
                  pw.Divider(color: PdfColors.grey300, thickness: 0.7, height: 1),
                  pw.SizedBox(height: 5),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('TOTAL DUE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11,
                          color: navy, letterSpacing: 0.8)),
                      pw.Text('FCFA ${total.toStringAsFixed(0)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15, color: orange)),
                  ]),
                ]),
              ),
            ),
            pw.Spacer(),
            // ------- Footer -------
            pw.Divider(color: navy, thickness: 1.1),
            pw.SizedBox(height: 7),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(hotel.hotelAddress, style: const pw.TextStyle(fontSize: 8.6, color: PdfColors.grey700)),
                pw.Text('Reception: (+237) 679-915-967',
                    style: const pw.TextStyle(fontSize: 8.6, color: PdfColors.grey700)),
              ]),
              pw.Text('Thank you for choosing La-Maliva Vista Hotel!',
                  style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 9, color: navy)),
            ]),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static Future<void> print(Uint8List bytes, String name) async {
    try {
      await Printing.layoutPdf(onLayout: (_) => bytes, name: name);
    } catch (_) {
      await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
    }
  }

  /// Download: saves the PDF to the device (Android Downloads via share sheet,
  /// Windows via the save dialog). Never needs a printer.
  static Future<void> download(Uint8List bytes, String name, BuildContext context) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invoice saved — $name.pdf')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save the invoice')));
      }
    }
  }
}

// ------------------------------------------------------------
// Home shell — bottom nav + slide drawer
// ------------------------------------------------------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ValueNotifier<int> _tab = ValueNotifier<int>(0);
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<bool>? _netSub;
  String? _updateDismissed; // hides the update banner for this version until a new one ships

  @override
  void initState() {
    super.initState();
    // Real connectivity awareness from the first frame
    NetService.instance.probe();
    // Cached notification feed immediately; server feed when online
    NotificationFeed.instance.load();
    NotificationFeed.instance.refreshFromServer();
    // Release notes (cached; refreshed from the website when online)
    ChangelogRepository.instance.load();
    // Silent update check (notifies only when a newer build exists)
    UpdateService.instance.check();
    // When internet returns: refresh everything + sync offline bookings
    _netSub = NetService.instance.onChange.listen((onlineNow) {
      if (!mounted) return;
      if (onlineNow) {
        RoomRepository.instance.refresh();
        SnackbarRepository.instance.refresh();
        SessionService.instance.refreshFeatures();
        NotificationFeed.instance.refreshFromServer();
        _syncOfflineRegistrations();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Back online — everything synced 🔄'),
            duration: Duration(seconds: 2)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No internet — showing cached hotel data'),
            duration: Duration(seconds: 2)));
      }
    });
  }

  Future<void> _syncOfflineRegistrations() async {
    final regs = await OfflineRegStore.instance.all();
    if (regs.isEmpty) return;
    try {
      final data = await Api.post('/api/sync-offline-registrations', {
        'registrations': regs.map((r) => r.toMap()).toList(),
      });
      if (data['ok'] == true) {
        for (final reg in regs) {
          await OfflineRegStore.instance.remove(reg.id);
        }
        await NotificationService.instance.notify('Offline registrations synced',
            '${data['synced']} guest record(s) uploaded to the hotel database.');
      }
    } catch (_) {
      // still offline — retried automatically the next time internet returns
    }
  }

  @override
  void dispose() {
    _netSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      const RoomsPage(),
      const MyBookingsPage(),
      const SnackbarPage(),
      const AccountPage(),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 900; // Windows EXE: multi-panel
      final shell = Column(children: [
        // Proactive update banner — appears by itself when a newer version
        // exists (startup check already ran). One tap → straight to download.
        ValueListenableBuilder<String?>(
          valueListenable: UpdateService.instance.latest,
          builder: (context, newest, _) {
            if (newest == null || newest == _updateDismissed) {
              return const SizedBox.shrink();
            }
            return Material(
              color: AppColors.navy800,
              child: InkWell(
                onTap: () => UpdateService.instance.downloadLatest(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                  child: Row(children: [
                    Icon(Icons.system_update_alt, size: 16, color: AppColors.gold),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Text('La-Maliva v$newest is available — tap to update',
                            style: TextStyle(fontSize: 12.5, color: AppColors.cream50,
                                fontWeight: FontWeight.w600))),
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ChangelogPage())),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.info_outline, size: 16, color: AppColors.gold),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _updateDismissed = newest),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close, size: 15, color: AppColors.cream50),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
        // Live connectivity banner (amber = offline, pulse = back online)
        ValueListenableBuilder<bool>(
          valueListenable: NetService.instance.online,
          builder: (context, isOnline, _) {
            if (isOnline) return const SizedBox.shrink();
            return Material(
              color: AppColors.gold.withOpacity(0.25),
              child: InkWell(
                onTap: () => NetService.instance.probe(),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 7, horizontal: 16),
                  child: Row(children: [
                    Icon(Icons.wifi_off, size: 15, color: AppColors.navy900),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('No internet — offline mode active. Tap to retry.',
                            style: TextStyle(fontSize: 12, color: AppColors.navy900,
                                fontWeight: FontWeight.w600))),
                    SizedBox(width: 8),
                    SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.8,
                            color: AppColors.orange600)),
                  ]),
                ),
              ),
            );
          },
        ),
        // Smooth fade+slide page switching (synced with bottom nav / rail)
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: _tab,
            builder: (context, tab, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.014), end: Offset.zero)
                      .animate(anim),
                  child: child,
                ),
              ),
              // LayoutBuilder keeps every page filling the shell while animating
              child: KeyedSubtree(
                key: ValueKey<int>(tab),
                child: pages[tab],
              ),
            ),
          ),
        ),
      ]);

      if (desktop) {
        // ============ WINDOWS / DESKTOP: side rail + wide panels ============
        return Scaffold(
          key: _scaffoldKey,
          drawer: const AppDrawer(),
          body: Row(children: [
            Material(
              color: AppColors.navy950,
              child: SizedBox(
                width: 92,
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 6),
                    child: Column(children: [
                      // THE single menu button — top-left, beside the logo
                      IconButton(
                        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                        icon: Icon(Icons.menu, color: AppColors.cream50),
                        tooltip: 'Menu',
                      ),
                      const SizedBox(height: 4),
                      ClipOval(
                        child: Image.asset('assets/logo.png', width: 34, height: 34,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(Icons.hotel, color: AppColors.gold)),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _tab,
                      builder: (context, tab, _) => NavigationRail(
                        selectedIndex: tab,
                        onDestinationSelected: (i) => _tab.value = i,
                        backgroundColor: Colors.transparent,
                        indicatorColor: AppColors.orange600.withOpacity(0.25),
                        selectedIconTheme: IconThemeData(color: AppColors.orange500),
                        unselectedIconTheme: IconThemeData(color: AppColors.cream50.withOpacity(0.8)),
                        selectedLabelTextStyle: TextStyle(color: AppColors.gold, fontSize: 11.5),
                        unselectedLabelTextStyle: TextStyle(color: AppColors.cream50.withOpacity(0.75), fontSize: 11),
                        labelType: NavigationRailLabelType.all,
                        leading: const SizedBox(height: 8),
                        destinations: const [
                          NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: Text('Home')),
                          NavigationRailDestination(icon: Icon(Icons.king_bed_outlined), selectedIcon: Icon(Icons.king_bed), label: Text('Rooms')),
                          NavigationRailDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: Text('Bookings')),
                          NavigationRailDestination(icon: Icon(Icons.local_bar_outlined), selectedIcon: Icon(Icons.local_bar), label: Text('Snackbar')),
                          NavigationRailDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text('Account')),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: AppColors.navy800),
            Expanded(child: shell),
          ]),
        );
      }

      // ============ ANDROID / PHONE: top bar + bottom nav ============
      return Scaffold(
        key: _scaffoldKey,
        drawer: const AppDrawer(),
        body: shell,
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: _tab,
          builder: (context, tab, _) => NavigationBar(
            height: 66,
            selectedIndex: tab,
            onDestinationSelected: (i) => _tab.value = i,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.king_bed_outlined), selectedIcon: Icon(Icons.king_bed), label: 'Rooms'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Bookings'),
              NavigationDestination(icon: Icon(Icons.local_bar_outlined), selectedIcon: Icon(Icons.local_bar), label: 'Snackbar'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
            ],
          ),
        ),
      );
    });
  }

  /// Opens the shell's slide-in menu. Pages live in their OWN Scaffolds, so
  /// `Scaffold.of(context)` from inside a page finds the page's scaffold
  /// (which has no drawer) — always go through the shell instead.
  void openMenu(BuildContext context) {
    _scaffoldKey.currentState?.openDrawer();
  }
}

// ------------------------------------------------------------
// Drawer — everything the user asked for, role aware
// ------------------------------------------------------------
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance;
    final user = session.user;
    return Drawer(
      backgroundColor: AppColors.brandNavy,
      child: SafeArea(
        child: ListView(padding: EdgeInsets.zero, children: [
          // Logo header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            child: Column(children: [
              CircleAvatar(
                backgroundImage: AssetImage('assets/logo.png'),
                radius: 34,
                backgroundColor: AppColors.navy900,
              ),
              SizedBox(height: 10),
              Text('LA-MALIVA VISTA',
                  style: TextStyle(color: AppColors.cream50, letterSpacing: 4, fontSize: 15,
                      fontWeight: FontWeight.w600)),
              Text('A TASTE OF PARADISE',
                  style: TextStyle(color: AppColors.gold, fontSize: 8.5, letterSpacing: 2.4)),
              const SizedBox(height: 8),
              if (user != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.orange600.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.orange600.withOpacity(0.5)),
                  ),
                  child: Text('${user.username} · ${user.role.toUpperCase()}',
                      style: TextStyle(color: AppColors.gold, fontSize: 11,
                          letterSpacing: 1)),
                ),
            ]),
          ),
          Divider(color: AppColors.navy800),

          _drawerTile(context, Icons.home_outlined, 'Home', () =>
              _nav(context, 0)),
          _drawerTile(context, Icons.king_bed_outlined, 'Rooms & booking', () =>
              _nav(context, 1)),
          _drawerTile(context, Icons.receipt_long_outlined, 'Booked rooms & receipts', () =>
              _nav(context, 2)),
          _drawerTile(context, Icons.local_bar_outlined, 'Snackbar / restaurant menu', () =>
              _nav(context, 3)),
          _drawerTile(context, Icons.credit_card, 'Payment options', () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsPage()));
          }),
          _drawerTile(context, Icons.dark_mode_outlined, 'Change app theme', () {
            Navigator.pop(context);
            _themeSheet(context);
          }),
          _drawerTile(context, Icons.person_outline, 'Account', () => _nav(context, 4)),

          if (user != null && user.isStaff) ...[
            Divider(color: AppColors.navy800),
            Padding(padding: EdgeInsets.only(left: 20, top: 6, bottom: 6),
                child: Text('STAFF & ADMIN', style: TextStyle(color: AppColors.gold,
                    fontSize: 10.5, letterSpacing: 2))),
            _drawerTile(context, Icons.insert_chart_outlined, 'Live overview', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffHomePage()));
            }),
            _drawerTile(context, Icons.event_available_outlined, 'Reservations & check-in', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffReservationsPage()));
            }),
            _drawerTile(context, Icons.fact_check_outlined, 'Offline guest register & invoices', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OfflineRegisterPage()));
            }),
            _drawerTile(context, Icons.edit_note_outlined, 'Snackbar manager', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SnackbarManagerPage()));
            }),
          ],
          if (user != null && user.isAdmin) ...[
            _drawerTile(context, Icons.admin_panel_settings_outlined, 'Administration tools', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage()));
            }),
          ],

          Divider(color: AppColors.navy800),
          if (user == null)
            _drawerTile(context, Icons.login, 'Sign in', () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            }, accent: true)
          else
            _drawerTile(context, Icons.logout, 'Logout', () async {
              await SessionService.instance.logout();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out')));
              }
            }, danger: true),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('la-maliva-vista-hotel.onrender.com\nBuea · Cameroon · v$kAppVersion',
                style: TextStyle(color: AppColors.navy800, fontSize: 10.5, height: 1.6)),
          ),
        ]),
      ),
    );
  }

  void _nav(BuildContext context, int tab) {
    Navigator.pop(context);
    context.findAncestorStateOfType<_HomeShellState>()?._tab.value = tab;
  }

  void _themeSheet(BuildContext context) {
    final appState = LamalivaApp.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Design style', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Re-skins the whole app — waves, cards, nav bar.',
                style: TextStyle(color: AppColors.ink500, fontSize: 12.5)),
            const SizedBox(height: 10),
            ...LuxTheme.meta.map((m) {
              final p = LuxTheme.palettes[m['id']!]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () { appState.setStyle(m['id']!); Navigator.pop(ctx); },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.navy900.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: appState._styleId == m['id'] ? AppColors.orange500 : Colors.transparent,
                          width: 1.6),
                    ),
                    child: Row(children: [
                      // palette swatch
                      Container(width: 42, height: 42, decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(11),
                        color: p['navy950'],
                      ),
                        padding: const EdgeInsets.all(3),
                        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            CircleAvatar(radius: 5.5, backgroundColor: p['navy800']),
                            CircleAvatar(radius: 5.5, backgroundColor: p['orange500']),
                          ]),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            CircleAvatar(radius: 5.5, backgroundColor: p['gold']),
                            CircleAvatar(radius: 5.5, backgroundColor: p['cream50']),
                          ]),
                        ])),
                      const SizedBox(width: 13),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['name']!, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                        Text(m['tag']!, style: TextStyle(color: AppColors.ink500, fontSize: 12)),
                      ])),
                      if (appState._styleId == m['id']!) Icon(Icons.check_circle, color: AppColors.orange500),
                    ]),
                  ),
                ),
              );
            }),
            const Divider(height: 26),
            const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            RadioListTile<ThemeMode>(
              value: ThemeMode.light, groupValue: appState._themeMode,
              title: const Text('Light'), onChanged: (m) { appState.setThemeMode(m!); Navigator.pop(ctx); }),
            RadioListTile<ThemeMode>(
              value: ThemeMode.dark, groupValue: appState._themeMode,
              title: const Text('Dark'), onChanged: (m) { appState.setThemeMode(m!); Navigator.pop(ctx); }),
            RadioListTile<ThemeMode>(
              value: ThemeMode.system, groupValue: appState._themeMode,
              title: const Text('Follow system'), onChanged: (m) { appState.setThemeMode(m!); Navigator.pop(ctx); }),
          ]),
        ),
      ),
    );
  }

  Widget _drawerTile(BuildContext context, IconData icon, String label, VoidCallback onTap,
      {bool accent = false, bool danger = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: ListTile(
        leading: Icon(icon, color: danger ? Colors.redAccent : accent ? AppColors.orange500 : AppColors.cream50.withOpacity(0.85)),
        title: Text(label, style: TextStyle(
            color: danger ? Colors.redAccent : accent ? AppColors.orange500 : AppColors.cream50.withOpacity(0.92),
            fontSize: 14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
      ),
    );
  }
}

// ------------------------------------------------------------
// Home page — hero, quick menu chips below the logo, featured rooms
// ------------------------------------------------------------
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final rooms = RoomRepository.instance.rooms.take(3).toList();
    final feats = SessionService.instance.features;
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => context
                .findAncestorStateOfType<_HomeShellState>()
                ?.openMenu(ctx),
          ),
        ),
        title: Row(children: const [
          CircleAvatar(backgroundImage: AssetImage('assets/logo.png'), radius: 16),
          SizedBox(width: 10),
          Text('La-Maliva Vista', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          // Bell → real notification inbox (developer team + hotel admin + app alerts)
          ValueListenableBuilder<int>(
            valueListenable: NotificationFeed.instance.unread,
            builder: (context, count, _) => Stack(children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const NotificationsPage()));
                },
              ),
              if (count > 0)
                Positioned(
                  right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: AppColors.orange600, shape: BoxShape.circle),
                    child: Text('$count',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
        ],
      ),
      body: WavyBackground(
        dark: false,
        child: RefreshIndicator(
        onRefresh: () async {
          await RoomRepository.instance.refresh();
          await SessionService.instance.refreshFeatures();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _Hero(),
            const SizedBox(height: 16),
            // Quick options — the slide-menu shortcut row below the logo/hero
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _quick(context, Icons.receipt_long, 'Receipts', const MyBookingsPage()),
                  _quick(context, Icons.credit_card, 'Payments', const PaymentsPage()),
                  _quick(context, Icons.local_bar, 'Snackbar', const SnackbarPage()),
                  _quick(context, Icons.place_outlined, 'Location', null,
                      onTapUrl: SessionService.instance.features.mapsUrl),
                  _quick(context, Icons.support_agent, 'Call us', null,
                      onTapUrl: 'tel:+237679915967'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Featured rooms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              TextButton(onPressed: () {
                context.findAncestorStateOfType<_HomeShellState>()?._tab.value = 1;
              }, child: Text('See all')),
            ]),
            if (rooms.isEmpty)
              Container(
                padding: EdgeInsets.all(28),
                decoration: _cardDeco(context),
                child: Center(child: Text('Rooms load as soon as you are online',
                    style: TextStyle(color: AppColors.ink500))),
              )
            else
              ...rooms.map((r) => _RoomCard(room: r, onBook: () => _openBooking(context, r))),
            SizedBox(height: 18),
            Container(
              padding: EdgeInsets.all(18),
              decoration: _cardDeco(context),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Find us', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 6),
                Text(feats.hotelAddress,
                    style: TextStyle(color: AppColors.ink500, fontSize: 12.5, height: 1.5)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(kBaseUrl), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.language, size: 16),
                  label: const Text('Open website'),
                ),
              ]),
            ),
          ],
        ),
      ),
      ),
    );
  }

  BoxDecoration _cardDeco(BuildContext context) => BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.navy950.withOpacity(0.07), blurRadius: 16, offset: Offset(0, 7))],
      );

  Widget _quick(BuildContext context, IconData icon, String label, Widget? page,
      {String? onTapUrl}) {
    return Container(
      width: 84,
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (page != null) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => page));
            } else if (onTapUrl != null) {
              launchUrl(Uri.parse(onTapUrl),
                  mode: onTapUrl.startsWith('http')
                      ? LaunchMode.externalApplication
                      : LaunchMode.platformDefault);
            }
          },
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: AppColors.orange500.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: AppColors.orange600, size: 21),
            ),
            const SizedBox(height: 7),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

Future<void> _openBooking(BuildContext context, Room room) async {
  // Guests: reservation is online-only. Staff/admin get the office tool
  // instead, which also works offline (queued + synced later).
  final user = SessionService.instance.user;
  final isStaff = user != null && user.isStaff;
  if (!NetService.instance.online.value && !isStaff) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Reservations need internet. Please reconnect to book.'),
        backgroundColor: AppColors.orange600));
    return;
  }
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => BookingSheet(room: room),
  );
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy950, AppColors.navy800],
        ),
        boxShadow: [BoxShadow(color: AppColors.navy950.withOpacity(0.35), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A TASTE OF PARADISE', style: TextStyle(color: AppColors.gold, fontSize: 10, letterSpacing: 4)),
          const SizedBox(height: 10),
          const Text('Where paradise\nfeels like home.',
              style: TextStyle(color: Colors.white, fontSize: 26, height: 1.2, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Row(children: [
            ElevatedButton(
              onPressed: () {
                context.findAncestorStateOfType<_HomeShellState>()?._tab.value = 1;
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange500,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: Text('RESERVE NOW', style: TextStyle(letterSpacing: 1.5, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: 10),
          ]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// Rooms page + booking sheet (live API booking)
// ------------------------------------------------------------
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key});
  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await RoomRepository.instance.load();
    if (mounted) setState(() => _loading = false);
    await RoomRepository.instance.refresh();
    if (mounted) setState(() => _offline = RoomRepository.instance.fromCache);
  }

  @override
  Widget build(BuildContext context) {
    final rooms = RoomRepository.instance.rooms;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: const [
          CircleAvatar(backgroundImage: AssetImage('assets/logo.png'), radius: 16),
          SizedBox(width: 10),
          Text('Rooms & Suites', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await RoomRepository.instance.refresh();
          if (mounted) setState(() => _offline = RoomRepository.instance.fromCache);
        },
        child: CustomScrollView(
          slivers: [
            if (_offline)
              SliverToBoxAdapter(child: _offlineBanner('Cached rooms & rates — booking syncs when online')),
            if (_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: AppColors.orange500)),
              )
            else if (rooms.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No rooms available right now', style: TextStyle(color: AppColors.ink500))),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _RoomCard(room: rooms[i], onBook: () => _openBooking(context, rooms[i])),
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

Widget _offlineBanner(String text) => Container(
      color: AppColors.gold.withOpacity(0.22),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(children: [
        Icon(Icons.wifi_off, size: 15, color: AppColors.navy900),
        SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.navy900))),
      ]),
    );

class _RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onBook;
  const _RoomCard({required this.room, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final available = room.status == 'Available';
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.navy950.withOpacity(0.08), blurRadius: 20, offset: Offset(0, 8))],
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
              // (fallback shows the bundled default room photo)
              Positioned(
                top: 10, left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(999)),
                  child: Text('ROOM ${room.number}',
                      style: TextStyle(fontSize: 9, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: AppColors.navy900)),
                ),
              ),
              if (!available)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                    child: const Center(
                      child: Text('NOT AVAILABLE', style: TextStyle(color: Colors.white, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
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
                  style: TextStyle(color: AppColors.ink500, fontSize: 12.5, height: 1.5)),
              SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                RichText(text: TextSpan(children: [
                  TextSpan(text: 'FCFA ', style: TextStyle(color: AppColors.orange600, fontSize: 10, fontWeight: FontWeight.w700)),
                  TextSpan(text: room.price.toStringAsFixed(0), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
                  TextSpan(text: ' / night', style: TextStyle(color: AppColors.ink500, fontSize: 11)),
                ])),
                ElevatedButton(
                  onPressed: available ? onBook : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy900,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: Text(available ? 'RESERVE' : 'FULL', style: const TextStyle(fontSize: 11, letterSpacing: 1.2)),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  /// Bundled default room photo — always available, even fully offline,
  /// so room cards never show an empty grey box.
  Widget _imgFallback() {
    final img = room.type.toLowerCase().contains('deluxe') || room.type.toLowerCase().contains('suite')
        ? 'assets/room_deluxe.jpg'
        : 'assets/room_default.jpg';
    return Image.asset(img, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
              color: AppColors.cream100,
              child: Center(child: Icon(Icons.hotel, size: 44, color: AppColors.orange500)),
            ));
  }
}

class BookingSheet extends StatefulWidget {
  final Room room;
  const BookingSheet({super.key, required this.room});

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  DateTime _in = DateTime.now().add(const Duration(days: 1));
  DateTime _out = DateTime.now().add(const Duration(days: 3));
  bool _busy = false;
  String? _error;

  /// Guest reservations are ONLINE-ONLY — real-time availability in the
  /// database means an offline booking could double-book a room.
  bool get _online => NetService.instance.online.value;
  StreamSubscription<bool>? _netSub;

  @override
  void initState() {
    super.initState();
    // Re-enable/disable the whole form the moment connectivity changes
    _netSub = NetService.instance.onChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _netSub?.cancel();
    super.dispose();
  }

  int get _nights => _out.difference(_in).inDays < 1 ? 1 : _out.difference(_in).inDays;
  double get _total => _nights * widget.room.price;

  Future<void> _pickDate(bool isCheckIn) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn ? _in : _out,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _in = picked;
        if (!_out.isAfter(_in)) _out = _in.add(const Duration(days: 2));
      } else if (picked.isAfter(_in)) {
        _out = picked;
      }
    });
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final user = SessionService.instance.user;
      final data = await Api.post('/api/book', {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim().isNotEmpty
            ? _email.text.trim()
            : (user?.email ?? ''),
        'room_id': widget.room.id,
        'check_in': '${_in.year}-${_in.month.toString().padLeft(2, '0')}-${_in.day.toString().padLeft(2, '0')}',
        'check_out': '${_out.year}-${_out.month.toString().padLeft(2, '0')}-${_out.day.toString().padLeft(2, '0')}',
      });
      if (data['ok'] == true) {
        await NotificationService.instance.notify('Booking confirmed 🎉',
            'Room ${widget.room.number} · ${_nights} night(s) · FCFA ${_total.toStringAsFixed(0)}');
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text((data['message'] ?? 'Booking confirmed!').toString())));
        }
      } else {
        setState(() => _error = (data['error'] ?? 'Booking failed').toString());
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No connection — booking needs internet. Staff can register you offline.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Reserve Room ${widget.room.number}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          Text('${widget.room.type} · FCFA ${widget.room.price.toStringAsFixed(0)} / night',
              style: TextStyle(color: AppColors.ink500)),
          const SizedBox(height: 18),
          // ONLINE-ONLY notice: shown whenever the sheet opens without internet
          ValueListenableBuilder<bool>(
            valueListenable: NetService.instance.online,
            builder: (context, online, _) => online
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.gold.withOpacity(0.45))),
                    child: Row(children: [
                      Icon(Icons.wifi_off, size: 18, color: AppColors.orange600),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('Reservations need internet (live room availability). '
                              'You are offline — please reconnect to book.',
                              style: const TextStyle(fontSize: 12, height: 1.45)))]),
                  ),
          ),
          TextField(controller: _name, enabled: _online, decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _phone, enabled: _online, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (e.g. 679…)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _email, enabled: _online, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional — links receipts to your account)', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _dateTile('Check-in', _in, _online ? () => _pickDate(true) : () {})),
            const SizedBox(width: 10),
            Expanded(child: _dateTile('Check-out', _out, _online ? () => _pickDate(false) : () {})),
          ]),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.cream100, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$_nights night${_nights > 1 ? 's' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('FCFA ${_total.toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.orange600)),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ValueListenableBuilder<bool>(
              valueListenable: NetService.instance.online,
              builder: (context, online, _) => ElevatedButton(
                onPressed: (_busy || !online) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange500,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.ink500.withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(online ? 'CONFIRM BOOKING' : 'OFFLINE — RESERVATION UNAVAILABLE',
                        style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.navy900.withOpacity(0.25)),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.ink500)),
          const SizedBox(height: 3),
          Text('${date.day}/${date.month}/${date.year}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------
// My bookings + receipt (view / print / share invoice)
// ------------------------------------------------------------
class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});
  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  bool _loading = true;
  String? _error;
  List<Booking> _bookings = [];
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    if (SessionService.instance.user == null) {
      setState(() { _loading = false; _error = 'signin'; });
      return;
    }
    try {
      final res = await Api.get('/api/my-bookings', auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _bookings = ((data['bookings'] ?? []) as List)
            .cast<Map<String, dynamic>>()
            .map(Booking.fromJson)
            .toList();
      }
      setState(() => _offline = false);
    } catch (_) {
      setState(() => _offline = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('My Bookings')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.orange500))
          : _error == 'signin'
              ? _SignInPrompt(onSignedIn: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_offline)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _offlineBanner('Receipts need a connection — pull to retry'),
                        ),
                      if (_bookings.isEmpty && !_offline)
                        Container(
                          padding: EdgeInsets.all(30),
                          decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(18)),
                          child: Column(children: [
                            Icon(Icons.receipt_long, size: 42, color: AppColors.orange500),
                            SizedBox(height: 12),
                            Text('No bookings yet', style: TextStyle(fontWeight: FontWeight.w700)),
                            SizedBox(height: 4),
                            Text('Reserve a room and your receipts appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.ink500, fontSize: 12.5)),
                          ]),
                        )
                      else
                        ..._bookings.map((b) => _BookingTile(b: b)),
                    ],
                  ),
                ),
    );
  }
}

class _SignInPrompt extends StatefulWidget {
  final VoidCallback onSignedIn;
  const _SignInPrompt({required this.onSignedIn});
  @override
  State<_SignInPrompt> createState() => _SignInPromptState();
}

class _SignInPromptState extends State<_SignInPrompt> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.lock_outline, size: 44, color: AppColors.orange500),
        SizedBox(height: 14),
        Text('Sign in to see your bookings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        SizedBox(height: 6),
        Text('Same account as the website.',
            style: TextStyle(color: AppColors.ink500, fontSize: 12.5)),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            widget.onSignedIn();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: const Text('SIGN IN'),
        ),
      ]),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Booking b;
  const _BookingTile({required this.b});

  @override
  Widget build(BuildContext context) {
    final statusColor = b.status == 'Checked-In'
        ? Colors.green
        : b.status == 'Checked-Out'
            ? AppColors.ink500
            : b.status == 'Cancelled'
                ? Colors.redAccent
                : AppColors.orange600;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Room ${b.room ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999)),
            child: Text(b.status, style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${b.roomType ?? ''} · FCFA ${b.amount.toStringAsFixed(0)}',
            style: TextStyle(color: AppColors.ink500, fontSize: 12.5)),
        const SizedBox(height: 6),
        Text('Check-in ${_fmt(b.checkIn)}  →  Check-out ${_fmt(b.checkOut)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => _receipt(context),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Receipt'),
          ),
          OutlinedButton.icon(
            onPressed: () => _download(context),
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('Download'),
          ),
          OutlinedButton.icon(
            onPressed: () => _print(context),
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print'),
          ),
        ]),
      ]),
    );
  }

  static String _fmt(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  Future<void> _receipt(BuildContext context) async {
    try {
      final res = await Api.get('/api/booking/${b.id}', auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final bk = data['booking'] as Map<String, dynamic>;
        if (!context.mounted) return;
        showModalBottomSheet(context: context, builder: (ctx) => _ReceiptSheet(bk: bk));
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt needs a connection')));
    }
  }

  /// Nights between check-in and check-out (min 1) for correct invoices.
  static int _nightsOf(Map<String, dynamic> bk) {
    try {
      final ci = DateTime.parse((bk['check_in'] ?? '').toString());
      final co = DateTime.parse((bk['check_out'] ?? '').toString());
      final n = co.difference(ci).inDays;
      return n < 1 ? 1 : n;
    } catch (_) {
      return 1;
    }
  }

  Future<void> _print(BuildContext context) async {
    try {
      final res = await Api.get('/api/booking/${b.id}', auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw 'x';
      final bk = data['booking'] as Map<String, dynamic>;
      final bytes = await Invoice.build(
        guestName: (bk['guest_name'] ?? 'Guest').toString(),
        phone: (bk['guest_phone'] ?? '').toString(),
        email: (bk['guest_email'] ?? '').toString(),
        roomLabel: 'Room ${bk['room']} (${bk['room_type']})',
        nights: _nightsOf(bk),
        rate: (bk['amount'] as num?)?.toDouble() ?? 0,
        reference: 'RES-${bk['id']}',
        issuedOn: _fmt((bk['check_in'] ?? '').toString()),
      );
      await Invoice.print(bytes, 'lamaliva-invoice-${b.id}');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printing needs a connection')));
    }
  }

  Future<void> _download(BuildContext context) async {
    try {
      final res = await Api.get('/api/booking/${b.id}', auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw 'x';
      final bk = data['booking'] as Map<String, dynamic>;
      final bytes = await Invoice.build(
        guestName: (bk['guest_name'] ?? 'Guest').toString(),
        phone: (bk['guest_phone'] ?? '').toString(),
        email: (bk['guest_email'] ?? '').toString(),
        roomLabel: 'Room ${bk['room']} (${bk['room_type']})',
        nights: _nightsOf(bk),
        rate: (bk['amount'] as num?)?.toDouble() ?? 0,
        reference: 'RES-${bk['id']}',
        issuedOn: _fmt((bk['check_in'] ?? '').toString()),
      );
      await Invoice.download(bytes, 'lamaliva-invoice-${b.id}', context);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading needs a connection')));
    }
  }
}

class _ReceiptSheet extends StatelessWidget {
  final Map<String, dynamic> bk;
  const _ReceiptSheet({required this.bk});

  @override
  Widget build(BuildContext context) {
    final hotel = bk['hotel'] as Map<String, dynamic>? ?? const {};
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Booking Receipt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          _row('Reference', 'RES-${bk['id']}'),
          _row('Guest', (bk['guest_name'] ?? '—').toString()),
          _row('Room', 'Room ${bk['room']} · ${bk['room_type']}'),
          _row('Check-in', _short((bk['check_in'] ?? '').toString())),
          _row('Check-out', _short((bk['check_out'] ?? '').toString())),
          _row('Status', (bk['status'] ?? '').toString()),
          _row('Amount', 'FCFA ${(bk['amount'] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}'),
          const Divider(height: 24),
          Text((hotel['name'] ?? '').toString(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text((hotel['address'] ?? '').toString(),
              style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
          Text((hotel['phone'] ?? '').toString(),
              style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
        ]),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(color: AppColors.ink500, fontSize: 12.5)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ]),
      );

  static String _short(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ------------------------------------------------------------
// Snackbar — live menu when admin enables it, else Coming Soon
// ------------------------------------------------------------
class SnackbarPage extends StatefulWidget {
  const SnackbarPage({super.key});
  @override
  State<SnackbarPage> createState() => _SnackbarPageState();
}

class _SnackbarPageState extends State<SnackbarPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await SnackbarRepository.instance.load();
    if (mounted) setState(() => _loading = false);
    await SnackbarRepository.instance.refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repo = SnackbarRepository.instance;
    return Scaffold(
      appBar: AppBar(title: Text('Snackbar & Restaurant')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.orange500))
          : !repo.active
              ? const ComingSoonView(
                  icon: Icons.local_bar,
                  title: 'Snackbar menu is brewing',
                  text: 'Our drinks & dishes menu launches soon. '
                      'The hotel manager flips the switch the moment it is ready.',
                )
              : RefreshIndicator(
                  onRefresh: () => SnackbarRepository.instance.refresh(),
                  child: Builder(builder: (context) {
                    // group by category
                    final cats = <String, List<SnackItem>>{};
                    for (final i in repo.items) {
                      cats.putIfAbsent(i.category, () => []).add(i);
                    }
                    final order = ['Drinks', 'Beer', 'Wine', 'Whisky', 'Meals', 'Snacks'];
                    final keys = cats.keys.toList()
                      ..sort((a, b) {
                        final ia = order.indexOf(a), ib = order.indexOf(b);
                        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
                      });
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (repo.fromCache)
                          Padding(padding: const EdgeInsets.only(bottom: 12),
                              child: _offlineBanner('Cached menu — prices as of last sync')),
                        ...keys.expand((k) => [
                              Padding(padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
                                  child: Text(k.toUpperCase(),
                                      style: TextStyle(letterSpacing: 2.4, fontSize: 12,
                                          fontWeight: FontWeight.w800, color: AppColors.orange600))),
                              ...cats[k]!.map((i) => _SnackTile(item: i)),
                              const SizedBox(height: 8),
                            ]),
                        if (repo.items.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(18)),
                            child: Center(child: Text('Menu is being prepared…',
                                style: TextStyle(color: AppColors.ink500))),
                          ),
                      ],
                    );
                  }),
                ),
    );
  }
}

class _SnackTile extends StatelessWidget {
  final SnackItem item;
  const _SnackTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 54, height: 54,
            child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                ? Image.network(item.imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback())
                : _fallback(),
          ),
        ),
        SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          SizedBox(height: 2),
          Text(item.category, style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
        ])),
        Text('FCFA ${item.price.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.orange600, fontSize: 13.5)),
      ]),
    );
  }

  Widget _fallback() => Container(
      color: AppColors.cream100,
      child: Icon(Icons.local_drink, color: AppColors.orange500));
}

// ------------------------------------------------------------
// Payments — MoMo & bank, gated by the admin toggle
// ------------------------------------------------------------
class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final active = SessionService.instance.features.paymentsActive;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Options')),
      body: !active
          ? const ComingSoonView(
              icon: Icons.credit_card,
              title: 'Mobile Money & Bank payments',
              text: 'MTN MoMo and bank transfer for room bookings arrive soon. '
                  'Until then, pay at the front desk — receipts sync to your account.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _payCard(context,
                    icon: Icons.phone_android,
                    title: 'MTN Mobile Money',
                    subtitle: 'Pay with MoMo to (+237) 679-915-967 — use your booking reference as the reason.'),
                _payCard(context,
                    icon: Icons.account_balance,
                    title: 'Bank Transfer',
                    subtitle: 'Ask reception for the hotel IBAN. Send the receipt to the front desk to confirm.'),
                _payCard(context,
                    icon: Icons.hotel,
                    title: 'Pay at Reception',
                    subtitle: 'Cash or card at check-in. Your room is held for 24h after booking.'),
                const SizedBox(height: 8),
                Center(child: Text('Payments are confirmed by the front desk; your receipt '
                    'updates automatically.', textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.ink500, fontSize: 11.5))),
              ],
            ),
    );
  }

  Widget _payCard(BuildContext context,
      {required IconData icon, required String title, required String subtitle}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: AppColors.orange500.withOpacity(0.13),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: AppColors.orange600),
        ),
        SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: AppColors.ink500, fontSize: 12, height: 1.45)),
        ])),
      ]),
    );
  }
}

// ------------------------------------------------------------
// Coming soon view (shared)
// ------------------------------------------------------------
class ComingSoonView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const ComingSoonView({super.key, required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 86, height: 86,
            decoration: BoxDecoration(
                color: AppColors.orange500.withOpacity(0.12),
                shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: AppColors.orange500),
          ),
          SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink500, fontSize: 13, height: 1.55)),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999)),
            child: Text('COMING SOON',
                style: TextStyle(color: AppColors.orange600, fontSize: 10.5,
                    letterSpacing: 2.4, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------
// Account page
// ------------------------------------------------------------
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _changelogNew = false;

  @override
  void initState() {
    super.initState();
    _checkChangelogNew();
  }

  /// NEW badge until the user opens the latest release notes.
  Future<void> _checkChangelogNew() async {
    await ChangelogRepository.instance.load();
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString('changelog_last_seen');
    final list = ChangelogRepository.instance.entries.value;
    if (!mounted) return;
    setState(() => _changelogNew = list.isNotEmpty && list.first.version != seen);
  }

  Future<void> _openChangelog() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangelogPage()));
    final prefs = await SharedPreferences.getInstance();
    final list = ChangelogRepository.instance.entries.value;
    if (list.isNotEmpty) await prefs.setString('changelog_last_seen', list.first.version);
    if (mounted) setState(() => _changelogNew = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionService.instance.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 8),
        Center(
          child: CircleAvatar(
            backgroundImage: AssetImage('assets/logo.png'),
            radius: 40,
            backgroundColor: AppColors.cream100,
          ),
        ),
        const SizedBox(height: 12),
        Center(
            child: Text(user?.username ?? 'Guest',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
        Center(
            child: Text(
                user != null ? '${user.email} · ${user.role.toUpperCase()}' : 'Not signed in',
                style: TextStyle(color: AppColors.ink500, fontSize: 12))),
        Center(
            child: Text('Native App v$kAppVersion',
                style: TextStyle(color: AppColors.ink500, fontSize: 11))),
        const SizedBox(height: 4),
        Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _openChangelog,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text("What's new in this version",
                    style: TextStyle(
                        color: AppColors.orange600,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios, size: 10, color: AppColors.orange600),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (user == null)
          _SettingsTile(
            icon: Icons.login,
            title: 'Sign in',
            subtitle: 'Same account as the website',
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
              if (mounted) setState(() {});
            },
          )
        else ...[
          if (user.mustChangePassword)
            _SettingsTile(
              icon: Icons.warning_amber_rounded,
              title: 'Change default password',
              subtitle: 'Important: secure your admin account',
              danger: true,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChangePasswordPage())),
            ),
          _SettingsTile(
            icon: Icons.password_outlined,
            title: 'Change password',
            subtitle: 'Update your account password',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChangePasswordPage())),
          ),
          _SettingsTile(
            icon: Icons.logout,
            title: 'Logout',
            subtitle: user.email,
            danger: true,
            onTap: () async {
              await SessionService.instance.logout();
              if (mounted) setState(() {});
            },
          ),
        ],
        const SizedBox(height: 6),
        _SettingsTile(
          icon: Icons.dark_mode_outlined,
          title: 'Change app theme',
          subtitle: 'Light · Dark · System',
          onTap: () => showMenu(
            context: context,
            position: const RelativeRect.fromLTRB(100, 100, 100, 100),
            items: [
              PopupMenuItem(child: const Text('Paradise Light'), onTap: () =>
                  LamalivaApp.of(context).setThemeMode(ThemeMode.light)),
              PopupMenuItem(child: const Text('Ocean Dark'), onTap: () =>
                  LamalivaApp.of(context).setThemeMode(ThemeMode.dark)),
              PopupMenuItem(child: const Text('System'), onTap: () =>
                  LamalivaApp.of(context).setThemeMode(ThemeMode.system)),
            ],
          ),
        ),
        _SettingsTile(
          icon: Icons.battery_saver,
          title: 'Battery saver',
          subtitle: AppFx.saverOn
              ? 'On — background motion paused'
              : 'Off — full animated backgrounds',
          trailing: Switch.adaptive(
            value: AppFx.saverOn,
            activeColor: AppColors.orange500,
            onChanged: (v) {
              AppFx.setBatterySaver(v);
              setState(() {});
            },
          ),
          onTap: () {
            AppFx.setBatterySaver(!AppFx.saverOn);
            setState(() {});
          },
        ),
        _SettingsTile(
          icon: Icons.history_edu,
          title: "What's new",
          subtitle: 'Release notes for every La-Maliva version',
          trailing: _changelogNew
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.orange500,
                      borderRadius: BorderRadius.circular(999)),
                  child: const Text('NEW',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                )
              : null,
          onTap: _openChangelog,
        ),
        _UpdateTile(),
        _SettingsTile(
          icon: Icons.notifications_active_outlined,
          title: 'Notification permission',
          subtitle: 'Re-request booking alerts',
          onTap: () async {
            final granted = await NotificationService.instance.requestPermission();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(granted
                      ? 'Notifications are enabled'
                      : 'Notifications remain disabled — enable them in system settings')));
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
        Center(
            child: Text('© La-Maliva Vista Hotel · Buea, Cameroon',
                style: TextStyle(color: AppColors.ink500, fontSize: 11))),
      ]),
    );
  }
}

// ------------------------------------------------------------
// What's new — in-app changelog timeline (served by the website)
// ------------------------------------------------------------
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  String _prettyDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = isDark ? Colors.white12 : AppColors.navy900.withOpacity(0.08);
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: WavyBackground(
        dark: isDark,
        child: ValueListenableBuilder<List<ChangelogEntry>>(
          valueListenable: ChangelogRepository.instance.entries,
          builder: (context, list, _) {
            if (list.isEmpty) {
              return const Center(
                  child: Text('No release notes yet — pull to refresh soon.',
                      textAlign: TextAlign.center));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final e = list[i];
                final isCurrent = e.version == kAppVersion;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Timeline rail with version dot
                      SizedBox(
                        width: 34,
                        child: Column(children: [
                          Container(
                            width: 16, height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCurrent ? AppColors.orange500 : AppColors.gold,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.orange600.withOpacity(0.35),
                                    blurRadius: 8, spreadRadius: 1),
                              ],
                            ),
                          ),
                          if (i != list.length - 1)
                            Expanded(child: Container(width: 2, color: line)),
                        ]),
                      ),
                      const SizedBox(width: 14),
                      // Card
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 18),
                          child: Material(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(18),
                            elevation: 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {},
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text('v${e.version}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16.5)),
                                      const SizedBox(width: 8),
                                      if (isCurrent)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 3),
                                          decoration: BoxDecoration(
                                              color: AppColors.orange500
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(999)),
                                          child: Text('INSTALLED',
                                              style: TextStyle(
                                                  fontSize: 9,
                                                  letterSpacing: 1.6,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.orange600))),
                                    ]),
                                    const SizedBox(height: 2),
                                    Text(_prettyDate(e.date),
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.ink500)),
                                    if (e.highlights.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: e.highlights
                                            .map((h) => Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                      color: AppColors.gold
                                                          .withOpacity(0.16),
                                                      borderRadius: BorderRadius
                                                          .circular(999)),
                                                  child: Text(h,
                                                      style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: AppColors
                                                              .orange600)),
                                                ))
                                            .toList(),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    ...e.notes.map((n) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 7),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 5),
                                                child: Container(
                                                    width: 5,
                                                    height: 5,
                                                    decoration: BoxDecoration(
                                                        color: AppColors.orange500,
                                                        shape: BoxShape.circle)),
                                              ),
                                              const SizedBox(width: 9),
                                              Expanded(
                                                  child: Text(n,
                                                      style: const TextStyle(
                                                          fontSize: 13,
                                                          height: 1.5))),
                                            ],
                                          ),
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Notifications Center — developer team + hotel admin posts + app alerts
// ------------------------------------------------------------
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await NotificationFeed.instance.refreshFromServer();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = NotificationFeed.instance.items;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: WavyBackground(
        dark: false,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: AppColors.orange500))
            : items.isEmpty
                ? Center(child: Text('No notifications yet',
                    style: TextStyle(color: AppColors.ink500)))
                : RefreshIndicator(
                    onRefresh: NotificationFeed.instance.refreshFromServer,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final n = items[i];
                        final icon = n.source == 'team'
                            ? Icons.verified_outlined
                            : n.source == 'admin'
                                ? Icons.campaign_outlined
                                : Icons.notifications_outlined;
                        final label = n.source == 'team'
                            ? 'LA-MALIVA TEAM'
                            : n.source == 'admin'
                                ? 'HOTEL ADMIN'
                                : 'APP';
                        final color = n.source == 'team'
                            ? AppColors.orange600
                            : n.source == 'admin'
                                ? AppColors.navy900
                                : AppColors.ink500;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 11),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(icon, size: 20, color: color),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(n.title, style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13.5)),
                              const SizedBox(height: 3),
                              Text(n.body, style: TextStyle(
                                  color: AppColors.ink500, fontSize: 12.5, height: 1.4)),
                              const SizedBox(height: 6),
                              Text('$label · ${_feedTime(n.at)}',
                                  style: TextStyle(color: AppColors.ink500, fontSize: 10.5, letterSpacing: 0.4)),
                            ])),
                          ]),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  static String _feedTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}

// ------------------------------------------------------------
// Check-for-updates tile (Account) — only reports/downloads when the
// website backend announces a newer version than this build.
// ------------------------------------------------------------
class _UpdateTile extends StatefulWidget {
  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _checking = false;
  String? _latest;
  bool _upToDate = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final latest = await UpdateService.instance.check(notifyIfUpToDate: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _latest = latest;
      _upToDate = latest == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _checking ? null : _check,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: AppColors.orange500.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: _checking
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2.2,
                            color: AppColors.orange600))
                    : Icon(Icons.system_update_outlined,
                        color: AppColors.navy900),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Check for updates',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(
                  _checking
                      ? 'Contacting the hotel server…'
                      : _latest != null
                          ? 'v$_latest available — tap Download below'
                          : _upToDate
                              ? 'You are on the latest version (v$kAppVersion)'
                              : 'Updates install from the official downloads page',
                  style: TextStyle(color: AppColors.ink500, fontSize: 12),
                ),
              ])),
              if (_latest != null) ...[
                TextButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ChangelogPage())),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: const Text("What's new", style: TextStyle(fontSize: 12)),
                ),
                ElevatedButton(
                  onPressed: () => UpdateService.instance.downloadLatest(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('Download', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final Widget? trailing;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: (danger ? Colors.redAccent : AppColors.navy900).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon,
                    color: danger ? Colors.redAccent : AppColors.navy900),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: danger ? Colors.redAccent : null)),
                SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: AppColors.ink500, fontSize: 12)),
              ])),
              if (trailing != null) trailing!,
              if (trailing == null)
                Icon(Icons.chevron_right, color: AppColors.ink500),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// Login (token auth against the website database)
// ------------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _otp = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _needsMfa = false; // server asked for a TOTP code
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final user = await SessionService.instance.login(
          _id.text.trim(), _pw.text,
          otp: _needsMfa && _otp.text.trim().isNotEmpty ? _otp.text.trim() : null);
      await NotificationService.instance.notify(
          'Welcome back, ${user.username}',
          user.isStaff ? 'Staff tools are unlocked in the menu.' : 'Your bookings are synced.');
      if (mounted) Navigator.pop(context, user);
    } on ApiException catch (e) {
      if (e.needsMfa) {
        setState(() { _needsMfa = true; _error = 'Enter the 8-digit code from your authenticator app.'; });
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      setState(() => _error = 'No connection — sign in needs internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandNavy,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 8),
          Center(
            child: Container(
              width: 92, height: 92,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.orange500.withOpacity(0.35), blurRadius: 36, spreadRadius: 3)]),
              child: ClipOval(child: Image.asset('assets/logo.png', fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.hotel, color: AppColors.gold))),
            ),
          ),
          SizedBox(height: 20),
          Center(child: Text('WELCOME BACK',
              style: TextStyle(color: AppColors.cream50, letterSpacing: 5, fontSize: 16,
                  fontWeight: FontWeight.w600))),
          Center(child: Text('One account for app & website',
              style: TextStyle(color: AppColors.gold, fontSize: 11))),
          const SizedBox(height: 30),
          TextField(
            controller: _id,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Username or email', Icons.person_outline),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pw,
            obscureText: _obscure,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Password', Icons.lock_outline).copyWith(
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.ink500),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_needsMfa) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              maxLength: 8,
              style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 18),
              decoration: _dec('Authenticator code', Icons.phonelink_lock_outlined).copyWith(
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: _busy
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('SIGN IN', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 26),
          Center(child: Text('No account? Sign up on the website.',
              style: TextStyle(color: AppColors.ink500, fontSize: 12))),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('$kBaseUrl/signup'),
                mode: LaunchMode.externalApplication),
            child: Text('Create one at la-maliva-vista-hotel.onrender.com',
                style: TextStyle(color: AppColors.gold, fontSize: 12)),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.ink500),
        prefixIcon: Icon(icon, color: AppColors.orange500),
        filled: true,
        fillColor: AppColors.navy900,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.orange500)),
      );
}

// ------------------------------------------------------------
// Change password
// ------------------------------------------------------------
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_new.text != _confirm.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await SessionService.instance.changePassword(_cur.text, _new.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated')));
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No connection — try again online.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _cur, obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password',
                  border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: _new, obscureText: true,
              decoration: const InputDecoration(labelText: 'New password (8+ characters)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 14),
          TextField(controller: _confirm, obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm new password',
                  border: OutlineInputBorder())),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('UPDATE PASSWORD'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// STAFF: live overview
// ------------------------------------------------------------
class StaffHomePage extends StatefulWidget {
  const StaffHomePage({super.key});
  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends State<StaffHomePage> {
  Map<String, dynamic>? _stats;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.get('/api/staff/overview', auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('staff_stats_cache', res.body);
        if (mounted) setState(() { _stats = data; _offline = false; });
        return;
      }
    } catch (_) {}
    // offline fallback — last snapshot
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('staff_stats_cache');
    if (raw != null && mounted) {
      setState(() { _stats = jsonDecode(raw) as Map<String, dynamic>; _offline = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Live Overview')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_offline) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: _offlineBanner('Last synced snapshot — pull to refresh')),
          if (s == null)
            Padding(padding: EdgeInsets.all(40),
                child: Center(child: Text('Sign in as staff to see live stats',
                    style: TextStyle(color: AppColors.ink500))))
          else ...[
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12, crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _stat(context, Icons.door_front_door_outlined, '${s['total_rooms'] ?? 0}', 'Rooms'),
                _stat(context, Icons.event_busy, '${s['occupied'] ?? 0}', 'Occupied'),
                _stat(context, Icons.event_available, '${s['free'] ?? 0}', 'Free'),
                _stat(context, Icons.percent, s['total_rooms'] == null || (s['total_rooms'] as num) == 0
                    ? '0%'
                    : '${(((s['occupied'] as num? ?? 0).toInt()) / (s['total_rooms'] as num) * 100).toStringAsFixed(0)}%', 'Occupancy'),
                _stat(context, Icons.flight_land, '${s['arrivals_today'] ?? 0}', 'Arrivals today'),
                _stat(context, Icons.flight_takeoff, '${s['departures_today'] ?? 0}', 'Departures today'),
              ],
            ),
          ],
        ]),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String value, String label) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(17)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.orange600, size: 24),
        Spacer(),
        Text(value, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
      ]),
    );
  }
}

// ------------------------------------------------------------
// STAFF: reservations with check-in / check-out
// ------------------------------------------------------------
class StaffReservationsPage extends StatefulWidget {
  const StaffReservationsPage({super.key});
  @override
  State<StaffReservationsPage> createState() => _StaffReservationsPageState();
}

class _StaffReservationsPageState extends State<StaffReservationsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Api.get('/api/staff/reservations', auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _items = ((data['reservations'] ?? []) as List).cast<Map<String, dynamic>>();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('staff_res_cache', res.body);
        _offline = false;
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('staff_res_cache');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _items = ((data['reservations'] ?? []) as List).cast<Map<String, dynamic>>();
        _offline = true;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _act(int id, String action) async {
    try {
      await Api.post('/api/staff/$action/$id', {}, auth: true);
      await NotificationService.instance.notify(
          action == 'checkin' ? 'Checked in ✓' : 'Checked out ✓',
          'Reservation RES-$id updated on the website database.');
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Check-in/out needs a connection')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reservations')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: AppColors.orange500))
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (_offline) Padding(padding: const EdgeInsets.only(bottom: 12),
                    child: _offlineBanner('Offline list — actions need connection')),
                ..._items.map((r) {
                  final status = (r['status'] ?? '').toString();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(15)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('RES-${r['id']} · Room ${r['room']}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        Text(status,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: status == 'Checked-In' ? Colors.green : AppColors.orange600)),
                      ]),
                      const SizedBox(height: 3),
                      Text('${r['guest_name']} · ${r['guest_phone'] ?? ''}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                      Text('FCFA ${(r['amount'] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}'
                          '  ·  ${_short((r['check_in'] ?? '').toString())} → ${_short((r['check_out'] ?? '').toString())}',
                          style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
                      const SizedBox(height: 10),
                      Row(children: [
                        if (status == 'Confirmed')
                          _miniBtn('Check in', Colors.green, () => _act((r['id'] as num).toInt(), 'checkin')),
                        if (status == 'Checked-In')
                          _miniBtn('Check out', Colors.redAccent, () => _act((r['id'] as num).toInt(), 'checkout')),
                      ]),
                    ]),
                  );
                }),
                if (_items.isEmpty)
                  Padding(padding: EdgeInsets.all(40),
                      child: Center(child: Text('No reservations yet',
                          style: TextStyle(color: AppColors.ink500)))),
              ]),
      ),
    );
  }

  static String _short(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}';
    } catch (_) {
      return iso;
    }
  }

  Widget _miniBtn(String label, Color color, VoidCallback onTap) => SizedBox(
        height: 30,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
              backgroundColor: color, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
      );
}

// ------------------------------------------------------------
// STAFF: offline guest register + printable invoices
// ------------------------------------------------------------
class OfflineRegisterPage extends StatefulWidget {
  const OfflineRegisterPage({super.key});
  @override
  State<OfflineRegisterPage> createState() => _OfflineRegisterPageState();
}

class _OfflineRegisterPageState extends State<OfflineRegisterPage> {
  List<OfflineRegistration> _regs = [];
  bool _syncing = false;
  StreamSubscription<bool>? _netSub;

  @override
  void initState() {
    super.initState();
    _reload();
    // Auto-sync pending records the moment internet returns
    _netSub = NetService.instance.onChange.listen((online) {
      if (online) _syncNow(silent: true);
    });
  }

  @override
  void dispose() {
    _netSub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final regs = await OfflineRegStore.instance.all();
    if (mounted) setState(() => _regs = regs);
  }

  /// Push every queued registration into the hotel database right now.
  Future<void> _syncNow({bool silent = false}) async {
    if (_syncing || !NetService.instance.online.value) return;
    setState(() => _syncing = true);
    try {
      final regs = await OfflineRegStore.instance.all();
      if (regs.isEmpty) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nothing to sync — all records are in the database')));
        }
        return;
      }
      final data = await Api.post('/api/sync-offline-registrations', {
        'registrations': regs.map((r) => r.toMap()).toList(),
      });
      if (data['ok'] == true) {
        for (final reg in regs) {
          await OfflineRegStore.instance.remove(reg.id);
        }
        await NotificationService.instance.notify('Registrations synced',
            '${data['synced']} guest record(s) uploaded to the hotel database.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${data['synced']} record(s) uploaded to the database ✓')));
        }
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not reach the server — records stay queued')));
      }
    } finally {
      await _reload();
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openForm() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _OfflineRegForm(),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guest Register')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        ValueListenableBuilder<bool>(
          valueListenable: NetService.instance.online,
          builder: (context, online, _) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: (online ? Colors.green : AppColors.orange600).withOpacity(0.12),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: (online ? Colors.green : AppColors.orange600).withOpacity(0.4))),
            child: Row(children: [
              Icon(online ? Icons.cloud_done : Icons.cloud_off,
                  color: online ? Colors.green : AppColors.orange600),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(online
                      ? 'Online — guest records save directly to the hotel database.'
                      : 'Offline — records are queued on this device and upload to the database automatically when internet returns.',
                      style: const TextStyle(fontSize: 12, height: 1.5))),
            ]),
          ),
        ),
        // Pending-sync queue banner
        ValueListenableBuilder<bool>(
          valueListenable: NetService.instance.online,
          builder: (context, online, _) => FutureBuilder<List<OfflineRegistration>>(
            future: OfflineRegStore.instance.all(),
            builder: (context, snap) {
              final pending = snap.data?.length ?? 0;
              if (pending == 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.gold.withOpacity(0.4))),
                child: Row(children: [
                  Icon(Icons.pending_outlined, size: 18, color: AppColors.orange600),
                  const SizedBox(width: 10),
                  Expanded(child: Text('$pending record(s) waiting to sync',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
                  TextButton(
                    onPressed: (_syncing || !online) ? null : () => _syncNow(),
                    child: _syncing
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sync now', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
              );
            },
          ),
        ),
        SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _openForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          icon: const Icon(Icons.person_add_alt),
          label: Text(NetService.instance.online.value
              ? 'REGISTER GUEST (SAVES TO DATABASE)'
              : 'REGISTER GUEST (OFFLINE QUEUE)'),
        ),
        const SizedBox(height: 18),
        ..._regs.map((r) => Container(
              margin: EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(15)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(r.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text('PENDING SYNC', style: TextStyle(fontSize: 9.5, letterSpacing: 1.4,
                      color: AppColors.orange600, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 3),
                Text('${r.phone} · ${r.email.isEmpty ? "—" : r.email}',
                    style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
                Text('${r.roomLabel} · ${r.nights} night(s) · FCFA ${r.total.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final bytes = await Invoice.build(
                        guestName: r.name, phone: r.phone, email: r.email,
                        roomLabel: r.roomLabel, nights: r.nights, rate: r.rate,
                        reference: 'OFF-REG-${r.id}',
                        issuedOn: r.createdAt,
                      );
                      await Invoice.print(bytes, 'lamaliva-invoice-${r.id}');
                    },
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Print invoice'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final bytes = await Invoice.build(
                        guestName: r.name, phone: r.phone, email: r.email,
                        roomLabel: r.roomLabel, nights: r.nights, rate: r.rate,
                        reference: 'OFF-REG-${r.id}',
                        issuedOn: r.createdAt,
                      );
                      if (!mounted) return;
                      await Invoice.download(bytes, 'lamaliva-invoice-${r.id}', context);
                    },
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Download'),
                  ),
                  IconButton(
                    onPressed: () async {
                      await OfflineRegStore.instance.remove(r.id);
                      _reload();
                    },
                    icon: Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                  ),
                ]),
              ]),
            )),
        if (_regs.isEmpty)
          Padding(padding: EdgeInsets.all(36),
              child: Center(child: Text('No offline registrations yet',
                  style: TextStyle(color: AppColors.ink500)))),
      ]),
    );
  }
}

class _OfflineRegForm extends StatefulWidget {
  const _OfflineRegForm();
  @override
  State<_OfflineRegForm> createState() => _OfflineRegFormState();
}

class _OfflineRegFormState extends State<_OfflineRegForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _room = TextEditingController();
  int _nights = 1;
  double _rate = 15000;
  bool _busy = false;
  String? _error;

  bool get _online => NetService.instance.online.value;

  Future<void> _save() async {
    if ((_name.text.trim().isEmpty) || (_phone.text.trim().isEmpty)) {
      setState(() => _error = 'Guest name and phone are required.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final now = DateTime.now();
    final reg = OfflineRegistration(
      id: now.millisecondsSinceEpoch % 1000000000,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      roomLabel: _room.text.trim().isEmpty ? 'Standard Room' : _room.text.trim(),
      nights: _nights,
      rate: _rate,
      createdAt: '${now.day}/${now.month}/${now.year}',
    );

    if (_online) {
      // ONLINE: write straight into the hotel database (same table the
      // website dashboard reads), then keep a local invoice copy.
      try {
        final data = await Api.post('/api/sync-offline-registrations', {
          'registrations': [reg.toMap()],
        });
        if (data['ok'] == true) {
          String resId = '—';
          final records = data['records'];
          if (records is List && records.isNotEmpty && records.first is Map) {
            resId = ((records.first as Map)['reservation_id'] ?? '—').toString();
          }
          await NotificationService.instance.notify('Guest registered',
              '${reg.name} saved to the hotel database (reservation #$resId).');
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${reg.name} added to the hotel database ✓')));
          }
          return;
        }
        throw (data['error'] ?? 'Server rejected the record').toString();
      } on ApiException catch (e) {
        // Auth/server problem — fall through to the offline queue so the
        // record is never lost; it syncs automatically later.
        await OfflineRegStore.instance.add(reg);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Saved on device (${e.message}) — will sync when back online')));
        }
        return;
      } catch (_) {
        // Connection dropped mid-save — queue it.
        await OfflineRegStore.instance.add(reg);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Connection dropped — saved on device, will sync automatically')));
        }
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    // OFFLINE: queue locally; syncs to the database when internet returns.
    await OfflineRegStore.instance.add(reg);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Saved offline — uploads to the database automatically when back online')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Register guest', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            // Live online/offline chip: tells staff exactly where the record goes
            ValueListenableBuilder<bool>(
              valueListenable: NetService.instance.online,
              builder: (context, online, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: (online ? Colors.green : AppColors.orange600).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(online ? Icons.cloud_done : Icons.cloud_off, size: 13,
                      color: online ? Colors.green : AppColors.orange600),
                  const SizedBox(width: 5),
                  Text(online ? 'ONLINE · saves to database' : 'OFFLINE · queued on device',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800,
                          letterSpacing: 0.4, color: online ? Colors.green : AppColors.orange600)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Guest full name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _room,
              decoration: const InputDecoration(labelText: 'Room (e.g. Room 101 — Deluxe)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              initialValue: _nights,
              decoration: const InputDecoration(labelText: 'Nights', border: OutlineInputBorder()),
              items: [1, 2, 3, 4, 5, 6, 7, 10, 14, 30]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
              onChanged: (v) => setState(() => _nights = v ?? 1),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              keyboardType: TextInputType.number,
              onChanged: (v) => _rate = double.tryParse(v) ?? _rate,
              controller: TextEditingController(text: _rate.toStringAsFixed(0)),
              decoration: InputDecoration(labelText: 'Rate/night FCFA', border: OutlineInputBorder()),
            )),
          ]),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(13),
            decoration: BoxDecoration(color: AppColors.cream100, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Invoice total', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('FCFA ${(_rate * _nights).toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AppColors.orange600)),
            ]),
          ),
          if (_error != null) ...[
            SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ],
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_online ? 'SAVE TO HOTEL DATABASE' : 'SAVE & QUEUE FOR SYNC',
                    style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------
// STAFF/ADMIN: snackbar manager (photo upload from device)
// ------------------------------------------------------------
class SnackbarManagerPage extends StatefulWidget {
  const SnackbarManagerPage({super.key});
  @override
  State<SnackbarManagerPage> createState() => _SnackbarManagerPageState();
}

class _SnackbarManagerPageState extends State<SnackbarManagerPage> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _imageUrl = TextEditingController();
  String _category = 'Drinks';
  XFile? _picked;
  bool _busy = false;

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (x != null) setState(() => _picked = x);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo picker unavailable here — paste an image link instead')));
      }
    }
  }

  Future<void> _upload() async {
    if (_name.text.trim().isEmpty || (double.tryParse(_price.text) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and a positive price are required')));
      return;
    }
    setState(() => _busy = true);
    try {
      final fields = {
        'name': _name.text.trim(),
        'category': _category,
        'price': _price.text.trim(),
      };
      if (_picked == null && _imageUrl.text.trim().isNotEmpty) {
        fields['image_url'] = _imageUrl.text.trim();
      }
      final res = await Api.postRaw('/api/snackbar/items', fields, file: _picked, auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        await NotificationService.instance.notify(
            'Menu updated', '${data['item']['name']} is now on the snackbar menu.');
        _name.clear(); _price.clear(); _imageUrl.clear();
        setState(() => _picked = null);
        await SnackbarRepository.instance.refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Added to the menu')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text((data['error'] ?? 'Upload failed').toString())));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload needs a connection')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Snackbar Manager')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name,
            decoration: const InputDecoration(labelText: 'Item name (e.g. Grilled Chicken)',
                border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
          items: ['Drinks', 'Beer', 'Wine', 'Whisky', 'Meals', 'Snacks']
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _category = v ?? 'Drinks'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _price, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Price (FCFA)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined, size: 17),
            label: Text(_picked == null ? 'Pick photo' : 'Photo ✓'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(controller: _imageUrl,
                decoration: const InputDecoration(labelText: '…or image link',
                    border: OutlineInputBorder(), isDense: true)),
          ),
        ]),
        if (_picked != null) ...[
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_picked!.path), height: 110, width: double.infinity, fit: BoxFit.cover)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _upload,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          child: _busy
              ? SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('PUBLISH TO MENU'),
        ),
        SizedBox(height: 10),
        Center(child: Text('Photos come from this device and upload straight to the website database.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.ink500, fontSize: 11))),
      ]),
    );
  }
}

// ------------------------------------------------------------
// ADMIN: toggles + user management
// ------------------------------------------------------------
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool _payments = false;
  bool _snackbar = false;
  bool _busyToggles = false;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    final f = SessionService.instance.features;
    _payments = f.paymentsActive;
    _snackbar = f.snackbarActive;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final res = await Api.get('/api/admin/users', auth: true);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        if (mounted) setState(() => _users = ((data['users'] ?? []) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _busyToggles = true);
    try {
      final data = await Api.post('/api/admin/toggles', {key: value}, auth: true);
      if (data['ok'] == true) {
        SessionService.instance.updateToggles(
            payments: data['payments_active'] == true,
            snackbar: data['snackbar_active'] == true);
        if (mounted) setState(() {
          _payments = data['payments_active'] == true;
          _snackbar = data['snackbar_active'] == true;
        });
        await NotificationService.instance.notify(
            'Feature switch flipped',
            'Payments: ${_payments ? "ON" : "OFF"} · Snackbar: ${_snackbar ? "ON" : "OFF"} — live on web & app.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Toggling needs a connection')));
      }
    } finally {
      if (mounted) setState(() => _busyToggles = false);
    }
  }

  Future<void> _createStaff() async {
    final ctrl = TextEditingController();
    final email = TextEditingController();
    final pw = TextEditingController();
    String role = 'staff';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: StatefulBuilder(builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Create staff account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(controller: ctrl,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: email,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: pw, obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (8+ chars)', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text('Staff (limited access)')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin (full access)')),
                ],
                onChanged: (v) => setSheet(() => role = v ?? 'staff'),
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('CREATE ACCOUNT'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final data = await Api.post('/api/admin/users', {
        'username': ctrl.text.trim(),
        'email': email.text.trim(),
        'password': pw.text,
        'role': role,
      }, auth: true);
      if (data['ok'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Account ${data['user']['username']} created')));
        _loadUsers();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text((data['error'] ?? 'Failed').toString())));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating accounts needs a connection')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Administration Tools')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        Text('FEATURE SWITCHES', style: TextStyle(letterSpacing: 2.2, fontSize: 11.5,
            fontWeight: FontWeight.w800, color: AppColors.orange600)),
        SizedBox(height: 4),
        Text('Applies to the website and this app instantly.',
            style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
              color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            title: const Text('Activate payment methods', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            subtitle: const Text('MoMo & bank sections open app-wide', style: TextStyle(fontSize: 11.5)),
            value: _payments,
            onChanged: _busyToggles ? null : (v) => _toggle('payments_active', v),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
              color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            title: const Text('Activate snackbar menu', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
            subtitle: const Text('Menu goes live instead of “Coming Soon”', style: TextStyle(fontSize: 11.5)),
            value: _snackbar,
            onChanged: _busyToggles ? null : (v) => _toggle('snackbar_active', v),
          ),
        ),
        SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('USER MANAGEMENT', style: TextStyle(letterSpacing: 2.2, fontSize: 11.5,
              fontWeight: FontWeight.w800, color: AppColors.orange600)),
          TextButton.icon(
            onPressed: _createStaff,
            icon: const Icon(Icons.person_add_alt, size: 16),
            label: const Text('Add staff'),
          ),
        ]),
        ..._users.map((u) => Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(13),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(13)),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: (u['role'] == 'admin' ? AppColors.orange600 : AppColors.navy800).withOpacity(0.18),
                  child: Text((u['username'] ?? '?').toString().substring(0, 1).toUpperCase(),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                          color: u['role'] == 'admin' ? AppColors.orange600 : AppColors.navy900)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${u['username']} · ${u['role']}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  Text((u['email'] ?? '').toString(),
                      style: TextStyle(color: AppColors.ink500, fontSize: 11.5)),
                ])),
                Icon(u['verified'] == true ? Icons.verified_outlined : Icons.hourglass_top,
                    size: 18, color: u['verified'] == true ? Colors.green : AppColors.ink500),
              ]),
            )),
      ]),
    );
  }
}
