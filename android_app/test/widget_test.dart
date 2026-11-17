import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lamaliva_staff_ui/lamaliva_staff_ui.dart';

void main() {
  testWidgets('staff sign-in screen renders on a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400); // Galaxy Note 8-ish
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const StaffApp(
        apiBaseUrl: 'http://192.168.1.128:8000',
        deviceName: 'Android test',
        platform: 'android',
      ),
    );

    // The wordmark is the hotel logo image, so assert its accessible identity
    // as well as the form itself.
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'La Maliva Vista hotel logo',
      ),
      findsOneWidget,
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
  });
}
