import 'package:flutter_test/flutter_test.dart';
import 'package:lamaliva_staff_ui/src/offline.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineVault.pending.value = 0;
  });

  test('held actions are encrypted and only the passkey opens them', () async {
    expect(await OfflineVault.hasVault(), isFalse);
    expect(await OfflineVault.unlock('manager-passkey'), isTrue);

    await OfflineVault.hold(
      HeldAction(
        id: heldActionId('/stays/3/payments'),
        label: 'Payment 20 000 XAF',
        path: '/stays/3/payments',
        body: {'amount': 20000, 'method': 'cash', 'reference': 'APP-1'},
        at: DateTime(2026, 11, 23, 12),
      ),
    );
    expect(OfflineVault.pending.value, 1);

    await OfflineVault.lock();
    expect(await OfflineVault.unlock('wrong-passkey'), isFalse);
    expect(await OfflineVault.unlock('manager-passkey'), isTrue);

    final actions = await OfflineVault.actions();
    expect(actions, hasLength(1));
    expect(actions.single.path, '/stays/3/payments');
    expect(actions.single.body['reference'], 'APP-1');
  });

  test('removing a held action updates the queue and its count', () async {
    await OfflineVault.unlock('manager-passkey');
    final id = heldActionId('/stays/4/checkout');
    await OfflineVault.hold(
      HeldAction(
        id: id,
        label: 'Checkout',
        path: '/stays/4/checkout',
        body: const {},
        at: DateTime(2026, 11, 23, 12),
      ),
    );
    await OfflineVault.remove(id);
    expect(await OfflineVault.actions(), isEmpty);
    expect(OfflineVault.pending.value, 0);
  });
}
