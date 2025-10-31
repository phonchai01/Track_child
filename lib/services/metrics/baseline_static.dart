// lib/services/metrics/baseline_static.dart
enum Metric { entropyH, complexityC, blankRatio, cotlRatio }

class Baseline {
  final double mean;
  final double std;
  const Baseline(this.mean, this.std);
}

/// ตาราง baseline แบบฝังในโค้ด (ใส่ค่าจริงของคุณแทนตัวอย่างได้)
class BaselineTable {
  // ใช้ id เทมเพลต: 'fish' | 'pencil' | 'icecream'
  static const Map<String, Map<String, Map<Metric, Baseline>>> data = {
    '4': {
      'fish': {
        Metric.entropyH:  Baseline(0.86, 0.02),
        Metric.complexityC: Baseline(0.17, 0.02),
        Metric.blankRatio: Baseline(0.05, 0.03),
        Metric.cotlRatio:  Baseline(0.11, 0.03),
      },
      'pencil': {
        Metric.entropyH:  Baseline(0.84, 0.02),
        Metric.complexityC: Baseline(0.18, 0.02),
        Metric.blankRatio: Baseline(0.06, 0.03),
        Metric.cotlRatio:  Baseline(0.10, 0.03),
      },
      'icecream': {
        Metric.entropyH:  Baseline(0.85, 0.02),
        Metric.complexityC: Baseline(0.17, 0.02),
        Metric.blankRatio: Baseline(0.05, 0.03),
        Metric.cotlRatio:  Baseline(0.10, 0.03),
      },
    },
    '5': {
      'fish': {
        Metric.entropyH:  Baseline(0.84, 0.02),
        Metric.complexityC: Baseline(0.18, 0.02),
        Metric.blankRatio: Baseline(0.04, 0.03),
        Metric.cotlRatio:  Baseline(0.09, 0.03),
      },
      'pencil': {
        Metric.entropyH:  Baseline(0.83, 0.02),
        Metric.complexityC: Baseline(0.19, 0.02),
        Metric.blankRatio: Baseline(0.05, 0.03),
        Metric.cotlRatio:  Baseline(0.08, 0.03),
      },
      'icecream': {
        Metric.entropyH:  Baseline(0.84, 0.02),
        Metric.complexityC: Baseline(0.18, 0.02),
        Metric.blankRatio: Baseline(0.04, 0.03),
        Metric.cotlRatio:  Baseline(0.09, 0.03),
      },
    },
  };

  static Baseline? get(String age, String template, Metric m) {
    return data[age]?[template]?[m];
  }

  /// Z = (X - μ) / σ
  static double zScore({
    required String age,
    required String template,
    required Metric metric,
    required double x,
  }) {
    final b = get(age, template, metric);
    if (b == null || b.std == 0) return double.nan;
    return (x - b.mean) / b.std;
  }

  /// รวม 4 ตัวเป็นดัชนีเดียว (ตาม paper: ใส่เครื่องหมายลบให้ H/Blank/COTL แล้ว sum)
  static ({double zH,double zC,double zB,double zO,double index,String level})
  computeIndex({
    required String age,
    required String template,
    required double H,
    required double C,
    required double Blank,
    required double COTL,
  }) {
    final zh = zScore(age: age, template: template, metric: Metric.entropyH,  x: H);
    final zc = zScore(age: age, template: template, metric: Metric.complexityC, x: C);
    final zb = zScore(age: age, template: template, metric: Metric.blankRatio,  x: Blank);
    final zo = zScore(age: age, template: template, metric: Metric.cotlRatio,   x: COTL);

    final index = (-zh) + (zc) + (-zb) + (-zo);
    final level = (index < -1) ? 'ต่ำกว่ามาตรฐาน'
                : (index > 1)  ? 'สูงกว่ามาตรฐาน'
                                : 'ปกติ';
    return (zH: zh, zC: zc, zB: zb, zO: zo, index: index, level: level);
  }
}
