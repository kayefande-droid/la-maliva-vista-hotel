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
import 'dart:typed_data';

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
const String kAppVersion = '2.2.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LamalivaApp());
}

// ------------------------------------------------------------
// Theme — luxury navy / burnt orange / cream, light + dark
// ------------------------------------------------------------
class AppColors {
  static const navy950 = Color(0xFF0A1628);
  static const brandNavy = Color(0xFF08123A); // exact badge navy from logo.png
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
  scaffoldBackgroundColor: AppColors.cream50,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.orange500,
    primary: AppColors.orange600,
    secondary: AppColors.navy900,
    surface: Colors.white,
    brightness: Brightness.light,
  ),
  appBarTheme: const AppBarTheme(
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
    contentTextStyle: const TextStyle(color: AppColors.cream50),
    behavior: SnackBarBehavior.floating,
  ),
);

final ThemeData luxuryDark = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.brandNavy,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.orange500,
    primary: AppColors.orange500,
    secondary: AppColors.gold,
    surface: AppColors.navy900,
    brightness: Brightness.dark,
  ),
  appBarTheme: const AppBarTheme(
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
  cardTheme: const CardThemeData(color: AppColors.navy900),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.orange600,
    contentTextStyle: const TextStyle(color: Colors.white),
    behavior: SnackBarBehavior.floating,
  ),
);

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

class _LamalivaAppState extends State<LamalivaApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode') ?? 'light';
    if (!mounted) return;
    setState(() => _themeMode =
        mode == 'dark' ? ThemeMode.dark : mode == 'system' ? ThemeMode.system : ThemeMode.light);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode',
        mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.system ? 'system' : 'light');
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La-Maliva Vista',
      debugShowCheckedModeBanner: false,
      theme: luxuryLight,
      darkTheme: luxuryDark,
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 1.1,
            colors: [Color(0xFF16305C), AppColors.brandNavy],
          ),
        ),
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
                        child: const CircularProgressIndicator(
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
                                const Icon(Icons.hotel, size: 48, color: AppColors.gold)),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 26),
              FadeTransition(
                opacity: _fade,
                child: Column(children: const [
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
      MaterialPageRoute(builder: (_) => const HomeShell()),
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
      await _plugin.show(id: DateTime.now().millisecondsSinceEpoch % 100000,
          title: title, body: body, notificationDetails: details);
    } catch (_) {}
  }

  Future<void> welcome() => notify(
      'Welcome to La-Maliva Vista', 'Rooms are cached for offline use. Karibu!');
}

