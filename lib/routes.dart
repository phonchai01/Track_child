// lib/routes.dart
import 'package:flutter/material.dart';
import 'dart:typed_data';

// ====== Screens ======
import 'features/profiles/profile_list_screen.dart';
import 'features/templates/template_picker_screen.dart';
import 'features/processing/processing_screen.dart';
import 'features/result/result_summary_screen.dart';
import 'features/history/history_list_screen.dart';

/// ชื่อเส้นทางกลาง ใช้ที่เดียวทั้งแอป
class AppRoutes {
  AppRoutes._();

  /// NOTE: กำหนดไว้เพื่ออ้างอิง แต่ **อย่าใส่ '/' ลงในตาราง routes**
  /// เพราะใน MaterialApp มี `home:` อยู่แล้ว
  static const String home = '/';

  static const String templatePicker = '/templates';
  static const String processing = '/process';
  static const String resultSummary = '/result';
  static const String history = '/history';

  /// ตาราง routes (ไม่มี '/')
  static Map<String, WidgetBuilder> get routes => <String, WidgetBuilder>{
    // ❌ ห้ามใส่ '/': (_) => const ProfileListScreen(),
    templatePicker: (_) => const TemplatePickerScreen(),

    // ต้องสร้างจอจาก arguments ที่ถูกส่งมา
    processing: (ctx) {
      final args = (ModalRoute.of(ctx)?.settings.arguments as Map?) ?? {};
      final mask =
          (args['maskAssetPath'] as String?) ?? 'assets/masks/fish_mask.png';

      return ProcessingScreen(
        maskAssetPath: mask,
        imageBytes: args['imageBytes'] as Uint8List?,
        imageAssetPath: args['imageAssetPath'] as String?,
        templateName: args['template'] as String?,
        imageName: args['imageName'] as String?,
      );
    },

    resultSummary: (_) => const ResultSummaryScreen(),

    history: (ctx) {
      final args = (ModalRoute.of(ctx)?.settings.arguments as Map?) ?? {};
      final key = (args['profileKey'] ?? args['key'] ?? args['id'] ?? '')
          .toString();
      return HistoryListScreen(profileKey: key);
    },
  };
}

/// ---------- Helper ช่วยนำทาง ----------
class Nav {
  static Future<T?> toTemplates<T>(
    BuildContext context,
    Map<String, dynamic> profile,
  ) {
    return Navigator.pushNamed<T>(
      context,
      AppRoutes.templatePicker,
      arguments: {'profile': profile},
    );
  }

  static Future<T?> toProcessing<T>(
    BuildContext context, {
    required String maskAssetPath,
    Map<String, dynamic>? profile,
    String? templateKey,
    String? templateName,
    Uint8List? imageBytes,
    String? imageAssetPath,
    String? imageName,
  }) {
    return Navigator.pushNamed<T>(
      context,
      AppRoutes.processing,
      arguments: {
        if (profile != null) 'profile': profile,
        if (templateKey != null) 'templateKey': templateKey,
        if (templateName != null) 'template': templateName,
        if (imageBytes != null) 'imageBytes': imageBytes,
        if (imageAssetPath != null) 'imageAssetPath': imageAssetPath,
        if (imageName != null) 'imageName': imageName,
        'maskAssetPath': maskAssetPath,
      },
    );
  }

  static Future<T?> toResult<T>(
    BuildContext context, {
    required Map<String, dynamic> args,
  }) {
    return Navigator.pushNamed<T>(
      context,
      AppRoutes.resultSummary,
      arguments: args,
    );
  }

  static Future<T?> toHistory<T>(BuildContext context, String profileKey) {
    return Navigator.pushNamed<T>(
      context,
      AppRoutes.history,
      arguments: {'profileKey': profileKey},
    );
  }
}
