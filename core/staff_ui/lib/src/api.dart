import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thin client for the La Maliva Vista API (`/api/v1`).
///
/// The apps only ever talk to the private hotel backend; PostgreSQL is never
/// reachable from a staff device.
class LamalivaApi {
  LamalivaApi({
    required this.baseUrl,
    required this.deviceName,
    required this.platform,
    this.appVersion = '1.0.0',
  });

  final String baseUrl;
  final String deviceName;
  final String platform;
  final String appVersion;

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _staff;

  Map<String, dynamic>? get staff => _staff;
  bool get isSignedIn => _accessToken != null;

  String get staffName =>
      (_staff?['full_name'] ?? _staff?['username'] ?? 'Staff').toString();
  String get staffRole => (_staff?['role'] ?? 'staff').toString();

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool retryOnExpiry = true,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$baseUrl/api/v1$path');
      final req = await client.openUrl(method, uri);
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_accessToken != null) {
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $_accessToken',
        );
      }
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await res.transform(utf8.decoder).join();
      final decoded =
          text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;

      if (res.statusCode == 401 && retryOnExpiry && _refreshToken != null) {
        if (await _refresh()) {
          return _request(method, path, body: body, retryOnExpiry: false);
        }
      }
      if (res.statusCode >= 400) {
        throw ApiException(_errorMessage(decoded), statusCode: res.statusCode);
      }
      return decoded;
    } on SocketException {
      throw ApiException(
        'Cannot reach the hotel server at $baseUrl. '
        'Check that the PC is on and you are on the hotel Wi-Fi.',
      );
    } on HandshakeException {
      throw ApiException('The hotel server refused a secure connection.');
    } finally {
      client.close(force: true);
    }
  }

  List<dynamic> _list(Map<String, dynamic> res) {
    final data = res['data'];
    return data is List ? data : const [];
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await _request('POST', '/auth/login', body: {
      'username': username,
      'password': password,
      'device': {
        'fingerprint': '$platform-${deviceName.toLowerCase().replaceAll(' ', '-')}',
        'name': deviceName,
        'platform': platform,
        'app_version': appVersion,
      },
    });
    final data = res['data'] as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String?;
    _staff = (data['staff'] as Map?)?.cast<String, dynamic>();
    return data;
  }

  Future<bool> _refresh() async {
    try {
      final res = await _request(
        'POST',
        '/auth/refresh',
        body: {'refresh_token': _refreshToken},
        retryOnExpiry: false,
      );
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final token = data['access_token'] as String?;
      if (token == null) return false;
      _accessToken = token;
      final refreshed = data['refresh_token'] as String?;
      if (refreshed != null) _refreshToken = refreshed;
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _request(
        'POST',
        '/auth/logout',
        body: {'refresh_token': _refreshToken},
        retryOnExpiry: false,
      );
    } on ApiException {
      // Signing out locally matters more than the server acknowledging it.
    } finally {
      _accessToken = null;
      _refreshToken = null;
      _staff = null;
    }
  }

  Future<List<dynamic>> rooms({String? status}) async {
    final query = status == null || status.isEmpty ? '' : '?status=$status';
    return _list(await _request('GET', '/rooms$query'));
  }

  Future<List<dynamic>> reservations({String? status}) async {
    final query = status == null || status.isEmpty ? '' : '?status=$status';
    return _list(await _request('GET', '/reservations$query'));
  }

  Future<List<dynamic>> arrivals() async =>
      _list(await _request('GET', '/reservations/arrivals'));

  Future<List<dynamic>> departures() async =>
      _list(await _request('GET', '/reservations/departures'));

  Future<List<dynamic>> guests() async =>
      _list(await _request('GET', '/guests'));

  Future<Map<String, dynamic>> overview() async {
    final res = await _request('GET', '/reports/overview');
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  bool get isAdmin => staffRole == 'admin';

  /// Register a guest straight into a room. The server seals the record and
  /// marks the room occupied in the same transaction.
  Future<Map<String, dynamic>> registerGuest({
    required int roomId,
    required Map<String, dynamic> guest,
    int nights = 1,
    int adults = 1,
    int children = 0,
    num? ratePerNight,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'room_id': roomId,
      'nights': nights,
      'adults': adults,
      'children': children,
      'guest': guest,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (ratePerNight != null) 'rate_per_night': ratePerNight,
    };
    final res = await _request('POST', '/reservations/register', body: body);
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<List<dynamic>> idTypes() async =>
      _list(await _request('GET', '/guests/id-types'));

  Future<List<dynamic>> inventoryItems() async =>
      _list(await _request('GET', '/inventory/items'));

  Future<List<dynamic>> movements(int itemId) async =>
      _list(await _request('GET', '/inventory/items/$itemId/movements'));

  Future<Map<String, dynamic>> recordMovement(
    int itemId, {
    required String kind,
    required num quantity,
    String? reason,
  }) async {
    final res = await _request(
      'POST',
      '/inventory/items/$itemId/movements',
      body: {
        'kind': kind,
        'quantity': quantity,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<Map<String, dynamic>> createItem({
    required String name,
    required String unit,
    num quantity = 0,
    num reorderLevel = 0,
    num unitCost = 0,
    String category = 'general',
    String? location,
  }) async {
    final res = await _request('POST', '/inventory/items', body: {
      'name': name,
      'unit': unit,
      'quantity': quantity,
      'reorder_level': reorderLevel,
      'unit_cost': unitCost,
      'category': category,
      if (location != null && location.trim().isNotEmpty) 'location': location.trim(),
    });
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<Map<String, dynamic>> updateItem(int id, Map<String, dynamic> changes) async {
    final res = await _request('PATCH', '/inventory/items/$id', body: changes);
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<List<dynamic>> staffAccounts() async =>
      _list(await _request('GET', '/staff'));

  Future<Map<String, dynamic>> createStaff({
    required String username,
    required String fullName,
    required String role,
    String? email,
    String? password,
  }) async {
    final res = await _request('POST', '/staff', body: {
      'username': username,
      'full_name': fullName,
      'role': role,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (password != null && password.trim().isNotEmpty) 'password': password.trim(),
    });
    return res;
  }

  Future<List<dynamic>> roomTypes() async =>
      _list(await _request('GET', '/rooms/types'));

  Future<Map<String, dynamic>> updateRoomType(
    int id, {
    num? baseRate,
    int? capacity,
    String? name,
  }) async {
    final res = await _request('PATCH', '/rooms/types/$id', body: {
      if (baseRate != null) 'base_rate': baseRate,
      if (capacity != null) 'capacity': capacity,
      if (name != null) 'name': name,
    });
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// The API answers with RFC 7807 problem details (`detail` / `title`), while
  /// some endpoints nest the reason in `error.message`. Accept both, so a
  /// rejected sign-in shows the real reason instead of a generic failure.
  static String _errorMessage(Map<String, dynamic> body) {
    final detail = body['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail;
    final error = body['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    if (error is String && error.trim().isNotEmpty) return error;
    final message = body['message'];
    if (message is String && message.trim().isNotEmpty) return message;
    final title = body['title'];
    if (title is String && title.trim().isNotEmpty) return title;
    return 'Request failed';
  }
}
