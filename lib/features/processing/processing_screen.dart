// lib/features/processing/processing_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../services/metrics/zscore_service.dart';
import '../../services/metrics/masks_cv.dart'
    show shrinkInsideForSafeCount, ensureWhiteIsInside;

import '../../services/metrics/blank_cv.dart';
import '../../services/metrics/cotl_cv.dart';
import '../../services/metrics/entropy_cv.dart';
import '../../services/metrics/complexity_cv.dart';

// สำหรับบันทึกประวัติ (แบบไฟล์ JSON/รูปใน Documents)
import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    this.imageBytes,
    this.imageAssetPath,
    required this.maskAssetPath,
    this.templateName,
    this.imageName,
  });

  final Uint8List? imageBytes;
  final String? imageAssetPath;
  final String maskAssetPath; // e.g. assets/masks/fish_mask.png
  final String? templateName; // label แสดงผล
  final String? imageName;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String? _error;

  // preview
  Uint8List? _previewBytes;

  // metrics (raw)
  double? _blank, _cotl, _entropy, _complexity;

  // Index (raw) + ระดับ
  double? _indexRaw;
  String? _level;

  // ช่วงอ้างอิงของ Index(raw) ต่อกลุ่มอายุ×เทมเพลต
  double? _lowCut, _highCut, _mu, _sigma;

  // profile/template
  late String _classKey; // 'Fish' | 'Pencil' | 'IceCream'
  late int _age; // 4 หรือ 5
  String _profileKey = ''; // owner ของประวัติ

  bool _started = false;
  late Future<void> _svcWarmup;

  @override
  void initState() {
    super.initState();
    _svcWarmup = ZScoreService.instance.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;
      _started = true;
      _run();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final profile = (args?['profile'] as Map?)?.cast<String, dynamic>();

    _profileKey =
        (profile?['key'] ??
                profile?['id'] ??
                profile?['profileKey'] ??
                profile?['name'] ??
                '')
            .toString();

    final rawTemplate =
        (args?['template'] ?? args?['templateKey'] ?? widget.templateName ?? '')
            .toString();
    _classKey = _resolveClassKey(rawTemplate);

    final dynamic ageRaw = profile?['age'];
    _age = (ageRaw is int) ? ageRaw : int.tryParse('${ageRaw ?? '0'}') ?? 0;

    debugPrint(
      '>> args -> classKey=$_classKey age=$_age profileKey=$_profileKey',
    );
  }

  // ---------- Helpers ----------
  String _resolveClassKey(String raw) {
    switch (raw) {
      case 'ปลา':
      case 'fish':
      case 'Fish':
        return 'Fish';
      case 'ดินสอ':
      case 'pencil':
      case 'Pencil':
        return 'Pencil';
      case 'ไอศกรีม':
      case 'icecream':
      case 'IceCream':
      case 'ice_cream':
        return 'IceCream';
      default:
        return raw;
    }
  }

  String _templateLabelFromKey(String key) => switch (key) {
    'Fish' => 'ปลา',
    'Pencil' => 'ดินสอ',
    'IceCream' => 'ไอศกรีม',
    _ => key,
  };

  Future<cv.Mat> _decodeBgr(Uint8List bytes) async =>
      cv.imdecode(bytes, cv.IMREAD_COLOR);

  Uint8List _matToPng(cv.Mat m) {
    final enc = cv.imencode('.png', m);
    return Uint8List.fromList(enc.$2.toList());
  }

  Future<Uint8List> _loadAssetBytes(String path) async {
    final b = await rootBundle.load(path);
    return b.buffer.asUint8List();
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
    if (m.channels > 1) m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
    final bin = cv.threshold(m, 127.0, 255.0, cv.THRESH_BINARY).$2;
    return bin;
  }

  Future<ImageSource?> _askImageSource() async {
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
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('เลือกรูปจากแกลเลอรี'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('ถ่ายรูปด้วยกล้อง'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Pipeline ----------
  Future<void> _run() async {
    try {
      // 1) โหลดภาพจริง
      cv.Mat bgr;
      if (widget.imageBytes != null) {
        bgr = await _decodeBgr(widget.imageBytes!);
      } else if (widget.imageAssetPath != null) {
        bgr = await _decodeBgr(await _loadAssetBytes(widget.imageAssetPath!));
      } else {
        final src = await _askImageSource();
        if (src == null) throw Exception('ยกเลิกการเลือกรูปภาพ');
        final XFile? picked = await ImagePicker().pickImage(source: src);
        if (picked == null) throw Exception('ยังไม่ได้เลือกรูปจาก $src');
        bgr = await _decodeBgr(await picked.readAsBytes());
      }

      // preview (resize ให้เบาลง)
      const maxW = 900;
      if (bgr.cols > maxW) {
        final s = maxW / bgr.cols;
        bgr = cv.resize(bgr, (maxW, (bgr.rows * s).round()));
      }
      final preview = _matToPng(bgr);

      // 2) โหลด mask ภายในเส้น + ภายนอกเส้น
      final maskInRaw = await _loadBinaryMask(widget.maskAssetPath);
      final insideRaw = ensureWhiteIsInside(maskInRaw);
      final inside = cv.resize(insideRaw, (
        bgr.cols,
        bgr.rows,
      ), interpolation: cv.INTER_NEAREST);
      final insideSafe = shrinkInsideForSafeCount(inside, px: 1);

      final maskOutPath = widget.maskAssetPath
          .replaceAll('assets/masks/', 'assets/masks_out/')
          .replaceAll('_mask', '_mask_out');

      cv.Mat insideForCotlSafe;
      try {
        final maskOutRaw = await _loadBinaryMask(maskOutPath);
        final insideFromOut = ensureWhiteIsInside(cv.bitwiseNOT(maskOutRaw));
        final insideFromOutResized = cv.resize(insideFromOut, (
          bgr.cols,
          bgr.rows,
        ), interpolation: cv.INTER_NEAREST);
        insideForCotlSafe = shrinkInsideForSafeCount(
          insideFromOutResized,
          px: 1,
        );
      } catch (_) {
        insideForCotlSafe = insideSafe;
      }

      // 3) channels
      final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
      final sat = _extractS(bgr);

      // 4) metrics (raw)
      final blank = await computeBlank(gray, sat, insideSafe);
      final ent = EntropyCV.computeNormalized(bgr, mask: insideSafe);
      final comp = ComplexityCV.edgeDensity(bgr, mask: insideSafe);
      final cotl = await computeCotl(gray, sat, insideForCotlSafe);

      // 5) คำนวณ Index (raw) + Z-sum
      await _svcWarmup;
      final raw = await ZScoreService.instance.computeRaw(
        templateKey: _classKey,
        age: _age,
        h: ent,
        c: comp,
        blank: blank,
        cotl: cotl,
      );
      final z = await ZScoreService.instance.compute(
        templateKey: _classKey,
        age: _age,
        h: ent,
        c: comp,
        blank: blank,
        cotl: cotl,
      );

      // 6) บันทึกประวัติ (PNG + record)
      try {
        final Uint8List pngBytes = Uint8List.fromList(
          cv.imencode('.png', bgr).$2.toList(),
        );

        String imagePath = '';
        if (_profileKey.isNotEmpty) {
          imagePath = await HistoryRepo.I.saveImageBytes(
            pngBytes,
            profileKey: _profileKey,
          );
        }

        final now = DateTime.now();
        final rec = HistoryRecord(
          id: now.millisecondsSinceEpoch.toString(),
          createdAt: now,
          profileKey: _profileKey,
          templateKey: _classKey,
          age: _age,
          h: ent,
          c: comp,
          blank: blank,
          cotl: cotl,
          // z-values (มาตรฐาน)
          zH: z.zH,
          zC: z.zC,
          zBlank: z.zBlank,
          zCotl: z.zCotl,
          zSum: z.zSum,
          // ระดับและไฟล์
          level: raw.level,
          imagePath: imagePath,
        );

        await HistoryRepo.I.add(_profileKey, rec);
        debugPrint('✅ [HIS] saved ${rec.id} for profile=$_profileKey');
      } catch (e) {
        debugPrint('⚠️ [HIS] save failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _previewBytes = preview;
        _blank = blank;
        _cotl = cotl;
        _entropy = ent;
        _complexity = comp;

        _indexRaw = raw.index;
        _level = raw.level;

        _lowCut = raw.lowCut;
        _highCut = raw.highCut;
        _mu = raw.mu;
        _sigma = raw.sigma;

        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  // ⭐ แปลงข้อความ level -> จำนวนดาว (1..5) แล้ววาดเป็นไอคอน
  Widget _buildStarLevel(String? level) {
    if (level == null || level.trim().isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(
            Icons.star_border_rounded,
            size: 28,
            color: Colors.grey.shade400,
          ),
        ),
      );
    }

    final s = level.toLowerCase();
    int stars = 3; // พื้นฐาน = ปกติ

    // รองรับทั้งไทย/อังกฤษ
    final very = s.contains('มาก'); // very
    final hi =
        s.contains('สูง') ||
        s.contains('ดีกว่า') ||
        s.contains('above') ||
        s.contains('better');
    final low =
        s.contains('ต่ำ') ||
        s.contains('ต่ำกว่า') ||
        s.contains('below') ||
        s.contains('worse');
    final normal =
        s.contains('ปกติ') ||
        s.contains('เกณฑ์') ||
        s.contains('within') ||
        s.contains('normal') ||
        s.contains('standard');

    if (hi && very) {
      stars = 5;
    } else if (hi) {
      stars = 4;
    } else if (low && very) {
      stars = 1;
    } else if (low) {
      stars = 2;
    } else if (normal) {
      stars = 3;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < stars ? Icons.star_rounded : Icons.star_border_rounded,
          size: 28,
          color: i < stars ? Colors.amber : Colors.grey.shade400,
        ),
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templateLabel =
        widget.templateName ?? _templateLabelFromKey(_classKey);

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

    final waiting =
        _blank == null ||
        _cotl == null ||
        _entropy == null ||
        _complexity == null;

    if (waiting) {
      return Scaffold(
        appBar: AppBar(title: Text('ประมวลผล · $templateLabel')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('ผลการประเมิน · $templateLabel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_previewBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_previewBytes!, fit: BoxFit.contain),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'อายุ $_age ขวบ  |  เทมเพลต $templateLabel',
            style: theme.textTheme.titleMedium,
          ),

          const Divider(height: 28),

          Text('ค่าชี้วัดดิบ', style: theme.textTheme.titleLarge),
          _metricRow('Blank (ในเส้น)', _blank!),
          _metricRow('COTL (นอกเส้น)', _cotl!),
          _metricRow('Entropy (normalized)', _entropy!),
          _metricRow('Complexity', _complexity!),

          const Divider(height: 28),

          Text('ดัชนีรวม (Index – raw)', style: theme.textTheme.titleLarge),
          _metricRow('Index', _indexRaw ?? 0),
          if (_lowCut != null && _highCut != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
              child: Text(
                'ช่วงมาตรฐานของกลุ่ม (μ±σ): '
                '[${_lowCut!.toStringAsFixed(4)}, ${_highCut!.toStringAsFixed(4)}]'
                '${_mu != null && _sigma != null ? '  (μ=${_mu!.toStringAsFixed(4)}, σ=${_sigma!.toStringAsFixed(4)})' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),

          const SizedBox(height: 10),
          const Text(
            'การแปลผลโดยภาพรวม',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _buildStarLevel(_level), // ⭐ แสดงดาวตามระดับ
          const SizedBox(height: 4),
          Text(
            _level ?? '-',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),

          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pop(context), // ย้อนกลับไป TemplatePicker
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

  String _guessTemplateName(String maskPath) {
    final file = maskPath.split('/').last.toLowerCase();
    if (file.contains('fish')) return 'ปลา';
    if (file.contains('pencil')) return 'ดินสอ';
    if (file.contains('ice')) return 'ไอศกรีม';
    return file;
  }
}
