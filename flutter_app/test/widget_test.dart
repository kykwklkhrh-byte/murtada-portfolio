import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viral_clips_ai/main.dart';

void main() {
  testWidgets('launches Arabic offline home without reading server settings', (tester) async {
    await tester.pumpWidget(const ViralApp());
    expect(find.text('VIRAL CLIPS AI'), findsOneWidget);
    expect(find.text('اختيار فيديو من الجهاز'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
  testWidgets('about screen identifies manual TikTok sharing', (tester) async {
    await tester.pumpWidget(const ViralApp());
    await tester.tap(find.text('عن التطبيق').last);
    await tester.pump();
    expect(find.textContaining('مو نشر تلقائي'), findsOneWidget);
  });
}
