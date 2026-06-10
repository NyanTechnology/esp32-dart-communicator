import 'package:flutter_test/flutter_test.dart';
import 'package:nyaneyes_tester/main.dart';

void main() {
  testWidgets('Smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const NyanEyeTesterApp());
    expect(find.byType(NyanEyeTesterApp), findsOneWidget);
  });
}
