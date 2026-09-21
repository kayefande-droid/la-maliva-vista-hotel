import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaliva_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  testWidgets('Splash renders badge, wordmark and progress, then hands over',
      (tester) async {
    await tester.pumpWidget(const LamalivaApp());

    // Splash content
    expect(find.text('LA-MALIVA VISTA'), findsOneWidget);
    expect(find.text('A  T A S T E  O F  P A R A D I S E'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let the splash timer run out and the home shell appear.
    // Fixed pumps (not pumpAndSettle): the wavy home background repeats
    // forever by design, so settling would never finish.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Home shell is up with bottom navigation
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Slide menu button opens the drawer', (tester) async {
    await tester.pumpWidget(const LamalivaApp());
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // The single ☰ at the top-left opens the shell drawer
    await tester.tap(find.byIcon(Icons.menu).first);
    await tester.pump(const Duration(milliseconds: 400));

    // Drawer slides in — its top items are on screen
    expect(find.text('Snackbar / restaurant menu'), findsOneWidget);
  });

  testWidgets('Snackbar shows Coming Soon while the toggle is off',
      (tester) async {
    SessionService.instance.features = Features(snackbarActive: false);
    await tester.pumpWidget(const MaterialApp(home: SnackbarPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Snackbar menu is brewing'), findsOneWidget);
  });

  testWidgets('Payments shows Coming Soon while the toggle is off',
      (tester) async {
    SessionService.instance.features = Features(paymentsActive: false);
    await tester.pumpWidget(const MaterialApp(home: PaymentsPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Mobile Money & Bank payments'), findsOneWidget);
  });

  testWidgets('Payments lists MoMo and bank once the admin toggle is on',
      (tester) async {
    SessionService.instance.features = Features(paymentsActive: true);
    await tester.pumpWidget(const MaterialApp(home: PaymentsPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('MTN Mobile Money'), findsOneWidget);
    expect(find.text('Bank Transfer'), findsOneWidget);
    expect(find.text('COMING SOON'), findsNothing);
  });

  testWidgets('Account page shows guest state with theme switcher',
      (tester) async {
    SessionService.instance.user = null;
    await tester.pumpWidget(const LamalivaApp());
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Jump to the Account tab
    await tester.tap(find.text('Account'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Change app theme'), findsOneWidget);
    expect(find.text('Native App v$kAppVersion'), findsOneWidget);
  });
}
