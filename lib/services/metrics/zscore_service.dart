import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// คีย์เทมเพลตให้ใช้ตาม masks: "ไอศกรีม", "ปลา", "ดินสอ"
class _Stats {
  final double mean;
  final double sd;
  const _Stats(this.mean, this.sd);
  double z(double x) => sd == 0 ? 0.0 : (x - mean) / sd;
}

class ZScoreResult {
  final double h;
  final double c;
  final double blank;
  final double cotl;
  const ZScoreResult({required this.h, required this.c, required this.blank, required this.cotl});
}

class _MetricStatsBundle {
  final _Stats h, c, blank, cotl;
  const _MetricStatsBundle({required this.h, required this.c, required this.blank, required this.cotl});
}

/// Singleton service
class ZScoreService {
  static final ZScoreService instance = ZScoreService._();
  ZScoreService._();

  /// Map[template][age] -> Bundle ของสถิติ
  final Map<String, Map<int, _MetricStatsBundle>> _stats = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final csvText = await rootBundle.loadString('assets/data/result_metrics.csv');
    _buildStatsFromCsv(csvText);
    _loaded = true;
  }

  /// ใช้ตอนเรียกคำนวณ
  Future<ZScoreResult> compute({
    required String templateKey, // "ไอศกรีม" | "ปลา" | "ดินสอ"
    required int age,            // 4 หรือ 5 (ถ้าอย่างอื่นจะจับคู่ใกล้สุด)
    required double h,
    required double c,
    required double blank,
    required double cotl,
  }) async {
    await ensureLoaded();
    final tk = _normalizeTemplate(templateKey);
    final a = _closestAgeGroup(age);

    final bundle = _stats[tk]?[a];
    if (bundle == null) {
      // ถ้าไม่พบสถิติ ให้คืนค่า 0
      return const ZScoreResult(h: 0, c: 0, blank: 0, cotl: 0);
    }
    return ZScoreResult(
      h: bundle.h.z(h),
      c: bundle.c.z(c),
      blank: bundle.blank.z(blank),
      cotl: bundle.cotl.z(cotl),
    );
  }

  // ------------------------
  // Internal helpers
  // ------------------------

  String _normalizeTemplate(String s) {
    final x = s.trim().toLowerCase();
    if (x.contains('ice')) return 'ไอศกรีม';
    if (x.contains('cream')) return 'ไอศกรีม';
    if (x.contains('icecream')) return 'ไอศกรีม';
    if (x.contains('fish') || x.contains('ปลา')) return 'ปลา';
    if (x.contains('pencil') || x.contains('ดินสอ')) return 'ดินสอ';
    // เผื่อชื่อส่งมาภาษาไทยตรง ๆ
    if (x.contains('ไอศกรีม') || x.contains('ไอติม')) return 'ไอศกรีม';
    return s;
  }

  int _closestAgeGroup(int age) {
    // dataset ตอนนี้มี 4 และ 5 ขวบ
    if (age <= 4) return 4;
    if (age >= 5) return 5;
    return age;
  }

  void _buildStatsFromCsv(String csvText) {
    // คาด header: Class,Name,H,C,Blank,COTL,Age
    final lines = const LineSplitter().convert(csvText).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;

    final header = _splitCsvLine(lines.first);
    final idxName  = header.indexOf('Name');
    final idxH     = header.indexOf('H');
    final idxC     = header.indexOf('C');
    final idxBlank = header.indexOf('Blank');
    final idxCOTL  = header.indexOf('COTL');
    final idxAge   = header.indexOf('Age');

    final Map<String, Map<int, List<List<double>>>> buckets = {}; // template -> age -> list of [H,C,Blank,COTL]

    for (var i = 1; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if ([idxName, idxH, idxC, idxBlank, idxCOTL, idxAge].any((x) => x < 0 || x >= cols.length)) continue;

      final template = _normalizeTemplate(_inferTemplate(cols[idxName]));
      final age = int.tryParse(cols[idxAge].trim()) ?? 0;
      final h = double.tryParse(cols[idxH]) ?? 0;
      final c = double.tryParse(cols[idxC]) ?? 0;
      final blank = double.tryParse(cols[idxBlank]) ?? 0;
      final cotl = double.tryParse(cols[idxCOTL]) ?? 0;

      buckets.putIfAbsent(template, () => {});
      buckets[template]!.putIfAbsent(age, () => []);
      buckets[template]![age]!.add([h, c, blank, cotl]);
    }

    // คำนวณ mean, sd
    buckets.forEach((template, byAge) {
      _stats.putIfAbsent(template, () => {});
      byAge.forEach((age, rows) {
        List<double> col(int j) => rows.map((r) => r[j]).toList();
        _stats[template]![age] = _MetricStatsBundle(
          h: _calc(col(0)),
          c: _calc(col(1)),
          blank: _calc(col(2)),
          cotl: _calc(col(3)),
        );
      });
    });
  }

  _Stats _calc(List<double> xs) {
    if (xs.isEmpty) return const _Stats(0, 0);
    final n = xs.length;
    final mean = xs.reduce((a, b) => a + b) / n;
    final varSum = xs.fold<double>(0, (s, x) => s + (x - mean) * (x - mean));
    final sd = n > 1 ? (varSum / (n - 1)).sqrt() : 0.0; // ใช้ sample sd
    return _Stats(mean, sd);
  }
}

extension on double {
  double sqrt() => this <= 0 ? 0.0 : Mathsqrt(this);
}

// ใช้ sqrt แบบง่ายโดยไม่ดึง dart:math ตรง ๆ (หลบชื่อซ้ำ)
double Mathsqrt(double v) => v > 0 ? v.toDouble().sqrtInternal() : 0.0;

extension _Sqrt on double {
  double sqrtInternal() {
    // Newton-Raphson แบบง่ายพอใช้
    double x = this;
    double g = this / 2.0;
    if (x == 0) return 0;
    for (int i = 0; i < 12; i++) {
      g = 0.5 * (g + x / g);
    }
    return g;
  }
}

/// เดาจากชื่อไฟล์/ชื่อรูป
String _inferTemplate(String nameRaw) {
  final name = nameRaw.toLowerCase();
  if (name.contains('ice') || name.contains('icecream') || name.contains('ice-cream') || name.contains('ice_cream') || name.contains('ไอศกรีม') || name.contains('ไอติม')) {
    return 'ไอศกรีม';
  }
  if (name.contains('fish') || name.contains('ปลา')) return 'ปลา';
  if (name.contains('pencil') || name.contains('ดินสอ')) return 'ดินสอ';
  return nameRaw;
}

/// CSV split แบบเรียบง่าย (รองรับค่าที่ไม่มีเครื่องหมายคำพูด)
List<String> _splitCsvLine(String line) {
  // ถ้าข้อมูลไม่มีคอมม่าในช่อง ใช้ split(',') ได้เลย
  // ถ้าภายหลังมีค่าใน "..." แล้วมีคอมม่าในช่อง ค่อยเปลี่ยนเป็นแพ็กเกจ csv
  return line.split(',');
}