// ------------------------------------------------------------
// API core — every call talks to the WEBSITE backend
// ------------------------------------------------------------
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
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

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.mustChangePassword = false,
  });

  bool get isStaff => role == 'staff' || role == 'admin';
  bool get isAdmin => role == 'admin';

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: (j['id'] as num).toInt(),
        username: (j['username'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        role: (j['role'] ?? 'user').toString(),
        mustChangePassword: j['must_change_password'] == true,
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

  Future<UserProfile> login(String identifier, String password) async {
    final data = await Api.post('/api/auth/login', {
      'username': identifier,
      'password': password,
    });
    if (data['ok'] != true) {
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
      }
    } catch (_) {
      fromCache = true;
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
      }
    } catch (_) {
      fromCache = true;
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
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.all(36),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('LA-MALIVA VISTA HOTEL',
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#08123A'))),
                    pw.Text('A Taste of Paradise — Buea, Cameroon',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ]),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColor.fromHex('#D97A2B'), width: 1.2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Text('INVOICE',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#D97A2B'))),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(color: PdfColor.fromHex('#08123A'), thickness: 1.4),
              pw.SizedBox(height: 18),
              pw.Text('Billed to', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11,
                  color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(guestName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.Text('Phone: $phone    Email: ${email.isEmpty ? "—" : email}',
                  style: const pw.TextStyle(fontSize: 10.5, color: PdfColors.grey700)),
              pw.SizedBox(height: 22),
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5,
                    color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#08123A')),
                cellStyle: const pw.TextStyle(fontSize: 10.5),
                headers: ['Description', 'Qty', 'Rate (FCFA)', 'Amount (FCFA)'],
                data: [
                  ['Room: $roomLabel', '$nights night${nights > 1 ? 's' : ''}',
                      rate.toStringAsFixed(0), total.toStringAsFixed(0)],
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8F1E4'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('FCFA ${total.toStringAsFixed(0)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14,
                              color: PdfColor.fromHex('#D97A2B'))),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 26),
              pw.Text('Reference: $reference',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.Text('Issued: $issuedOn',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.SizedBox(height: 8),
              pw.Text(hotel.hotelAddress,
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.Text('Reception: (+237) 679-915-967',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.Spacer(),
              pw.Center(
                child: pw.Text('Thank you for choosing La-Maliva Vista Hotel!',
                    style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10.5,
                        color: PdfColor.fromHex('#08123A'))),
              ),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      const RoomsPage(),
      const MyBookingsPage(),
      const SnackbarPage(),
      const AccountPage(),
    ];
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: ValueListenableBuilder<int>(
        valueListenable: _tab,
        builder: (context, tab, _) => pages[tab],
      ),
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
                backgroundImage: const AssetImage('assets/logo.png'),
                radius: 34,
                backgroundColor: AppColors.navy900,
              ),
              const SizedBox(height: 10),
              const Text('LA-MALIVA VISTA',
                  style: TextStyle(color: AppColors.cream50, letterSpacing: 4, fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Text('A TASTE OF PARADISE',
                  style: TextStyle(color: AppColors.gold, fontSize: 8.5, letterSpacing: 2.4)),
              const SizedBox(height: 8),
              if (user != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.orange600.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.orange600.withOpacity(0.5)),
                  ),
                  child: Text('${user.username} · ${user.role.toUpperCase()}',
                      style: const TextStyle(color: AppColors.gold, fontSize: 11,
                          letterSpacing: 1)),
                ),
            ]),
          ),
          const Divider(color: AppColors.navy800),

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
            const Divider(color: AppColors.navy800),
            const Padding(padding: EdgeInsets.only(left: 20, top: 6, bottom: 6),
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

          const Divider(color: AppColors.navy800),
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
          const Padding(
            padding: EdgeInsets.all(20),
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
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16),
              child: Text('App theme', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          RadioListTile<ThemeMode>(
            value: ThemeMode.light, groupValue: appState._themeMode,
            title: const Text('Paradise Light (cream)'), onChanged: (m) { appState.setThemeMode(m!); Navigator.pop(ctx); }),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark, groupValue: appState._themeMode,
            title: const Text('Ocean Dark (navy)'), onChanged: (m) { appState.setThemeMode(m!); Navigator.pop(ctx); }),
          RadioListTile<ThemeMode>(
            value: ThemeMode.system, groupValue: appState._themeMode,
            title: const Text('Follow system'), onChanged: (m) { appState.setThemeMode(m!); Navigator.pop(ctx); }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _drawerTile(BuildContext context, IconData icon, String label, VoidCallback onTap,
      {bool accent = false, bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(children: const [
          CircleAvatar(backgroundImage: AssetImage('assets/logo.png'), radius: 16),
          SizedBox(width: 10),
          Text('La-Maliva Vista', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_outlined), onPressed: () async {
            await NotificationService.instance.init();
            await NotificationService.instance.notify('La-Maliva Vista',
                'You are up to date. Karibu!');
          }),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await RoomRepository.instance.refresh();
          await SessionService.instance.refreshFeatures();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _Hero(onMenu: () => Scaffold.of(context).openDrawer()),
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
              }, child: const Text('See all')),
            ]),
            if (rooms.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: _cardDeco(context),
                child: const Center(child: Text('Rooms load as soon as you are online',
                    style: TextStyle(color: AppColors.ink500))),
              )
            else
              ...rooms.map((r) => _RoomCard(room: r, onBook: () => _openBooking(context, r))),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: _cardDeco(context),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Find us', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                Text(feats.hotelAddress,
                    style: const TextStyle(color: AppColors.ink500, fontSize: 12.5, height: 1.5)),
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
    );
  }

  BoxDecoration _cardDeco(BuildContext context) => BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.navy950.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, 7))],
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
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => BookingSheet(room: room),
  );
}

