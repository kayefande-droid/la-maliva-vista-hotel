import 'dart:async';
import 'dart:io';

/// Starts the hotel API that ships beside this PC app, if it is not already
/// running.
///
/// The installer drops `lamaliva-api.exe` in a `server` folder next to the
/// app. Nothing is started when the API answers already, so a hotel that runs
/// the server centrally is not affected. Failures are swallowed: the app still
/// opens and the sign-in screen offers the server address.
Future<void> ensureLocalServer({String baseUrl = 'http://127.0.0.1:8000'}) async {
  if (!Platform.isWindows) return;
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !_isLoopback(uri.host)) return;

  final probe = Uri.parse('$baseUrl/api/v1/health');
  if (await _answers(probe)) return;

  final exe = File(_apiPath());
  if (!await exe.exists()) return;

  try {
    await Process.start(
      exe.path,
      const [],
      workingDirectory: exe.parent.path,
      mode: ProcessStartMode.detachedWithStdio,
      runInShell: false,
    );
  } on ProcessException {
    return;
  }

  // Give it a moment to bind the port; the first screen then loads normally.
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (await _answers(probe)) return;
  }
}

bool _isLoopback(String host) =>
    host == '127.0.0.1' || host == 'localhost' || host == '::1';

String _apiPath() {
  final dir = File(Platform.resolvedExecutable).parent;
  final candidates = [
    '${dir.path}${Platform.pathSeparator}server'
        '${Platform.pathSeparator}lamaliva-api.exe',
    '${dir.path}${Platform.pathSeparator}lamaliva-api.exe',
    '${dir.path}${Platform.pathSeparator}server'
        '${Platform.pathSeparator}La-Maliva-Vista-API.exe',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return candidates.first;
}

Future<bool> _answers(Uri probe) async {
  final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 700);
  try {
    final request = await client.getUrl(probe);
    final response = await request.close().timeout(const Duration(seconds: 2));
    await response.drain<void>();
    return response.statusCode < 500;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
