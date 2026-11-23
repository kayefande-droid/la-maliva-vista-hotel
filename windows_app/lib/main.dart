import 'package:flutter/material.dart';

import 'package:lamaliva_staff_ui/lamaliva_staff_ui.dart';

import 'local_server.dart';

/// The hotel API on this PC. Override with
/// `flutter build windows --dart-define=LAMALIVA_API=http://<host>:8000`.
const String kApiBaseUrl = String.fromEnvironment(
  'LAMALIVA_API',
  defaultValue: 'http://127.0.0.1:8000',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The installer carries the API beside the app: bring it up in the
  // background so the desk never has to open a terminal. When the API is
  // hosted on another PC this returns at once.
  await ensureLocalServer(baseUrl: kApiBaseUrl);
  runApp(
    const StaffApp(
      apiBaseUrl: kApiBaseUrl,
      deviceName: 'Windows staff PC',
      platform: 'windows',
    ),
  );
}