class _Hero extends StatelessWidget {
  final VoidCallback onMenu;
  const _Hero({required this.onMenu});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(children: [
            ElevatedButton(
              onPressed: () {
                context.findAncestorStateOfType<_HomeShellState>()?._tab.value = 1;
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: const Text('RESERVE NOW', style: TextStyle(letterSpacing: 1.5, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              onPressed: onMenu,
              icon: const Icon(Icons.menu, color: AppColors.cream50),
              style: IconButton.styleFrom(backgroundColor: AppColors.navy800),
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(children: [
        const Icon(Icons.wifi_off, size: 15, color: AppColors.navy900),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.navy900))),
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
                  style: const TextStyle(color: AppColors.ink500, fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                RichText(text: TextSpan(children: [
                  const TextSpan(text: 'FCFA ', style: TextStyle(color: AppColors.orange600, fontSize: 10, fontWeight: FontWeight.w700)),
                  TextSpan(text: room.price.toStringAsFixed(0), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' / night', style: TextStyle(color: AppColors.ink500, fontSize: 11)),
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

  Widget _imgFallback() => Container(
        color: AppColors.cream100,
        child: const Center(child: Icon(Icons.hotel, size: 44, color: AppColors.orange500)),
      );
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
              style: const TextStyle(color: AppColors.ink500)),
          const SizedBox(height: 18),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (e.g. 679…)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (optional — links receipts to your account)', border: OutlineInputBorder())),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _dateTile('Check-in', _in, () => _pickDate(true))),
            const SizedBox(width: 10),
            Expanded(child: _dateTile('Check-out', _out, () => _pickDate(false))),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.cream100, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$_nights night${_nights > 1 ? 's' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('FCFA ${_total.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.orange600)),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('CONFIRM BOOKING', style: TextStyle(letterSpacing: 1.4, fontWeight: FontWeight.w700)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            border: Border.all(color: AppColors.navy900.withOpacity(0.25)),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.ink500)),
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
      appBar: AppBar(title: const Text('My Bookings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange500))
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
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(18)),
                          child: const Column(children: [
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
        const Icon(Icons.lock_outline, size: 44, color: AppColors.orange500),
        const SizedBox(height: 14),
        const Text('Sign in to see your bookings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        const Text('Same account as the website.',
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
            style: const TextStyle(color: AppColors.ink500, fontSize: 12.5)),
        const SizedBox(height: 6),
        Text('Check-in ${_fmt(b.checkIn)}  →  Check-out ${_fmt(b.checkOut)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => _receipt(context),
            icon: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Receipt'),
          ),
          const SizedBox(width: 8),
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
        nights: 1,
        rate: (bk['amount'] as num?)?.toDouble() ?? 0,
        reference: 'RES-${bk['id']}',
        issuedOn: _fmt((bk['check_in'] ?? '').toString()),
      );
      await Invoice.print(bytes, 'lamaliva-receipt-${b.id}');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printing needs a connection')));
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
              style: const TextStyle(color: AppColors.ink500, fontSize: 11.5)),
          Text((hotel['phone'] ?? '').toString(),
              style: const TextStyle(color: AppColors.ink500, fontSize: 11.5)),
        ]),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: AppColors.ink500, fontSize: 12.5)),
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
      appBar: AppBar(title: const Text('Snackbar & Restaurant')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange500))
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
                              Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                                  child: Text(k.toUpperCase(),
                                      style: const TextStyle(letterSpacing: 2.4, fontSize: 12,
                                          fontWeight: FontWeight.w800, color: AppColors.orange600))),
                              ...cats[k]!.map((i) => _SnackTile(item: i)),
                              const SizedBox(height: 8),
                            ]),
                        if (repo.items.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(18)),
                            child: const Center(child: Text('Menu is being prepared…',
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
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 2),
          Text(item.category, style: const TextStyle(color: AppColors.ink500, fontSize: 11.5)),
        ])),
        Text('FCFA ${item.price.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.orange600, fontSize: 13.5)),
      ]),
    );
  }

  Widget _fallback() => Container(
      color: AppColors.cream100,
      child: const Icon(Icons.local_drink, color: AppColors.orange500));
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
                const Center(child: Text('Payments are confirmed by the front desk; your receipt '
                    'updates automatically.', textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.ink500, fontSize: 11.5))),
              ],
            ),
    );
  }

  Widget _payCard(BuildContext context,
      {required IconData icon, required String title, required String subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: AppColors.orange500.withOpacity(0.13),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: AppColors.orange600),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: AppColors.ink500, fontSize: 12, height: 1.45)),
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
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 86, height: 86,
            decoration: BoxDecoration(
                color: AppColors.orange500.withOpacity(0.12),
                shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: AppColors.orange500),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink500, fontSize: 13, height: 1.55)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('COMING SOON',
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
  @override
  Widget build(BuildContext context) {
    final user = SessionService.instance.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 8),
        Center(
          child: CircleAvatar(
            backgroundImage: const AssetImage('assets/logo.png'),
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
                style: const TextStyle(color: AppColors.ink500, fontSize: 12))),
        const Center(
            child: Text('Native App v$kAppVersion',
                style: TextStyle(color: AppColors.ink500, fontSize: 11))),
        const SizedBox(height: 20),
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
        const Center(
            child: Text('© La-Maliva Vista Hotel · Buea, Cameroon',
                style: TextStyle(color: AppColors.ink500, fontSize: 11))),
      ]),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: AppColors.ink500, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.ink500),
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
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      final user = await SessionService.instance.login(_id.text.trim(), _pw.text);
      await NotificationService.instance.notify(
          'Welcome back, ${user.username}',
          user.isStaff ? 'Staff tools are unlocked in the menu.' : 'Your bookings are synced.');
      if (mounted) Navigator.pop(context, user);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
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
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 92, height: 92,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.orange500.withOpacity(0.35), blurRadius: 36, spreadRadius: 3)]),
              child: ClipOval(child: Image.asset('assets/logo.png', fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.hotel, color: AppColors.gold))),
            ),
          ),
          const SizedBox(height: 20),
          const Center(child: Text('WELCOME BACK',
              style: TextStyle(color: AppColors.cream50, letterSpacing: 5, fontSize: 16,
                  fontWeight: FontWeight.w600))),
          const Center(child: Text('One account for app & website',
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
          const Center(child: Text('No account? Sign up on the website.',
              style: TextStyle(color: AppColors.ink500, fontSize: 12))),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('$kBaseUrl/signup'),
                mode: LaunchMode.externalApplication),
            child: const Text('Create one at la-maliva-vista-hotel.onrender.com',
                style: TextStyle(color: AppColors.gold, fontSize: 12)),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.ink500),
        prefixIcon: Icon(icon, color: AppColors.orange500),
        filled: true,
        fillColor: AppColors.navy900,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.orange500)),
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
            const Padding(padding: EdgeInsets.all(40),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(17)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.orange600, size: 24),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: AppColors.ink500, fontSize: 11.5)),
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
      appBar: AppBar(title: const Text('Reservations')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.orange500))
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
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        Text(status,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: status == 'Checked-In' ? Colors.green : AppColors.orange600)),
                      ]),
                      const SizedBox(height: 3),
                      Text('${r['guest_name']} · ${r['guest_phone'] ?? ''}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                      Text('FCFA ${(r['amount'] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}'
                          '  ·  ${_short((r['check_in'] ?? '').toString())} → ${_short((r['check_out'] ?? '').toString())}',
                          style: const TextStyle(color: AppColors.ink500, fontSize: 11.5)),
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
                  const Padding(padding: EdgeInsets.all(40),
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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final regs = await OfflineRegStore.instance.all();
    if (mounted) setState(() => _regs = regs);
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
      appBar: AppBar(title: const Text('Guest Register (Offline)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.gold.withOpacity(0.4))),
          child: const Row(children: [
            Icon(Icons.cloud_off, color: AppColors.orange600),
            SizedBox(width: 12),
            Expanded(child: Text('Register guests with no internet. Invoices print '
                'straight from this device — data stays on the phone until synced.',
                style: TextStyle(fontSize: 12, height: 1.5))),
          ]),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _openForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('REGISTER GUEST + INVOICE'),
        ),
        const SizedBox(height: 18),
        ..._regs.map((r) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(15)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text('OFFLINE', style: TextStyle(fontSize: 9.5, letterSpacing: 1.4,
                      color: AppColors.orange600, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 3),
                Text('${r.phone} · ${r.email.isEmpty ? "—" : r.email}',
                    style: const TextStyle(color: AppColors.ink500, fontSize: 11.5)),
                Text('${r.roomLabel} · ${r.nights} night(s) · FCFA ${r.total.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(children: [
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
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      await OfflineRegStore.instance.remove(r.id);
                      _reload();
                    },
                    icon: const Icon(Icons.delete_outline, size: 19, color: Colors.redAccent),
                  ),
                ]),
              ]),
            )),
        if (_regs.isEmpty)
          const Padding(padding: EdgeInsets.all(36),
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

  Future<void> _save() async {
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
    await OfflineRegStore.instance.add(reg);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Register guest (offline)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
              value: _nights,
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
              decoration: const InputDecoration(labelText: 'Rate/night FCFA', border: OutlineInputBorder()),
            )),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: AppColors.cream100, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Invoice total', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('FCFA ${(_rate * _nights).toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: AppColors.orange600)),
            ]),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange500, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('SAVE & KEEP ON DEVICE'),
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
          value: _category,
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
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('PUBLISH TO MENU'),
        ),
        const SizedBox(height: 10),
        const Center(child: Text('Photos come from this device and upload straight to the website database.',
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
                value: role,
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
      appBar: AppBar(title: const Text('Administration Tools')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('FEATURE SWITCHES', style: TextStyle(letterSpacing: 2.2, fontSize: 11.5,
            fontWeight: FontWeight.w800, color: AppColors.orange600)),
        const SizedBox(height: 4),
        const Text('Applies to the website and this app instantly.',
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
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('USER MANAGEMENT', style: TextStyle(letterSpacing: 2.2, fontSize: 11.5,
              fontWeight: FontWeight.w800, color: AppColors.orange600)),
          TextButton.icon(
            onPressed: _createStaff,
            icon: const Icon(Icons.person_add_alt, size: 16),
            label: const Text('Add staff'),
          ),
        ]),
        ..._users.map((u) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
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
                      style: const TextStyle(color: AppColors.ink500, fontSize: 11.5)),
                ])),
                Icon(u['verified'] == true ? Icons.verified_outlined : Icons.hourglass_top,
                    size: 18, color: u['verified'] == true ? Colors.green : AppColors.ink500),
              ]),
            )),
      ]),
    );
  }
}
