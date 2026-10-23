import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:murtada_star/main.dart';

void main() {
  testWidgets('يبدأ التطبيق باسم مرتضى ستار وبالأقسام الأساسية', (tester) async {
    await tester.pumpWidget(const MurtadaStarApp());
    expect(find.text('مرتضى ستار'), findsOneWidget);
    expect(find.text('تنظيف الملفات المؤقتة'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
