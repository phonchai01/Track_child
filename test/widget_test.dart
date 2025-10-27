import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_phone_app/main.dart';

void main() {
  // ✅ ทดสอบว่าแอป ColoringApp โหลดได้โดยไม่ error
  testWidgets('ColoringApp builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ColoringApp());

    // ตรวจว่ามี MaterialApp อยู่ 1 ตัว (หมายถึงแอปโหลดสำเร็จ)
    expect(find.byType(MaterialApp), findsOneWidget);

    // ตรวจว่ามี title 'Coloring Metrics' แสดงอยู่บนหน้าจอ
    expect(find.text('Coloring Metrics'), findsOneWidget);
  });
}
