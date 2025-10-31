// lib/services/metrics/zscore_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;

/// -----------------------------
/// สถิติพื้นฐาน
/// -----------------------------
class _Stats {
  final double mean;
  final double sd;
  const _Stats(this.mean, this.sd);

  double z(double x) => (sd == 0 || sd.isNaN) ? 0.0 : (x - mean) / sd;
}

/// -----------------------------
/// ช่วงอ้างอิงของ Index
/// -----------------------------
class IndexBand {
  final double mu;
  final double sigma;
  final double low;   // mu - k*sigma
  final double high;  // mu + k*sigma
  final double k;
  const IndexBand({
    required this.mu,
    required this.sigma,
    required this.low,
    required this.high,
    required this.k,
  });
}

/// -----------------------------
/// ผลสำหรับ RAW INDEX
/// -----------------------------
class RawIndexResult {
  final double index;    // -H + C - Blank - COTL (raw)
  final String level;    // ต่ำกว่ามาตรฐาน | อยู่ในเกณฑ์มาตรฐาน | สูงกว่ามาตรฐาน
  final double mu;       // μ ของ raw-index ในกลุ่ม
  final double sigma;    // σ ของ raw-index ในกลุ่ม
  final double lowCut;   // μ−σ
  final double highCut;  // μ+σ
  const RawIndexResult({
    required this.index,
    required this.level,
    required this.mu,
    required this.sigma,
    required this.lowCut,
    required this.highCut,
  });
}

/// -----------------------------
/// (คงไว้เผื่อไฟล์อื่นใช้อยู่) ผลแบบ Z-sum
/// -----------------------------
class ZScoreResult {
  final double zH;
  final double zC;
  final double zBlank;
  final double zCotl;
  final double zSum;     // ดัชนีรวมในสเกล Z
  final String level;

  final double? zsumMean;
  final double? zsumSd;
  final double? lowCut;
  final double? highCut;

  const ZScoreResult({
    required this.zH,
    required this.zC,
    required this.zBlank,
    required this.zCotl,
    required this.zSum,
    required this.level,
    this.zsumMean,
    this.zsumSd,
    this.lowCut,
    this.highCut,
  });
}

/// ----------------------------------------------
/// bundle ต่อกลุ่ม (template × age)
/// เก็บสถิติ metric ดิบ + สถิติของทั้ง Z-sum และ RAW index
/// ----------------------------------------------
class _MetricStatsBundle {
  final _Stats h, c, blank, cotl;  // สถิติ metric ดิบ
  // baseline สำหรับ Z-sum
  final double zsumMean;
  final double zsumSd;
  // baseline สำหรับ RAW index
  final double rawMean;
  final double rawSd;

  const _MetricStatsBundle({
    required this.h,
    required this.c,
    required this.blank,
    required this.cotl,
    required this.zsumMean,
    required this.zsumSd,
    required this.rawMean,
    required this.rawSd,
  });
}

/// ==============================================
/// ZScoreService (singleton)
/// ==============================================
class ZScoreService {
  static final ZScoreService instance = ZScoreService._();
  ZScoreService._();

