import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'offline.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.offline = false});

  final String message;
  final int? statusCode;

  /// True when the request never reached the server. Those failures can be
  /// held on the device and replayed once the server returns.
  final bool offline;

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
  String get username => (_staff?['username'] ?? '').toString();

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
      final decoded = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;

      if (res.statusCode == 401 && retryOnExpiry && _refreshToken != null) {
        if (await _refresh()) {
          return _request(method, path, body: body, retryOnExpiry: false);
        }
      }
      if (res.statusCode >= 400) {
        throw ApiException(_errorMessage(decoded), statusCode: res.statusCode);
      }
      NetworkStatus.reachable.value = true;
      return decoded;
    } on TimeoutException {
      NetworkStatus.reachable.value = false;
      throw ApiException(
        'The hotel server is not answering. You can continue offline; '
        'actions are held on this device until it returns.',
        offline: true,
      );
    } on SocketException {
      NetworkStatus.reachable.value = false;
      throw ApiException(
        'Cannot reach the hotel server at $baseUrl. '
        'You can continue offline; actions are held on this device.',
        offline: true,
      );
    } on HandshakeException {
      NetworkStatus.reachable.value = false;
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
    final res = await _request(
      'POST',
      '/auth/login',
      body: {
        'username': username,
        'password': password,
        'device': {
          'fingerprint':
              '$platform-${deviceName.toLowerCase().replaceAll(' ', '-')}',
          'name': deviceName,
          'platform': platform,
          'app_version': appVersion,
        },
      },
    );
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

  /// A list that survives a dead server: the last good answer is served, and
  /// the caller can tell it is stale from [NetworkStatus.reachable].
  Future<List<dynamic>> _cachedList(
    String key,
    Future<List<dynamic>> Function() load,
  ) async {
    try {
      final list = await load();
      await OfflineCache.put(key, list);
      return list;
    } on ApiException catch (error) {
      if (error.offline) {
        final cached = await OfflineCache.read(key);
        if (cached is List) return cached;
      }
      rethrow;
    }
  }

  Future<List<dynamic>> rooms({String? status}) async {
    final query = status == null || status.isEmpty ? '' : '?status=$status';
    return _cachedList(
      'rooms$query',
      () async => _list(await _request('GET', '/rooms$query')),
    );
  }

  Future<List<dynamic>> reservations({String? status}) async {
    final query = status == null || status.isEmpty ? '' : '?status=$status';
    return _cachedList(
      'reservations$query',
      () async => _list(await _request('GET', '/reservations$query')),
    );
  }

  Future<List<dynamic>> arrivals() async => _cachedList(
    'arrivals',
    () async => _list(await _request('GET', '/reservations/arrivals')),
  );

  Future<List<dynamic>> departures() async => _cachedList(
    'departures',
    () async => _list(await _request('GET', '/reservations/departures')),
  );

  Future<List<dynamic>> guests() async => _cachedList(
    'guests',
    () async => _list(await _request('GET', '/guests')),
  );

  Future<Map<String, dynamic>> overview() async {
    try {
      final res = await _request('GET', '/reports/overview');
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      await OfflineCache.put('overview', data);
      return data;
    } on ApiException catch (error) {
      if (error.offline) {
        final cached = await OfflineCache.read('overview');
        if (cached is Map) {
          return {...cached.cast<String, dynamic>(), 'stale': true};
        }
      }
      rethrow;
    }
  }

  bool get isAdmin => staffRole == 'admin';

  /// Approving extensions and authorising debt belongs to management, so the
  /// client hides those controls for everyone else — the server enforces it.
  bool get canApprove => staffRole == 'admin' || staffRole == 'manager';

  // --- Stays ---------------------------------------------------------

  /// Every room currently held, with the server's own countdown and money
  /// position. The server reads this from its clock in Africa/Douala.
  Future<Map<String, dynamic>> stayMonitor() async {
    try {
      final res = await _request('GET', '/stays/monitor');
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      await OfflineCache.put('stays.monitor', data);
      return data;
    } on ApiException catch (error) {
      if (error.offline) {
        final cached = await OfflineCache.read('stays.monitor');
        if (cached is Map) {
          return {...cached.cast<String, dynamic>(), 'stale': true};
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> stayDetail(int reservationId) async {
    try {
      final res = await _request('GET', '/stays/$reservationId');
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      await OfflineCache.put('stays.$reservationId', data);
      return data;
    } on ApiException catch (error) {
      if (error.offline) {
        final cached = await OfflineCache.read('stays.$reservationId');
        if (cached is Map) {
          return {...cached.cast<String, dynamic>(), 'stale': true};
        }
      }
      rethrow;
    }
  }

  /// A cheap check that the server is back. Never throws.
  Future<bool> probe() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/api/v1/health'));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      final ok = res.statusCode < 500;
      if (ok) NetworkStatus.reachable.value = true;
      return ok;
    } catch (_) {
      NetworkStatus.reachable.value = false;
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Writes a held action back through the ordinary endpoint.
  Future<Map<String, dynamic>> postRaw(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _request('POST', path, body: body);
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
  }

  Future<Map<String, dynamic>> addPayment(
    int reservationId, {
    required num amount,
    required String method,
    String kind = 'payment',
    String? reference,
    String? notes,
  }) async {
    final res = await _request(
      'POST',
      '/stays/$reservationId/payments',
      body: {
        'amount': amount,
        'kind': kind,
        'method': method,
        if (reference != null && reference.trim().isNotEmpty)
          'reference': reference.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Ask for more time. With approval required the stay keeps its current
  /// expiry until a manager decides, and the original stay is never rewritten.
  Future<Map<String, dynamic>> requestExtension(
    int reservationId, {
    required int minutes,
    String? note,
    bool autoApprove = false,
  }) async {
    final res = await _request(
      'POST',
      '/stays/$reservationId/extensions',
      body: {
        'minutes': minutes,
        'auto_approve': autoApprove,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return res;
  }

  Future<Map<String, dynamic>> approveExtension(
    int reservationId,
    int extensionId,
  ) async {
    final res = await _request(
      'POST',
      '/stays/$reservationId/extensions/$extensionId/approve',
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<Map<String, dynamic>> rejectExtension(
    int reservationId,
    int extensionId, {
    String? note,
  }) async {
    final res = await _request(
      'POST',
      '/stays/$reservationId/extensions/$extensionId/reject',
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Close the stay: final payment, receipt and a housekeeping task. A balance
  /// can only be left outstanding with a manager's authorisation.
  Future<Map<String, dynamic>> checkoutStay(
    int reservationId, {
    List<Map<String, dynamic>> payments = const [],
    bool authoriseOutstanding = false,
    String? note,
  }) async {
    final res = await _request(
      'POST',
      '/stays/$reservationId/checkout',
      body: {
        'payments': payments,
        'authorise_outstanding': authoriseOutstanding,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<Map<String, dynamic>> receipt(int reservationId) async {
    final res = await _request('GET', '/stays/$reservationId/receipt');
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

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

  Future<List<dynamic>> idTypes() async => _cachedList(
    'guests.idTypes',
    () async => _list(await _request('GET', '/guests/id-types')),
  );

  /// Money screens carry the night's takings, so they stay with management.
  bool get canSeeMoney => staffRole == 'admin' || staffRole == 'manager';

  Future<Map<String, dynamic>> moneyReport({int days = 30}) async {
    final today = DateTime.now();
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final from = iso(today.subtract(Duration(days: days - 1)));
    final res = await _request(
      'GET',
      '/reports/money?from=$from&to=${iso(today)}',
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Today's till: the recent sales and their money total.
  Future<(List<dynamic>, Map<String, dynamic>)> shopSales() async {
    final res = await _request('GET', '/shop/sales');
    final meta = (res['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (_list(res), meta);
  }

  Future<Map<String, dynamic>> recordSale({
    required int itemId,
    required num quantity,
    num? unitPrice,
    String method = 'cash',
    String? reference,
  }) async {
    final res = await _request(
      'POST',
      '/shop/sales',
      body: {
        'item_id': itemId,
        'quantity': quantity,
        if (unitPrice != null) 'unit_price': unitPrice,
        'method': method,
        if (reference != null) 'reference': reference,
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<List<dynamic>> inventoryItems() async => _cachedList(
    'inventory.items',
    () async => _list(await _request('GET', '/inventory/items')),
  );

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
    num salePrice = 0,
    String category = 'general',
    String? location,
  }) async {
    final res = await _request(
      'POST',
      '/inventory/items',
      body: {
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'reorder_level': reorderLevel,
        'unit_cost': unitCost,
        'sale_price': salePrice,
        'category': category,
        if (location != null && location.trim().isNotEmpty)
          'location': location.trim(),
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  Future<Map<String, dynamic>> updateItem(
    int id,
    Map<String, dynamic> changes,
  ) async {
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
    final res = await _request(
      'POST',
      '/staff',
      body: {
        'username': username,
        'full_name': fullName,
        'role': role,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (password != null && password.trim().isNotEmpty)
          'password': password.trim(),
      },
    );
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
    final res = await _request(
      'PATCH',
      '/rooms/types/$id',
      body: {
        if (baseRate != null) 'base_rate': baseRate,
        if (capacity != null) 'capacity': capacity,
        if (name != null) 'name': name,
      },
    );
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
