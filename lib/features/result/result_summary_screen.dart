import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/metrics/zscore_service.dart';
import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo_sqlite.dart';
import '../../services/ai/ai_coach_service.dart'; // ✅ เพิ่ม

class ResultSummaryScreen extends StatefulWidget {
  const ResultSummaryScreen({super.key});

  @override
  State<ResultSummaryScreen> createState() => _ResultSummaryScreenState();
}

class _ResultSummaryScreenState extends State<ResultSummaryScreen> {
  bool _saved = false;
  final _ai = AiCoachService(); // ✅ instance ผู้ช่วย AI
  String? _aiFeedback;
  String? _aiNextTemplate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_saved) {
      _saved = true;
      _saveHistoryIfPossible();
    }
  }

  Future<void> _saveHistoryIfPossible() async {
    final args = (ModalRoute.of(context)?.settings.arguments as Map?) ?? {};
    try {
      final profileKey = (() {
        final p = (args['profile'] as Map?)?.cast<String, dynamic>();
        final k = p?['key'] ?? p?['id'] ?? p?['profileKey'] ?? p?['name'];
        return (k ?? '').toString();
      })();

      if (profileKey.isEmpty) return;

      final templateKey = (args['templateKey'] ?? args['template'] ?? '-')
          .toString();
      final dynamic ageRaw = args['age'] ?? (args['profile'] as Map?)?['age'];
      final int age = (ageRaw is int) ? ageRaw : int.tryParse('$ageRaw') ?? 0;

      final ZScoreResult? z = args['zscore'] as ZScoreResult?;
      final Uint8List? imageBytes = args['imageBytes'] as Uint8List?;
      final metricsObj = args['metrics'];
      final index = (args['index'] is num)
          ? (args['index'] as num).toDouble()
          : z?.zSum;
      final level = args['level'] as String? ?? z?.level;

      final m = _extractMetricsDynamic(metricsObj);

      String imagePath = '';
      if (imageBytes != null) {
        imagePath = await HistoryRepoSqlite.I.saveImageBytes(
          imageBytes,
          profileKey: profileKey,
        );
      }

      final now = DateTime.now();
      final rec = HistoryRecord(
        id: now.millisecondsSinceEpoch.toString(),
        createdAt: now,
        profileKey: profileKey,
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
        zSum: index ?? 0,
        level: level ?? '-',
        imagePath: imagePath,
      );

      await HistoryRepoSqlite.I.add(profileKey, rec);
      debugPrint('✅ [HIS] saved ${rec.id} for $profileKey');
    } catch (e) {
      debugPrint('⚠️ Save history failed: $e');
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final templateKey = (args?['templateKey'] ?? args?['template'] ?? '-')
        .toString();
    final dynamic ageRaw = args?['age'] ?? (args?['profile'] as Map?)?['age'];
    final int age = (ageRaw is int) ? ageRaw : int.tryParse('$ageRaw') ?? 0;
    final z = args?['zscore'] as ZScoreResult?;
    final index = (args?['index'] is num)
        ? (args?['index'] as num).toDouble()
        : z?.zSum;
    final level = args?['level'] as String? ?? z?.level;
    final Uint8List? previewBytes = args?['imageBytes'] as Uint8List?;
    final m = _extractMetricsDynamic(args?['metrics']);

    // 🔹 เรียก AI ครั้งแรก (โหลด feedback และ next suggestion)
    if (_aiFeedback == null && index != null && z != null) {
      _ai
          .buildParentFeedback(
            templateName: templateKey,
            age: age,
            entropy: m['h'] ?? 0,
            complexity: m['c'] ?? 0,
            blank: m['blank'] ?? 0,
            cotl: m['cotl'] ?? 0,
            index: index,
            levelText: level ?? '-',
          )
          .then((txt) {
            if (mounted) setState(() => _aiFeedback = txt);
          });

      _ai
          .suggestNextTemplate(
            currentTemplate: templateKey,
            zSum: index,
            cotl: m['cotl'] ?? 0,
            blank: m['blank'] ?? 0,
          )
          .then((txt) {
            if (mounted) setState(() => _aiNextTemplate = txt);
          });
    }

    return Scaffold(
      appBar: AppBar(title: Text('ผลการประเมิน · ${_title(templateKey)}')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8F5FF), Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (previewBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(previewBytes, fit: BoxFit.contain),
              ),
            const SizedBox(height: 12),
            Text(
              'อายุ $age ขวบ  |  เทมเพลต ${_title(templateKey)}',
              style: const TextStyle(fontSize: 16),
            ),
            const Divider(height: 20),

            _card(
              'ค่าชี้วัดดิบ',
              Column(
                children: [
                  _metricTile('Blank (ในเส้น)', m['blank']),
                  _metricTile('COTL (นอกเส้น)', m['cotl']),
                  _metricTile('Entropy (normalized)', m['h']),
                  _metricTile('Complexity', m['c']),
                ],
              ),
            ),

            const SizedBox(height: 12),

            _card(
              'ดัชนีรวม (Index – raw)',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _metricTile('Index', index),
                  const SizedBox(height: 8),
                  const Text(
                    'การแปลผลโดยภาพรวม:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  _buildStarLevel(level),
                  const SizedBox(height: 4),
                  Text(
                    level ?? '-',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (_aiFeedback != null)
              _card(
                'คำแนะนำจากผู้ช่วยอัตโนมัติ',
                Text(_aiFeedback!, style: const TextStyle(height: 1.4)),
              )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              ),

            if (_aiNextTemplate != null)
              _card(
                'เทมเพลตถัดไปที่แนะนำ',
                Text(_aiNextTemplate!, style: const TextStyle(height: 1.3)),
              ),

            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.home_outlined),
              label: const Text('กลับไปหน้าเลือกเทมเพลต'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Helper Widgets ----------------
  Widget _card(String title, Widget child) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, double? value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value?.toStringAsFixed(4) ?? '-'),
        ],
      ),
    );
  }

  // ⭐ ดาวประเมินระดับ
  Widget _buildStarLevel(String? level) {
    if (level == null || level.trim().isEmpty) return _stars(0);
    final s = level.toLowerCase();
    int stars;
    if (s.contains('สูง')) {
      stars = s.contains('มาก') ? 5 : 4;
    } else if (s.contains('ต่ำ')) {
      stars = s.contains('มาก') ? 1 : 2;
    } else {
      stars = 3;
    }
    return _stars(stars);
  }

  Widget _stars(int filled) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < filled ? Icons.star_rounded : Icons.star_border_rounded,
          color: i < filled ? Colors.amber : Colors.grey.shade400,
          size: 28,
        ),
      ),
    );
  }

  // ---------------- Data extract helpers ----------------
  Map<String, double> _extractMetricsDynamic(dynamic m) {
    double? h, c, blank, cotl;
    if (m is Map) {
      h = _toDouble(m['h'] ?? m['H'] ?? m['entropy']);
      c = _toDouble(m['c'] ?? m['C'] ?? m['complexity']);
      blank = _toDouble(m['blank']);
      cotl = _toDouble(m['cotl']);
    } else if (m != null) {
      final d = m as dynamic;
      h = _toDouble(_try(() => d.h));
      c = _toDouble(_try(() => d.c));
      blank = _toDouble(_try(() => d.blank));
      cotl = _toDouble(_try(() => d.cotl));
    }
    return {'h': h ?? 0, 'c': c ?? 0, 'blank': blank ?? 0, 'cotl': cotl ?? 0};
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  T? _try<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  String _title(String key) {
    switch (key.toLowerCase()) {
      case 'fish':
        return 'ปลา';
      case 'pencil':
        return 'ดินสอ';
      case 'icecream':
      case 'ice_cream':
        return 'ไอศกรีม';
      default:
        return key;
    }
  }
}
