import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyaneyes_tester/main.dart';

void main() {
  testWidgets('Smoke test and check basic navigation', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const NyanEyeTesterApp());
    expect(find.byType(NyanEyeTesterApp), findsOneWidget);

    // Verify Bluetooth debugging screen is shown first
    expect(find.text('扫描蓝牙设备'), findsOneWidget);

    // Verify LAN debugging screen navigation
    await tester.tap(find.byIcon(Icons.wifi));
    await tester.pumpAndSettle();

    // Verify LAN screen has '扫描局域网' and manual IP input elements
    expect(find.text('扫描局域网'), findsOneWidget);
    expect(find.text('直连'), findsOneWidget);
  });
}
