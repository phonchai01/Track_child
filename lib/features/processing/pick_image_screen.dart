// lib/features/processing/pick_image_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import './processing_screen.dart';

class PickImageScreen extends StatelessWidget {
  const PickImageScreen({
    super.key,
    required this.maskAssetPath, // <- ใช้ mask สำเร็จรูป
    this.templateName, // ไว้โชว์ชื่อ/ดีบั๊ก
  });

  final String maskAssetPath; // เช่น 'assets/masks/fish_mask.png'
  final String? templateName;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    // กันพลาด: ถ้า mask ว่าง ให้ฟ้องก่อน
    if (maskAssetPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('maskAssetPath ว่าง: กรุณาส่งพาธของ mask'),
        ),
      );
      return;
    }

    final XFile? picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;

    final Uint8List bytes = await picked.readAsBytes();

    // ไปหน้า Processing พร้อม bytes (รูปจริง) + maskAssetPath (mask ภายในเส้น)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          imageBytes: bytes,
          maskAssetPath: maskAssetPath, // ✅ ใช้ mask
          showInlineResult: true,
          templateAssetPath: '',
        ),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
