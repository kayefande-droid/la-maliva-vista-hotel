import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lamaliva_staff_ui/lamaliva_staff_ui.dart';

void main() {
  testWidgets('staff sign-in renders in the desktop layout', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const StaffApp(
        apiBaseUrl: 'http://127.0.0.1:8000',
        deviceName: 'Windows test',
        platform: 'windows',
      ),
    );

    // The wide shell puts the wordmark on the photograph and the form beside it.
    expect(find.text('La Maliva Vista'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Server  http://127.0.0.1:8000'), findsOneWidget);
  });
}
