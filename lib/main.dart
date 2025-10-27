// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';

import 'routes.dart';
import 'features/templates/template_picker_screen.dart'; // <- ใช้เป็น home

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // จับ error ฝั่ง Flutter ทั้งหมดให้เห็นในคอนโซล
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // กัน error หลุดนอกเฟรม (เช่น asset/route ผิด) จะพิมพ์ stack ชัดเจน
  runZonedGuarded(
    () {
      runApp(const ColoringApp());
    },
    (error, stack) {
      // ดูสาเหตุจริงถ้ามีแอปเด้ง
      // คุณจะเห็นบรรทัดนี้ในคอนโซล
      debugPrint('UNCAUGHT ERROR: $error\n$stack');
    },
  );
}

class ColoringApp extends StatelessWidget {
  const ColoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coloring Metrics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),

      // แสดงหน้าเลือกเทมเพลตเป็นหน้าแรก (ลดความเสี่ยงชื่อ route เพี้ยน)
      home: const TemplatePickerScreen(),

      // ยังให้ onGenerateRoute ใช้งานได้ตามเดิมเวลานำทาง
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
