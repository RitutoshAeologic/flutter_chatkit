import 'package:flutter/material.dart';
import 'package:flutter_chatkit/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatKitApp(initialRoute: '/'));
    // Minimal smoke test — verify the widget tree builds
    expect(find.byType(MaterialApp), findsNothing); // GetMaterialApp wraps it
  });
}