  final Map<String, Map<int, _MetricStatsBundle>> _stats = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final csvText = await rootBundle.loadString('assets/data/result_metrics.csv');
    _buildStatsFromCsv(csvText);
    _loaded = true;
  }

  /// ============== RAW ==============
  /// Index(raw) = -H + C - Blank - COTL
  /// ระดับใช้ช่วง [μ−σ, μ+σ] ของ "raw-index" ของกลุ่ม
  Future<RawIndexResult> computeRaw({
    required String templateKey,
    required int age,
    required double h,
    required double c,
    required double blank,
    required double cotl,
  }) async {
    await ensureLoaded();

    final tk = _normalizeTemplate(templateKey);
    final a  = _closestAgeGroup(age);
    final b  = _stats[tk]?[a];

    if (b == null) {
      return const RawIndexResult(
        index: double.nan,
        level: 'ไม่มีข้อมูลมาตรฐาน',
        mu: 0, sigma: 0, lowCut: 0, highCut: 0,
      );
    }

    final idx = (-h) + c + (-blank) + (-cotl); // raw index
    final low  = b.rawMean - b.rawSd;
    final high = b.rawMean + b.rawSd;
    final level = (idx < low)
        ? 'ต่ำกว่ามาตรฐาน'
        : (idx > high)
            ? 'สูงกว่ามาตรฐาน'
            : 'อยู่ในเกณฑ์มาตรฐาน';

    return RawIndexResult(
      index: idx,
      level: level,
      mu: b.rawMean,
      sigma: b.rawSd,
      lowCut: low,
      highCut: high,
    );
    // หมายเหตุ: ถ้าต้องการให้ช่วงปรับได้ (เช่น k=1.5) ค่อยเพิ่มพารามิเตอร์ในภายหลัง
  }

  /// ============== (เดิม) Z-sum ==============
  Future<ZScoreResult> compute({
    required String templateKey,
    required int age,
    required double h,
    required double c,
    required double blank,
    required double cotl,
    double bandK = 1.0,
  }) async {
    await ensureLoaded();

    final tk = _normalizeTemplate(templateKey);
    final a  = _closestAgeGroup(age);
    final b  = _stats[tk]?[a];

    if (b == null) {
      return const ZScoreResult(
        zH: double.nan,
        zC: double.nan,
        zBlank: double.nan,
        zCotl: double.nan,
        zSum: double.nan,
        level: 'ไม่มีข้อมูลมาตรฐาน',
      );
    }

    final zH = -b.h.z(h);
    final zC =  b.c.z(c);
    final zB = -b.blank.z(blank);
    final zO = -b.cotl.z(cotl);
    final zSum = zH + zC + zB + zO;

    final low  = b.zsumMean - bandK * b.zsumSd;
    final high = b.zsumMean + bandK * b.zsumSd;
    final level = (zSum < low)
        ? 'ต่ำกว่ามาตรฐาน'
        : (zSum > high)
            ? 'สูงกว่ามาตรฐาน'
            : 'อยู่ในเกณฑ์มาตรฐาน';

    return ZScoreResult(
      zH: zH,
      zC: zC,
      zBlank: zB,
      zCotl: zO,
      zSum: zSum,
      level: level,
      zsumMean: b.zsumMean,
      zsumSd: b.zsumSd,
      lowCut: low,
      highCut: high,
    );
  }

  /// ดึงช่วงอ้างอิง RAW (ถ้าต้องแสดงอย่างเดียว)
  IndexBand bandForRaw(String templateKey, int age, {double k = 1.0}) {
    final tk = _normalizeTemplate(templateKey);
    final a  = _closestAgeGroup(age);
    final b  = _stats[tk]?[a];
    if (b == null) return const IndexBand(mu: 0, sigma: 0, low: 0, high: 0, k: 1.0);
    return IndexBand(
      mu: b.rawMean,
      sigma: b.rawSd,
      low: b.rawMean - k * b.rawSd,
      high: b.rawMean + k * b.rawSd,
      k: k,
    );
  }

  // ---------------- Build stats from CSV ----------------
  void _buildStatsFromCsv(String csvText) {
    // header คาดว่า: Class,Name,H,C,Blank,COTL,Age
    final lines = const LineSplitter()
        .convert(csvText)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    final header = _splitCsvLine(lines.first);
    final iName  = header.indexWhere((x) => x.toLowerCase() == 'name');
    final iH     = header.indexWhere((x) => x.toLowerCase() == 'h');
    final iC     = header.indexWhere((x) => x.toLowerCase() == 'c');
    final iBlank = header.indexWhere((x) => x.toLowerCase() == 'blank');
    final iCOTL  = header.indexWhere((x) => x.toLowerCase() == 'cotl');
    final iAge   = header.indexWhere((x) => x.toLowerCase() == 'age');

    final Map<String, Map<int, List<List<double>>>> groups = {};

    for (var i = 1; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if ([iName, iH, iC, iBlank, iCOTL, iAge].any((x) => x < 0 || x >= cols.length)) {
        continue;
      }
      final template = _normalizeTemplate(_inferTemplate(cols[iName]));
      final age      = int.tryParse(cols[iAge].trim()) ?? 0;
      final h        = double.tryParse(cols[iH]) ?? 0;
      final c        = double.tryParse(cols[iC]) ?? 0;
      final blank    = double.tryParse(cols[iBlank]) ?? 0;
      final cotl     = double.tryParse(cols[iCOTL]) ?? 0;

      groups.putIfAbsent(template, () => {});
      groups[template]!.putIfAbsent(age, () => []);
      groups[template]![age]!.add([h, c, blank, cotl]);
    }

    final Map<String, Map<int, _MetricStatsBundle>> tmp = {};
    groups.forEach((tpl, byAge) {
      tmp.putIfAbsent(tpl, () => {});
      byAge.forEach((age, rows) {
        if (rows.isEmpty) return;

        List<double> col(int j) => rows.map((r) => r[j]).toList();
        final hStat = _calc(col(0));
        final cStat = _calc(col(1));
        final bStat = _calc(col(2));
        final oStat = _calc(col(3));

        // Z-sum ของทุกแถว (ย้อนสเกล H/Blank/COTL)
        final zSums = <double>[];
        // RAW index ของทุกแถว
        final rawIdx = <double>[];

        for (final r in rows) {
          final zH = -hStat.z(r[0]);
          final zC =  cStat.z(r[1]);
          final zB = -bStat.z(r[2]);
          final zO = -oStat.z(r[3]);
          zSums.add(zH + zC + zB + zO);

          // raw index
          rawIdx.add((-r[0]) + r[1] + (-r[2]) + (-r[3]));
        }

        final zsumStat = _calc(zSums);
        final rawStat  = _calc(rawIdx);

        tmp[tpl]![age] = _MetricStatsBundle(
          h: hStat,
          c: cStat,
          blank: bStat,
          cotl: oStat,
          zsumMean: zsumStat.mean,
          zsumSd: zsumStat.sd,
          rawMean: rawStat.mean,
          rawSd: rawStat.sd,
        );
      });
    });

    _stats
      ..clear()
      ..addAll(tmp);
  }

  _Stats _calc(List<double> xs) {
    if (xs.isEmpty) return const _Stats(0, 0);
    final n = xs.length;
    final mean = xs.reduce((a, b) => a + b) / n;
    double varSum = 0.0;
    for (final x in xs) {
      final d = x - mean;
      varSum += d * d;
    }
    final sd = (n > 1) ? math.sqrt(varSum / (n - 1)) : 0.0; // sample sd
    return _Stats(mean, sd);
  }

  // ---------------- helpers ----------------
  String _normalizeTemplate(String s) {
    final x = s.trim().toLowerCase();
    if (x.contains('ice') || x.contains('cream') || x.contains('ไอศกรีม') || x.contains('ไอติม')) {
      return 'ไอศกรีม';
    }
    if (x.contains('fish') || x.contains('ปลา')) return 'ปลา';
    if (x.contains('pencil') || x.contains('ดินสอ')) return 'ดินสอ';
    return s;
  }

  int _closestAgeGroup(int age) {
    if (age <= 4) return 4;
    if (age >= 5) return 5;
    return age;
  }
}

// เดา template จากชื่อไฟล์/ชื่อรูป
String _inferTemplate(String nameRaw) {
  final n = nameRaw.toLowerCase();
  if (n.contains('ice') || n.contains('icecream') || n.contains('ice-cream') ||
      n.contains('ice_cream') || n.contains('ไอศกรีม') || n.contains('ไอติม')) {
    return 'ไอศกรีม';
  }
  if (n.contains('fish') || n.contains('ปลา')) return 'ปลา';
  if (n.contains('pencil') || n.contains('ดินสอ')) return 'ดินสอ';
  return nameRaw;
}

List<String> _splitCsvLine(String line) => line.split(',').map((e) => e.trim()).toList();
