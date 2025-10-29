// lib/routes.dart
import 'package:flutter/material.dart';

import 'features/templates/template_picker_screen.dart';
import 'features/camera/camera_overlay_screen.dart';
import 'features/processing/processing_screen.dart';
import 'features/result/result_summary_screen.dart';
import 'features/history/history_list_screen.dart';
import 'features/trends/trends_screen.dart';
import 'features/trends/progress_screen.dart';
import 'features/profiles/profile_list_screen.dart'; // <- ใช้เป็น home

class AppRoutes {
  static const templates = '/templates';
  static const camera = '/camera';
  static const processing = '/processing';
  static const result = '/result';
  static const history = '/history';
  static const trends = '/trends';
  static const profiles = '/profiles';
}

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.templates:
        return MaterialPageRoute(
          builder: (_) => const TemplatePickerScreen(),
          settings: settings, // ✅ ใส่ไว้ให้เหมือนกัน
        );

      case AppRoutes.camera:
        return MaterialPageRoute(
          builder: (_) => const CameraOverlayScreen(),
          settings: settings, // ✅ สำคัญ: ส่ง arguments ต่อไป
        );

      case AppRoutes.processing:
        return MaterialPageRoute(
          builder: (_) =>
              const ProcessingScreen(maskAssetPath: '', templateAssetPath: ''),
          settings: settings, // ✅ ส่ง args ต่อให้หน้าประมวลผลด้วย
        );

      case AppRoutes.result:
        return MaterialPageRoute(
          builder: (_) => const ResultSummaryScreen(),
          settings: settings,
        );

      case AppRoutes.history:
        return MaterialPageRoute(
          builder: (_) => const HistoryListScreen(),
          settings: settings,
        );

      case AppRoutes.trends:
        return MaterialPageRoute(
          builder: (_) => const TrendsScreen(),
          settings: settings,
        );
      case AppRoutes.trends:
        return MaterialPageRoute(builder: (_) => const ProgressScreen());
      case AppRoutes.templates:
        return MaterialPageRoute(
          builder: (_) => const ProfileListScreen(),
          settings: settings, // ✅ ใส่ไว้ให้เหมือนกัน
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const ProfileListScreen(),
          settings: settings,
        );
    }
  }
}
