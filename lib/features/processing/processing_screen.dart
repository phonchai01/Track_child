// lib/features/processing/processing_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../services/metrics/masks_cv.dart'
    show shrinkInsideForSafeCount, ensureWhiteIsInside;

import '../../services/metrics/blank_cv.dart';
import '../../services/metrics/cotl_cv.dart';
import '../../services/metrics/entropy_cv.dart';
import '../../services/metrics/complexity_cv.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    this.imageBytes,
    this.imageAssetPath,
    required this.maskAssetPath,
    this.templateName,
    this.showInlineResult = true,
    required String templateAssetPath,
    this.imageName,
  });

  final Uint8List? imageBytes;
  final String? imageAssetPath;
  final String maskAssetPath;
  final String? templateName;
  final bool showInlineResult;
  final String? imageName;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  bool _started = false;
  String? _error;

  double? _blank, _cotl, _entropy, _complexity;

  // ✅ เพิ่มตัวแปรเก็บภาพเพื่อพรีวิว
  Uint8List? _previewBytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<cv.Mat> _decodeBgr(Uint8List bytes) async {
    return cv.imdecode(bytes, cv.IMREAD_COLOR);
  }

  // ✅ ช่วยแปลง Mat -> PNG bytes เพื่อเอาไปแสดงบน UI
  Uint8List _matToPng(cv.Mat m) {
    final enc = cv.imencode('.png', m); // (bool ok, Uint8List buf)
    return Uint8List.fromList(enc.$2.toList());
  }

  Future<Uint8List> _loadAssetBytes(String path) async {
    try {
      final b = await rootBundle.load(path);
      return b.buffer.asUint8List();
    } catch (_) {
      throw Exception('Asset not found or empty: $path');
    }
  }

  String _guessTemplateName(String maskPath) {
    final file = maskPath.split('/').last.toLowerCase();
    if (file.contains('fish')) return 'ปลา';
    if (file.contains('pencil')) return 'ดินสอ';
    if (file.contains('ice')) return 'ไอศกรีม';
    return file;
  }

  cv.Mat _extractS(cv.Mat bgr) {
    final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
    try {
      return cv.extractChannel(hsv, 1);
    } catch (_) {
      final c = cv.split(hsv);
      return c[1];
    }
  }

  Future<cv.Mat> _loadBinaryMask(String path) async {
    final bytes = await _loadAssetBytes(path);
    cv.Mat m = await _decodeBgr(bytes);
    if (m.channels > 1) {
      m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
    }
    final bin = cv.threshold(m, 127.0, 255.0, cv.THRESH_BINARY).$2;
    return bin;
  }

  Future<ImageSource?> _askImageSource() async {
    final templateLabel =
        widget.templateName ?? _guessTemplateName(widget.maskAssetPath);
    if (!mounted) return null;
    return await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'เลือกแหล่งรูปภาพ',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: Colors.black12.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('เทมเพลตที่เลือก: $templateLabel'),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('เลือกรูปจากแกลเลอรี'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('ถ่ายรูปด้วยกล้อง'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    try {
      // 1) โหลดภาพจริง
      cv.Mat bgr;
      if (widget.imageBytes != null) {
        bgr = await _decodeBgr(widget.imageBytes!);
      } else if (widget.imageAssetPath != null) {
        final data = await _loadAssetBytes(widget.imageAssetPath!);
        bgr = await _decodeBgr(data);
      } else {
        final src = await _askImageSource();
        if (src == null) throw Exception('ยกเลิกการเลือกรูปภาพ');
        final XFile? picked = await ImagePicker().pickImage(source: src);
        if (picked == null) throw Exception('ยังไม่ได้เลือกรูปจาก $src');
        bgr = await _decodeBgr(await picked.readAsBytes());
      }

      // ✅ ทำพรีวิว (ลดขนาดก่อนเล็กน้อยเพื่อความลื่น)
      final maxW = 900;
      if (bgr.cols > maxW) {
        final scale = maxW / bgr.cols;
        bgr = cv.resize(bgr, (maxW, (bgr.rows * scale).round()));
      }
      final preview = _matToPng(bgr);

      // 2) โหลด MASK (แยกในเส้น/นอกเส้น)
      // ---- ภายในเส้น: ใช้ assets/masks/*.png ----
      final maskInRaw = await _loadBinaryMask(widget.maskAssetPath);
      final insideRaw = ensureWhiteIsInside(maskInRaw); // ให้แน่ใจว่า "ขาว=ภายใน"
      final inside = cv.resize(
        insideRaw,
        (bgr.cols, bgr.rows),
        interpolation: cv.INTER_NEAREST, // รักษาบิตของมาสก์
      );
      final insideSafe = shrinkInsideForSafeCount(inside, px: 1); // กันติดเส้นพิมพ์

      // ---- ภายนอกเส้น (สำหรับ COTL): ใช้ assets/masks_out/*_mask_out.png ----
      final maskOutPath = widget.maskAssetPath
          .replaceAll('assets/masks/', 'assets/masks_out/')
          .replaceAll('_mask', '_mask_out');

      cv.Mat insideForCotlSafe;
      try {
        final maskOutRaw = await _loadBinaryMask(maskOutPath);
        // ใน masks_out: "ดำ=ภายใน, ขาว=ภายนอก" → กลับให้เป็น "ขาว=ภายใน"
        final insideFromOut = ensureWhiteIsInside(cv.bitwiseNOT(maskOutRaw));
        final insideFromOutResized = cv.resize(
          insideFromOut,
          (bgr.cols, bgr.rows),
          interpolation: cv.INTER_NEAREST,
        );
        insideForCotlSafe = shrinkInsideForSafeCount(insideFromOutResized, px: 1);
      } catch (_) {
        // ถ้าไม่มีไฟล์ใน masks_out ให้ fallback ใช้ insideSafe
        insideForCotlSafe = insideSafe;
      }

      // 3) channels
      final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
      final sat  = _extractS(bgr);

      // 4) metrics
      // ---- วัด "ภายในเส้น" ----
      final blank = await computeBlank(gray, sat, insideSafe);
      final ent   = EntropyCV.computeNormalized(bgr, mask: insideSafe);
      final comp  = ComplexityCV.edgeDensity(bgr, mask: insideSafe);

      // ---- วัด "นอกเส้น" (COTL) ด้วยมาสก์ภายนอกที่ปรับกลับแล้ว ----
      final cotl  = await computeCotl(gray, sat, insideForCotlSafe);
      // ถ้าต้องการแหวน 3 มม. แบบฟิกซ์จริง ๆ ใช้อันนี้แทน:
      // final cotl = await computeCotl3mm(
      //   gray, sat, insideForCotlSafe,
      //   pixelsPerMM: 300.0 / 25.4, // ตัวอย่าง 300 dpi
      //   ringMM: 3.0,
      // );

      if (!mounted) return;
      setState(() {
        _previewBytes = preview;
        _blank = blank;
        _cotl = cotl;
        _entropy = ent;
        _complexity = comp;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templateLabel =
        widget.templateName ?? _guessTemplateName(widget.maskAssetPath);

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('ประมวลผล · $templateLabel')),
        body: Center(
          child: Text(
            'เกิดข้อผิดพลาด:\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (_blank == null ||
        _cotl == null ||
        _entropy == null ||
        _complexity == null) {
      return Scaffold(
        appBar: AppBar(title: Text('ประมวลผล · $templateLabel')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('ผลการประมวลผล · $templateLabel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ✅ พรีวิวรูปภาพ
          if (_previewBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  color: Colors.black12.withOpacity(0.05),
                  alignment: Alignment.center,
                  child: Image.memory(_previewBytes!, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ป้ายชื่อเทมเพลต
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black12.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.label_important_outline, size: 18),
                const SizedBox(width: 8),
                Text('เทมเพลตที่เลือก: $templateLabel'),
              ],
            ),
          ),

          Text('สรุปค่าชี้วัด', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _metricRow('Blank (ในเส้น)', _blank!),
          _metricRow('COTL (นอกเส้น)', _cotl!),
          _metricRow('Entropy (normalized)', _entropy!),
          _metricRow('Complexity', _complexity!),
          const SizedBox(height: 24),
          Text('แนวโน้มค่าที่คาดหวัง:', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '- เทมเพลตเปล่า: Blank ≈ 1.00, COTL ≈ 0.00, Entropy ต่ำ, Edge ต่ำ\n'
            '- ภาพระบาย: Blank ≈ 0.35–0.55, COTL ≈ 0.03–0.12, Entropy/Edge สูงขึ้น',
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            icon: const Icon(Icons.home_outlined),
            label: const Text('กลับไปหน้าเลือกเทมเพลต'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.black12.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value.toStringAsFixed(4)),
        ],
      ),
    );
  }
}
