// lib/features/result/result_summary_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../../services/metrics/zscore_service.dart';
import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo.dart';

class ResultSummaryScreen extends StatefulWidget {
  const ResultSummaryScreen({super.key});

  @override
  State<ResultSummaryScreen> createState() => _ResultSummaryScreenState();
}

class _ResultSummaryScreenState extends State<ResultSummaryScreen> {
  bool _saved = false; // กันการบันทึกซ้ำ

  // ---- helpers --------------------------------------------------------------

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // ดึงค่าจาก Map โดยรองรับหลายชื่อคีย์และ case-insensitive
  num? _getFromMap(Map m, List<String> names) {
    for (final n in names) {
      if (m.containsKey(n)) return m[n] as num?;
      final lower = n.toLowerCase();
      final hit = m.entries.firstWhere(
        (e) => e.key.toString().toLowerCase() == lower,
        orElse: () => const MapEntry('', null),
      );
      if (hit.value != null) return hit.value as num?;
    }
    return null;
  }

  // ลองอ่าน field จาก object ถ้าไม่มี field จะคืน null (กัน NoSuchMethodError)
  T? _tryGet<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  /// อ่าน metrics จาก dynamic ให้ได้ Map<String,double> เสมอ
  Map<String, double> _extractMetricsDynamic(dynamic m) {
    double? h, c, blank, cotl;

    if (m is Map) {
      h = _toDouble(_getFromMap(m, ['h', 'H', 'entropy', 'entropyValue']));
      c = _toDouble(
        _getFromMap(m, ['c', 'C', 'complexity', 'dstar', 'Dstar', 'dStar']),
      );
      blank = _toDouble(
        _getFromMap(m, ['blank', 'blankCoverage', 'coverageBlank']),
      );
      cotl = _toDouble(_getFromMap(m, ['cotl', 'cotlOutside', 'outside']));
    } else if (m != null) {
      final d = m as dynamic;
      h =
          _toDouble(_tryGet(() => d.h)) ??
          _toDouble(_tryGet(() => d.H)) ??
          _toDouble(_tryGet(() => d.entropy)) ??
          _toDouble(_tryGet(() => d.entropyValue));

      c =
          _toDouble(_tryGet(() => d.c)) ??
          _toDouble(_tryGet(() => d.C)) ??
          _toDouble(_tryGet(() => d.complexity)) ??
          _toDouble(_tryGet(() => d.dstar)) ??
          _toDouble(_tryGet(() => d.Dstar)) ??
          _toDouble(_tryGet(() => d.dStar));

      blank =
          _toDouble(_tryGet(() => d.blank)) ??
          _toDouble(_tryGet(() => d.blankCoverage)) ??
          _toDouble(_tryGet(() => d.coverageBlank));

      cotl =
          _toDouble(_tryGet(() => d.cotl)) ??
          _toDouble(_tryGet(() => d.cotlOutside)) ??
          _toDouble(_tryGet(() => d.outside));
    }

    return {
      'h': h ?? 0.0,
      'c': c ?? 0.0,
      'blank': blank ?? 0.0,
      'cotl': cotl ?? 0.0,
    };
  }

  // badge แสดง Z-score
  Widget _zBadge(double z) {
    String label;
    if (z <= -2) {
      label = 'ต่ำมาก (≤ -2σ)';
    } else if (z < -1) {
      label = 'ต่ำ (-1σ)';
    } else if (z > 2) {
      label = 'สูงมาก (≥ 2σ)';
    } else if (z > 1) {
      label = 'สูง (+1σ)';
    } else {
      label = 'ปกติ';
    }
    return Chip(label: Text('${z.toStringAsFixed(2)} • $label'));
  }

  Widget _metricTile(String label, double value) {
    return ListTile(
      title: Text(label),
      trailing: Text(value.toStringAsFixed(4)),
      dense: true,
    );
  }

  // ---------------- Save history once ---------------------------------------

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_saved) return;
    _saved = true;
    _saveHistoryIfPossible();
  }

  Future<void> _saveHistoryIfPossible() async {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    try {
      final String templateKey =
          (args['templateKey'] ?? args['template'] ?? 'fish').toString();
      final dynamic metricsObj = args['metrics'];
      final ZScoreResult? z = args['zscore'] as ZScoreResult?;
      final dynamic ageRaw = args['age'];
      final int age = (ageRaw is int)
          ? ageRaw
          : int.tryParse('${ageRaw ?? ''}') ?? 0;
      final Uint8List? imageBytes = args['imageBytes'] as Uint8List?;

      // แปลง metrics
      final m = _extractMetricsDynamic(metricsObj);

      // เซฟรูปลงโฟลเดอร์ของแอป (ถ้ามี)
      String imagePath = '';
      if (imageBytes != null) {
        imagePath = await historyRepo.saveImageBytes(imageBytes);
      }

      // สร้าง record แล้วบันทึก
      final now = DateTime.now();
      final rec = HistoryRecord(
        id: now.millisecondsSinceEpoch.toString(),
        createdAt: now,
        templateKey: templateKey,
        age: age,
        h: m['h'] ?? 0,
        c: m['c'] ?? 0,
        blank: m['blank'] ?? 0,
        cotl: m['cotl'] ?? 0,
        zH: z?.h ?? 0,
        zC: z?.c ?? 0,
        zBlank: z?.blank ?? 0,
        zCotl: z?.cotl ?? 0,
        imagePath: imagePath,
      );

      await historyRepo.add(rec);
      debugPrint('✅ Saved history record: ${rec.id}');
    } catch (e) {
      debugPrint('⚠️ Save history failed: $e');
    }
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String templateKey =
        (args?['templateKey'] ?? args?['template'])?.toString() ?? '-';

    final dynamic ageRaw = args?['age'];
    final int age = (ageRaw is int)
        ? ageRaw
        : int.tryParse('${ageRaw ?? ''}') ?? 0;

    final dynamic metricsObj = args?['metrics'];
    final z = args?['zscore'] as ZScoreResult?;
    final Uint8List? previewBytes = args?['imageBytes'] as Uint8List?;
    final mm = _extractMetricsDynamic(metricsObj);

    return Scaffold(
      appBar: AppBar(title: const Text('สรุปผลการประมวลผล')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (previewBytes != null) ...[
            AspectRatio(
              aspectRatio: 1,
              child: Image.memory(previewBytes, fit: BoxFit.contain),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: ListTile(
              title: Text('เทมเพลต: $templateKey'),
              subtitle: Text('อายุ: ${age == 0 ? "-" : "$age ขวบ"}'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(title: Text('ค่าตัวชี้วัด (ดิบ)'), dense: true),
                _metricTile('H (Entropy)', mm['h'] ?? 0.0),
                _metricTile('D* / C (Complexity)', mm['c'] ?? 0.0),
                _metricTile('Blank (ในเส้น)', mm['blank'] ?? 0.0),
                _metricTile('COTL (นอกเส้น)', mm['cotl'] ?? 0.0),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (z != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Z-Score',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _zBadge(z.h),
                        _zBadge(z.c),
                        _zBadge(z.blank),
                        _zBadge(z.cotl),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ย้อนกลับ'),
          ),
        ],
      ),
    );
  }
}
