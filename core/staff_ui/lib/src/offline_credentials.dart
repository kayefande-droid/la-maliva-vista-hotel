import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recognises a staff member on this device when the hotel server cannot be
/// reached, so a desk or a phone keeps working through a dropped connection.
///
/// Only a salted, stretched digest of the password is kept — never the
/// password itself — and only the staff record the server already returned.
/// A record is written on every successful online sign-in, so a changed
/// password replaces the old one and a revoked account ages out after
/// [maxAge] days without a successful sign-in.
///
/// This is a convenience, not an authority: nothing held offline is accepted
/// by the server without a live manager or administrator passkey at push time.
class OfflineCredentials {
  OfflineCredentials._();

  static const _storeKey = 'lamaliva.offline.login.v1';
  static const _rounds = 60000;

  /// After this long without a successful online sign-in the saved record is
  /// refused, so a lost phone cannot sign in forever.
  static const Duration maxAge = Duration(days: 30);

  static Map<String, dynamic> _readStore(SharedPreferences prefs) {
    final text = prefs.getString(_storeKey);
    if (text == null || text.isEmpty) return {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // A corrupted store is simply no store.
    }
    return {};
  }

  static String _salt() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  static String _digest(String salt, String username, String password) {
    List<int> bytes = utf8.encode('$salt|$username|$password');
    for (var round = 0; round < _rounds; round++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }

  /// Called after the server accepts a sign-in.
  static Future<void> remember({
    required String username,
    required String password,
    required Map<String, dynamic> staff,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final store = _readStore(prefs);
      final salt = _salt();
      store[username.toLowerCase()] = {
        'salt': salt,
        'hash': _digest(salt, username.toLowerCase(), password),
        'staff': staff,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      };
      await prefs.setString(_storeKey, jsonEncode(store));
    } catch (_) {
      // Never let a device-side write break a live sign-in.
    }
  }

  /// `null` when this device has no usable record for these credentials.
  static Future<Map<String, dynamic>?> recognise({
    required String username,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = _readStore(prefs)[username.toLowerCase()];
      if (entry is! Map) return null;
      final salt = entry['salt'];
      final hash = entry['hash'];
      final staff = entry['staff'];
      if (salt is! String || hash is! String || staff is! Map) return null;

      final savedAt = DateTime.tryParse('${entry['saved_at']}');
      if (savedAt == null) return null;
      if (DateTime.now().toUtc().difference(savedAt.toUtc()) > maxAge) {
        return null;
      }

      final candidate = _digest(salt, username.toLowerCase(), password);
      if (candidate.length != hash.length) return null;
      var same = 0;
      for (var i = 0; i < candidate.length; i++) {
        same |= candidate.codeUnitAt(i) ^ hash.codeUnitAt(i);
      }
      if (same != 0) return null;
      return staff.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Whether this device has ever signed this person in successfully.
  static Future<bool> hasRecord(String username) async {
    final prefs = await SharedPreferences.getInstance();
    return _readStore(prefs)[username.toLowerCase()] is Map;
  }

  /// Used when an administrator changes a password from this device.
  static Future<void> forget(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _readStore(prefs);
    store.remove(username.toLowerCase());
    if (store.isEmpty) {
      await prefs.remove(_storeKey);
    } else {
      await prefs.setString(_storeKey, jsonEncode(store));
    }
  }
}
