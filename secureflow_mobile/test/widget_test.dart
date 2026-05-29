// This test file is a placeholder.
// Run: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:secureflow_mobile/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const ProviderScope(child: SecureFlowApp()));
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}

