// lib/features/processing/pick_image_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import './processing_screen.dart';

class PickImageScreen extends StatelessWidget {
  const PickImageScreen({
    super.key,
    required this.maskAssetPath, // เช่น 'assets/masks/fish_mask.png'
    this.templateName,           // ชื่อเทมเพลตเพื่อโชว์บน AppBar
  });

  final String maskAssetPath;
  final String? templateName;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    // ดึง args ที่ส่งมาจาก TemplatePicker (profile + template)
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final profile = args?['profile'];
    final template =
        (args?['template'] ?? templateName)?.toString(); // กันกรณีไม่ได้ส่ง template ใน args

    if (maskAssetPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('maskAssetPath ว่าง: กรุณาส่งพาธของ mask')),
      );
      return;
    }

    final XFile? picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;

    final Uint8List bytes = await picked.readAsBytes();

    // ไปหน้า Processing พร้อมรูป + mask และ "ส่งต่อ" profile/age + template ไปด้วย
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          imageBytes: bytes,
          maskAssetPath: maskAssetPath,
          templateName: template, // เผื่อใช้แสดงชื่อบนหน้า Processing
        ),
        settings: RouteSettings(arguments: {
          'profile': profile,     // ✅ สำคัญ: มี age อยู่ในนี้
          'template': template,   // ✅ สำคัญ: Fish/Pencil/IceCream
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('เลือกรูป (${templateName ?? 'template'})')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text('เลือกแหล่งรูปภาพ', style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _pick(context, ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('เลือกรูปจากแกลเลอรี'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _pick(context, ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('ถ่ายรูปใหม่'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const Spacer(),
            Text(
              'Mask: $maskAssetPath',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
