// lib/features/processing/processing_screen.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../services/metrics/metrics_bundle.dart';
import '../../services/metrics/zscore_service.dart';
import '../../widgets/loading_indicator.dart';
import '../result/result_summary_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({super.key});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  bool _started = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _run();
  }

  /// แปลง template ชื่อไทย/อื่น ๆ -> key สำหรับไฟล์ใน assets/masks/
  String _normalizeTemplateKey(String raw) {
    final r = raw.trim().toLowerCase();
    const mapping = {
      'ปลา': 'fish',
      'ดินสอ': 'pencil',
      'ไอศกรีม': 'icecream',
      'ไอติม': 'icecream',
    };
    return mapping[r] ?? r;
  }

  /// โหลด bytes จาก asset path
  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    debugPrint('✅ Loaded asset: $assetPath (${data.lengthInBytes} bytes)');
    return data.buffer.asUint8List();
  }

  /// เดาไฟล์ mask จาก key หลายชื่อ
  Future<Uint8List> _loadMaskBytesByKey(String templateKey) async {
    final key = _normalizeTemplateKey(templateKey);
    final candidates = <String>[
      'assets/masks/${key}_mask.png',
      'assets/masks/${key}_mask.jpg',
      'assets/masks/$key.png',
      'assets/masks/$key.jpg',
    ];

    FlutterError? lastErr;
    for (final path in candidates) {
      try {
        final data = await rootBundle.load(path);
        debugPrint(
          '✅ Loaded mask asset by key: $path  (${data.lengthInBytes} bytes)',
        );
        return data.buffer.asUint8List();
      } on FlutterError catch (e) {
        lastErr = e;
        debugPrint('❌ Not found: $path');
      }
    }

    final msg = StringBuffer()
      ..writeln('ไม่พบไฟล์ mask ใน assets สำหรับ templateKey="$templateKey"')
      ..writeln(
        'โปรดตรวจสอบ pubspec.yaml ว่าประกาศ assets/masks/ ถูกต้อง และมีไฟล์ชื่อใดชื่อหนึ่งดังนี้:',
      )
      ..writeAll(candidates.map((e) => ' - $e\n'));
    if (lastErr != null) {
      msg.writeln('\nรายละเอียดระบบ: ${lastErr.message}');
    }
    throw Exception(msg.toString());
  }

  Future<void> _run() async {
    try {
      final args =
          (ModalRoute.of(context)?.settings.arguments as Map?) ?? const {};
      debugPrint('➡️ Processing args: $args');

      // ---- รับพารามิเตอร์จากหน้าก่อน ----
      final Uint8List? imageBytesArg = args['imageBytes'] as Uint8List?;
      final String? imagePathArg = (args['imagePath'] ?? args['path'])
          ?.toString();

      String templateKey =
          (args['templateKey'] ?? args['templateId'] ?? args['template'])
              ?.toString() ??
          'fish';
      final String? maskAsset =
          args['maskAsset'] as String?; // ✅ ใหม่: พาธไฟล์ mask ตรง ๆ

      // --- เตรียมรูปเป็น bytes ---
      late Uint8List imageBytes;
      if (imageBytesArg != null) {
        imageBytes = imageBytesArg;
      } else if (imagePathArg != null && imagePathArg.isNotEmpty) {
        final file = File(imagePathArg);
        if (!file.existsSync()) {
          throw Exception('ไม่พบไฟล์รูปภาพที่ path: $imagePathArg');
        }
        imageBytes = await file.readAsBytes();
      } else {
        throw Exception('ต้องส่ง imageBytes หรือ imagePath อย่างใดอย่างหนึ่ง');
      }
      debugPrint('✅ Loaded image bytes: ${imageBytes.length}');

      // --- โหลด mask ตามลำดับความสำคัญ: maskBytes > maskAsset > templateKey ---
      templateKey = _normalizeTemplateKey(templateKey);

      final Uint8List maskBytes =
          (args['maskBytes'] as Uint8List?) ??
          (maskAsset != null ? await _loadAssetBytes(maskAsset) : null) ??
          await _loadMaskBytesByKey(templateKey);

      // --- คำนวณ metrics ---
      final bundle = MetricsBundle();
      final result = await bundle.computeAll(
        imageBytes: imageBytes,
        maskBytes: maskBytes,
      );
      debugPrint(
        '✅ Metrics: H=${result.h}, D*=${result.dstar}, Blank=${result.blank}, COTL=${result.cotl}',
      );

      // --- คำนวณ Z-score ---
      final z = await ZScoreService.instance.compute(
        templateKey: templateKey,
        age: int.tryParse('${args['age'] ?? 4}') ?? 4,
        h: result.h,
        c: result.dstar,
        blank: result.blank,
        cotl: result.cotl,
      );

      if (!mounted) return;

      // --- ไปหน้าสรุปผล ---
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ResultSummaryScreen(),
          settings: RouteSettings(
            arguments: {
              ...args,
              'templateKey': templateKey,
              'zscore': z,
              'metrics': {
                'h': result.h,
                'c': result.dstar,
                'blank': result.blank,
                'cotl': result.cotl,
              },
              'imageBytes': imageBytes,
              'maskBytes': maskBytes,
            },
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('❌ Processing error: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Processing')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            'เกิดข้อผิดพลาดระหว่างประมวลผล:\n\n$_error',
            textAlign: TextAlign.left,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Processing')),
      body: const Center(child: LoadingIndicator()),
    );
  }
}
