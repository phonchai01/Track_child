// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'routes.dart';

// ตั้งให้ path ตรงกับโปรเจกต์ของคุณ:
// ถ้าโฟลเดอร์ชื่อ features/profiles/ ให้ใช้ import นี้
import 'features/profiles/profile_list_screen.dart';

// ถ้าโปรเจกต์คุณใช้ features/profile/ (ไม่มี s) ให้ใช้บรรทัดล่างแทน
// import 'features/profile/profile_list_screen.dart';

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

      // ✅ หน้าแรก: เลือกโปรไฟล์
      home: const ProfileListScreen(),

      // ✅ ใช้ routes แบบตายตัวจาก routes.dart (ไม่ใช้ onGenerateRoute แล้ว)
      routes: AppRoutes.routes,
    );
  }
}
