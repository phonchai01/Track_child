// lib/features/review_crop_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart' show rootBundle;

// ✅ ใช้ opencv_dart ตัวเดียวให้สุด
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../routes.dart';
import '../../widgets/app_button.dart';

// utils ของเรา
import '../../services/image/opencv_utils.dart' as utils;
import '../../services/image/preprocess_cv.dart';

class ReviewCropScreen extends StatefulWidget {
  const ReviewCropScreen({super.key});

  @override
  State<ReviewCropScreen> createState() => _ReviewCropScreenState();
}

class _ReviewCropScreenState extends State<ReviewCropScreen> {
  Uint8List? original; // ภาพต้นฉบับจากกล้อง/แกลเลอรี
  Uint8List? enhanced; // ภาพหลัง pipeline (PNG)
  String templateKey = 'fish';
  bool _didInit = false;
  bool _processing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;

    final args = (ModalRoute.of(context)?.settings.arguments ?? {}) as Map?;
    final bytes = args?['imageBytes'] as Uint8List?;
    templateKey = (args?['templateKey'] as String?) ?? 'fish';

    if (bytes != null) _setImage(bytes);
  }

  // เลือกภาพจากแกลเลอรี/กล้อง
  Future<void> _pickHere({required bool fromCamera}) async {
    try {
      final picker = ImagePicker();
      final picked = await (fromCamera
          ? picker.pickImage(source: ImageSource.camera, imageQuality: 95)
          : picker.pickImage(source: ImageSource.gallery, imageQuality: 95));
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      _setImage(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เลือกภาพไม่สำเร็จ: $e')));
    }
  }

  // ใช้ pipeline: centerCropResize -> toGray -> binarize -> encode PNG
  void _setImage(Uint8List bytes) {
    setState(() {
      original = bytes;
      enhanced = null;
      _processing = true;
    });

    // ทำงานนอกเฟรมปัจจุบัน
    Future(() {
      try {
        // 1) crop ให้เป็นสี่เหลี่ยมก่อน (ผลลัพธ์เป็น cv.Mat)
        final cv.Mat mat = PreprocessCV.centerCropResize(bytes, target: 1024);

        // 2) แปลงเป็น gray (cv.Mat)
        final cv.Mat gray = utils.toGray(mat);

        // 3) binarize (245 ~ ลบ noise พื้นหลังขาว)
        final cv.Mat bin = utils.binarize(gray, thresh: 245).$2;

        // 4) encode เป็น PNG (Uint8List) เพื่อแสดงบน UI/ส่งต่อ
        final Uint8List png = utils.imencodePng(bin);

        if (!mounted) return;
        setState(() {
          enhanced = png; // ✅ ไม่ต้อง cast
          _processing = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _processing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ประมวลผลภาพล้มเหลว: $e')));
      }
    });
  }

  // โหลด mask ตาม template (ขาว=ในเส้น, ดำ=นอกเส้น)
  Future<Uint8List> _loadMaskForTemplate(String key) async {
    final path = switch (key) {
      'fish' => 'assets/masks/fish_template.png',
      'pencil' => 'assets/masks/pencil_template.png',
      'icecream' => 'assets/masks/icecream_template.png',
      _ => 'assets/masks/fish_template.png',
    };
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }

  // ไปหน้า processing พร้อมข้อมูล
  Future<void> _onConfirm() async {
    if (_processing) return;
    final bytesToUse = enhanced ?? original;
    if (bytesToUse == null) return;

    final maskBytes = await _loadMaskForTemplate(templateKey);
    if (!mounted) return;

    Navigator.pushNamed(
      context,
      AppRoutes.processing,
      arguments: {
        'imageBytes': bytesToUse,
        'maskBytes': maskBytes,
        'templateKey': templateKey,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = (enhanced ?? original) != null && !_processing;

    return Scaffold(
      appBar: AppBar(title: const Text('ตรวจภาพ & ปรับครอป')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      color: Colors.black12,
                      child: original == null
                          ? const Center(child: Text('ไม่มีภาพ'))
                          : Image.memory(original!, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      color: Colors.black12,
                      child: _processing
                          ? const Center(child: CircularProgressIndicator())
                          : (enhanced == null
                                ? const Center(child: Text('ยังไม่ปรับภาพ'))
                                : Image.memory(enhanced!, fit: BoxFit.contain)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              text: 'ยืนยัน (ใช้ภาพที่ปรับแล้ว)',
              onPressed: () {
                if (!canConfirm) return;
                _onConfirm();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'เลือกรูป',
                    primary: false,
                    onPressed: () => _pickHere(fromCamera: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    text: 'ถ่ายรูป',
                    primary: false,
                    onPressed: () => _pickHere(fromCamera: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
