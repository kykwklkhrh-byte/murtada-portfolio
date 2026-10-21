import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viral_clips_ai/main.dart';

void main() {
  testWidgets('Arabic navigation renders without backend', (tester) async {
    await tester.pumpWidget(const ViralApp());
    expect(find.text('VIRAL CLIPS AI'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('الرئيسية'), findsWidgets);
  });
}
