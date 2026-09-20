import 'package:flutter_test/flutter_test.dart';
import 'package:lamaliva_app/main.dart';

void main() {
  testWidgets('App boots to splash', (tester) async {
    await tester.pumpWidget(const LamalivaApp());
    // Let the splash's 1.4s boot timer elapse (runs _boot → navigation).
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('LA-MALIVA VISTA'), findsOneWidget);
  });
}
