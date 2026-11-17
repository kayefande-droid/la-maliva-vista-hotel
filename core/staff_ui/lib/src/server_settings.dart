import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// The hotel's server address belongs to the device, not to the build: the same
/// install can be pointed at the office server, a LAN address or a remote host.
///
/// The address lives in the app's private preferences, and changing it requires
/// an administrator's credentials — the app signs in against the candidate host
/// and only keeps the address when that account really is an administrator on
/// that server. A wrong address or a non-admin account is refused and the old
/// address is left untouched.
class ServerSettings {
  static const _key = 'lamaliva.server.url';

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null || saved.trim().isEmpty) return null;
    return saved.trim();
  }

  static Future<void> save(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalise(url));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// `hotel.example.com:8000/` becomes `http://hotel.example.com:8000`.
  static String normalise(String url) {
    var value = url.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Returns `null` when [username]/[password] is an administrator on
  /// [baseUrl]; otherwise the reason it was refused, ready to show.
  static Future<String?> verifyAdmin({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    if (baseUrl.trim().isEmpty) return 'Enter the server address.';
    if (username.trim().isEmpty || password.isEmpty) {
      return 'An administrator username and password are required.';
    }
    final probe = LamalivaApi(
      baseUrl: normalise(baseUrl),
      deviceName: deviceName,
      platform: platform,
    );
    try {
      await probe.login(username: username.trim(), password: password);
    } on ApiException catch (e) {
      return 'Could not sign in to that server: ${e.message}';
    } catch (e) {
      return 'That address did not answer: $e';
    }
    if (!probe.isAdmin) {
      return 'That account is staff, not an administrator. Only an administrator may change the server address.';
    }
    return null;
  }
}
