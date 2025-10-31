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
  bool _saved = false; // ป้องกันบันทึกซ้ำ

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
      final int age =
          (ageRaw is int) ? ageRaw : int.tryParse('${ageRaw ?? ''}') ?? 0;
      final Uint8List? imageBytes = args['imageBytes'] as Uint8List?;
      final double? index =
          (args['index'] is num) ? (args['index'] as num).toDouble() : null;
      final String? level = args['level'] as String?;

      // ดึง metrics จาก args
      final m = _extractMetricsDynamic(metricsObj);

      // เซฟรูป (ถ้ามี)
      String imagePath = '';
      if (imageBytes != null) {
        imagePath = await historyRepo.saveImageBytes(imageBytes);
      }

      // บันทึก record
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
        zH: z?.zH ?? 0,
        zC: z?.zC ?? 0,
        zBlank: z?.zBlank ?? 0,
        zCotl: z?.zCotl ?? 0,
        zSum: index ?? z?.zSum ?? 0,
        level: level ?? z?.level ?? '-',
        imagePath: imagePath,
      );

      await historyRepo.add(rec);
      debugPrint('✅ Saved history record: ${rec.id}');
    } catch (e) {
      debugPrint('⚠️ Save history failed: $e');
    }
  }

  // ---------------- Helper ----------------
  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

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

  T? _tryGet<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  Map<String, double> _extractMetricsDynamic(dynamic m) {
    double? h, c, blank, cotl;
    if (m is Map) {
      h = _toDouble(_getFromMap(m, ['h', 'H', 'entropy']));
      c = _toDouble(_getFromMap(m, ['c', 'C', 'complexity']));
      blank = _toDouble(_getFromMap(m, ['blank']));
      cotl = _toDouble(_getFromMap(m, ['cotl']));
    } else if (m != null) {
      final d = m as dynamic;
      h = _toDouble(_tryGet(() => d.h));
      c = _toDouble(_tryGet(() => d.c));
      blank = _toDouble(_tryGet(() => d.blank));
      cotl = _toDouble(_tryGet(() => d.cotl));
    }
    return {
      'h': h ?? 0.0,
      'c': c ?? 0.0,
      'blank': blank ?? 0.0,
      'cotl': cotl ?? 0.0,
    };
  }

  Widget _metricTile(String label, double value) {
    return ListTile(
      title: Text(label),
      trailing: Text(value.toStringAsFixed(4)),
      dense: true,
    );
  }

  Widget _zBadge(String label, double z) {
    String level;
    if (z <= -2) {
      level = 'ต่ำมาก (≤ -2σ)';
    } else if (z < -1) {
      level = 'ต่ำ (-1σ)';
    } else if (z > 2) {
      level = 'สูงมาก (≥ 2σ)';
    } else if (z > 1) {
      level = 'สูง (+1σ)';
    } else {
      level = 'ปกติ';
    }
    return Chip(label: Text('$label: ${z.toStringAsFixed(2)} • $level'));
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final String templateKey =
        (args?['templateKey'] ?? args?['template'])?.toString() ?? '-';

    final dynamic ageRaw = args?['age'];
    final int age =
        (ageRaw is int) ? ageRaw : int.tryParse('${ageRaw ?? ''}') ?? 0;

    final dynamic metricsObj = args?['metrics'];
    final z = args?['zscore'] as ZScoreResult?;
    final double? index =
        (args?['index'] is num) ? (args?['index'] as num).toDouble() : z?.zSum;
    final String? level = args?['level'] as String? ?? z?.level;
    final Uint8List? previewBytes = args?['imageBytes'] as Uint8List?;
    final mm = _extractMetricsDynamic(metricsObj);

    return Scaffold(
      appBar: AppBar(title: const Text('สรุปผลการประเมิน')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (previewBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
                _metricTile('C (Complexity)', mm['c'] ?? 0.0),
                _metricTile('Blank (ในเส้น)', mm['blank'] ?? 0.0),
                _metricTile('COTL (นอกเส้น)', mm['cotl'] ?? 0.0),
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
                    const Text('Z-Score',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _zBadge('Entropy (H)', z.zH),
                        _zBadge('Complexity (C)', z.zC),
                        _zBadge('Blank', z.zBlank),
                        _zBadge('COTL', z.zCotl),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ดัชนีรวม (Z-sum)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('ค่า Index: ${index?.toStringAsFixed(3) ?? "-"}'),
                    const SizedBox(height: 6),
                    Chip(label: Text('การแปลผล: ${level ?? "-"}')),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('ย้อนกลับ'),
          ),
        ],
      ),
    );
  }
}
