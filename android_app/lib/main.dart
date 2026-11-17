import 'package:flutter/material.dart';

import 'package:lamaliva_staff_ui/lamaliva_staff_ui.dart';

/// Hotel API base URL.
///
/// The emulator reaches the host PC at 10.0.2.2. A real phone needs the PC's
/// address on the hotel network:
/// `flutter build apk --dart-define=LAMALIVA_API=http://<PC-IP>:8000`.
const String kApiBaseUrl = String.fromEnvironment(
  'LAMALIVA_API',
  defaultValue: 'http://10.0.2.2:8000',
);

void main() {
  runApp(
    const StaffApp(
      apiBaseUrl: kApiBaseUrl,
      deviceName: 'Android staff phone',
      platform: 'android',
    ),
  );
}
