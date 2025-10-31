// lib/features/camera/camera_overlay_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../widgets/app_drawer.dart';
import '../../widgets/app_button.dart';
import '../../widgets/template_overlay.dart';
import '../processing/processing_screen.dart';

class CameraOverlayScreen extends StatelessWidget {
  const CameraOverlayScreen({super.key});

  /// แปลงชื่อเทมเพลตให้เป็น key ที่ใช้กับ assets/masks/*
  String _normalizeKey(String raw) {
    final r = raw.trim().toLowerCase();
    const mapThToKey = {
      'ปลา': 'fish',
      'ดินสอ': 'pencil',
      'ไอศกรีม': 'icecream',
      'ไอติม': 'icecream',
    };
    return mapThToKey[r] ?? r; // ถ้าเป็น 'fish'/'pencil' อยู่แล้วจะคงเดิม
  }

  /// อ่าน templateKey จาก arguments (รองรับทั้ง Map และ String)
  String _getTemplateKey(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    String? k;

    if (args is Map) {
      // รองรับหลายชื่อคีย์ เพื่อความยืดหยุ่น
      k = (args['templateKey'] ?? args['template'] ?? args['key'] ?? args['id'])
          ?.toString();
    } else if (args is String) {
      k = args;
    }

    final result = _normalizeKey((k ?? 'fish'));
    debugPrint('[Camera] templateKey=$result (from args=$args)');
    return result;
  }

  Future<void> _pickImage(
    BuildContext context, {
    bool fromCamera = false,
  }) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await (fromCamera
          ? picker.pickImage(source: ImageSource.camera, imageQuality: 95)
          : picker.pickImage(source: ImageSource.gallery, imageQuality: 95));
      if (picked == null) return;

      final Uint8List bytes = await picked.readAsBytes();
      final String templateKey = _getTemplateKey(context);

      // ➜ ไปหน้า Processing พร้อมภาพและ templateKey ที่เลือกจริง
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProcessingScreen(
            imageBytes: bytes,
            maskAssetPath:
                'assets/masks/${templateKey}_mask.png', // โหลด mask ตามชื่อ key
          ),

          settings: RouteSettings(
            arguments: {
              'imageBytes': bytes,
              'templateKey': templateKey, // Processing จะโหลด mask ตาม key นี้
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เลือก/ถ่ายรูปไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String templateKey = _getTemplateKey(context);

    return Scaffold(
      appBar: AppBar(title: const Text('โหมดถ่ายภาพ')),
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          const Center(
            child: Icon(Icons.photo_camera, size: 120, color: Colors.black26),
          ),
          // แสดง overlay ตามเทมเพลตที่เลือก (หลัง normalize แล้ว)
          TemplateOverlay(templateName: templateKey),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'เลือกรูป',
                    primary: false,
                    onPressed: () => _pickImage(context, fromCamera: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    text: 'ถ่ายรูป',
                    onPressed: () => _pickImage(context, fromCamera: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
