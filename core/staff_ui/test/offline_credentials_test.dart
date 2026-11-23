import 'package:flutter_test/flutter_test.dart';
import 'package:lamaliva_staff_ui/src/offline_credentials.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staff = {
    'id': 7,
    'username': 'frontdesk',
    'full_name': 'Front Desk',
    'role': 'receptionist',
  };

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a saved sign-in recognises the same password and nothing else',
    () async {
      await OfflineCredentials.remember(
        username: 'frontdesk',
        password: 'Maliva#2026',
        staff: staff,
      );

      final found = await OfflineCredentials.recognise(
        username: 'FrontDesk',
        password: 'Maliva#2026',
      );
      expect(found, isNotNull);
      expect(found!['role'], 'receptionist');

      expect(
        await OfflineCredentials.recognise(
          username: 'frontdesk',
          password: 'maliva#2026',
        ),
        isNull,
      );
      expect(
        await OfflineCredentials.recognise(
          username: 'someone-else',
          password: 'Maliva#2026',
        ),
        isNull,
      );
    },
  );

  test('the stored record never contains the password', () async {
    await OfflineCredentials.remember(
      username: 'frontdesk',
      password: 'Maliva#2026',
      staff: staff,
    );
    final prefs = await SharedPreferences.getInstance();
    final blob = prefs.getString('lamaliva.offline.login.v1') ?? '';
    expect(blob, isNot(contains('Maliva#2026')));
    expect(blob, contains('frontdesk'));
  });

  test('a record older than the window is refused', () async {
    await OfflineCredentials.remember(
      username: 'frontdesk',
      password: 'Maliva#2026',
      staff: staff,
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('lamaliva.offline.login.v1')!;
    final old = raw.replaceFirst(
      RegExp(r'"saved_at":"[^"]+"'),
      '"saved_at":"${DateTime.now().toUtc().subtract(const Duration(days: 90)).toIso8601String()}"',
    );
    await prefs.setString('lamaliva.offline.login.v1', old);

    expect(
      await OfflineCredentials.recognise(
        username: 'frontdesk',
        password: 'Maliva#2026',
      ),
      isNull,
    );
  });

  test('a new password replaces the old record', () async {
    await OfflineCredentials.remember(
      username: 'frontdesk',
      password: 'Maliva#2026',
      staff: staff,
    );
    await OfflineCredentials.remember(
      username: 'frontdesk',
      password: 'Maliva#2027',
      staff: staff,
    );
    expect(
      await OfflineCredentials.recognise(
        username: 'frontdesk',
        password: 'Maliva#2026',
      ),
      isNull,
    );
    expect(
      await OfflineCredentials.recognise(
        username: 'frontdesk',
        password: 'Maliva#2027',
      ),
      isNotNull,
    );
  });
}
