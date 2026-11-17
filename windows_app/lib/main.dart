import 'package:flutter/material.dart';

import 'package:lamaliva_staff_ui/lamaliva_staff_ui.dart';

/// The hotel API on this PC. Override with
/// `flutter build windows --dart-define=LAMALIVA_API=http://<host>:8000`.
const String kApiBaseUrl = String.fromEnvironment(
  'LAMALIVA_API',
  defaultValue: 'http://127.0.0.1:8000',
);

void main() {
  runApp(
    const StaffApp(
      apiBaseUrl: kApiBaseUrl,
      deviceName: 'Windows staff PC',
      platform: 'windows',
    ),
  );
}
