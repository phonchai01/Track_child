// Statistical Complexity (LMC) จาก permutation distribution (Bandt–Pompe)
// API เดิม: ComplexityCV.edgeDensity(bgr, {mask})
//  *แม้ชื่อเมธอดเดิม แต่ความหมายคือ LMC Complexity แล้ว*
import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ComplexityCV {
  /// คืนค่า LMC Complexity (สำหรับ dx=dy=2 จะอยู่ราวๆ 0..0.2155)
  /// รวมเฉพาะหน้าต่างที่ทุกพิกเซลอยู่ใน mask (all-4-inside)
  static double edgeDensity(
    cv.Mat bgr, {
    cv.Mat? mask,
    int dx = 2,
    int dy = 2,
  }) {
    final _GrayMask gm = _prepareGrayAndMask(bgr, mask);
    final counts = _countPermDistribution(gm, dx: dx, dy: dy);

    int total = 0;
    for (final c in counts) total += c;
    if (total == 0) return 0.0;

    final p = List<double>.generate(counts.length, (i) => counts[i] / total);
    final hn = _entropyNormalizedFromP(p);
    final d = _jsDivToUniform(p);
    final ds = _dStar(p.length);
    final c = (ds > 0) ? (d * hn / ds) : 0.0;
    return c.clamp(0.0, 1.0);
  }

  /// Alias ชื่อชัดๆ หากอยากเรียกตรงๆ ว่า LMC
  static double computeLMC(
    cv.Mat bgr, {
    cv.Mat? mask,
    int dx = 2,
    int dy = 2,
  }) => edgeDensity(bgr, mask: mask, dx: dx, dy: dy);
}

// ----------------------- helpers (เหมือน entropy) -----------------------

class _GrayMask {
  final int w, h;
  final List<int> r, g, b;
  final List<int>? mask;
  _GrayMask(this.w, this.h, this.r, this.g, this.b, this.mask);

  double grayAt(int idx) => (r[idx] + g[idx] + b[idx]) / 3.0;
}

_GrayMask _prepareGrayAndMask(cv.Mat bgr, cv.Mat? mask) {
  final ch = cv.split(bgr);
  final b = ch[0].data;
  final g = ch[1].data;
  final r = ch[2].data;

  List<int>? m;
  if (mask != null) {
    final m1 = (mask.channels > 1)
        ? cv.cvtColor(mask, cv.COLOR_BGR2GRAY).data
        : mask.data;
    m = List<int>.from(m1);
  }
  return _GrayMask(bgr.cols, bgr.rows, r.toList(), g.toList(), b.toList(), m);
}

List<int> _countPermDistribution(
  _GrayMask gm, {
  required int dx,
  required int dy,
}) {
  final H = gm.h, W = gm.w;
  final m = dx * dy;
  final perms = _allPerms(m);
  final indexOf = <String, int>{
    for (int i = 0; i < perms.length; i++) _key(perms[i]): i,
  };
  final counts = List<int>.filled(perms.length, 0);

  for (int y = 0; y <= H - dy; y++) {
    for (int x = 0; x <= W - dx; x++) {
      if (gm.mask != null) {
        bool ok = true;
        for (int yy = 0; yy < dy && ok; yy++) {
          final row = (y + yy) * W;
          for (int xx = 0; xx < dx; xx++) {
            if (gm.mask![row + (x + xx)] == 0) {
              ok = false;
              break;
            }
          }
        }
        if (!ok) continue;
      }

      final vals = List<double>.filled(m, 0.0);
      int k = 0;
      for (int yy = 0; yy < dy; yy++) {
        final row = (y + yy) * W;
        for (int xx = 0; xx < dx; xx++) {
          final idx = row + (x + xx);
          vals[k++] = gm.grayAt(idx);
        }
      }

      final ord = _argsortStable(vals);
      counts[indexOf[_key(ord)]!] += 1;
    }
  }
  return counts;
}

List<int> _argsortStable(List<double> v) {
  final idx = List<int>.generate(v.length, (i) => i);
  idx.sort((a, b) {
    final da = v[a], db = v[b];
    if (da < db) return -1;
    if (da > db) return 1;
    return a.compareTo(b);
  });
  return idx;
}

List<List<int>> _allPerms(int m) {
  final res = <List<int>>[];
  void gen(List<int> cur, List<int> left) {
    if (left.isEmpty) {
      res.add(List<int>.from(cur));
      return;
    }
    for (int i = 0; i < left.length; i++) {
      final next = List<int>.from(left)..removeAt(i);
      gen([...cur, left[i]], next);
    }
  }

  gen([], List<int>.generate(m, (i) => i));
  return res;
}

String _key(List<int> p) => p.join(',');

double _S(Iterable<double> p) {
  double s = 0.0;
  for (final pi in p) {
    if (pi > 0) s += pi * math.log(1.0 / pi);
  }
  return s;
}

double _entropyNormalizedFromP(List<double> p) {
  final n = p.length;
  if (n <= 1) return 0.0;
  return _S(p) / math.log(n);
}

double _jsDivToUniform(List<double> p) {
  final n = p.length;
  final u = 1.0 / n;
  double Sm = 0.0, Sp = 0.0;
  for (final pi in p) {
    final mi = 0.5 * (pi + u);
    if (mi > 0) Sm += mi * math.log(1.0 / mi);
    if (pi > 0) Sp += pi * math.log(1.0 / pi);
  }
  final Su = math.log(n);
  return Sm - 0.5 * Sp - 0.5 * Su;
}

double _dStar(int n) {
  return -0.5 *
      (((n + 1) / n) * math.log(n + 1) + math.log(n) - 2 * math.log(2 * n));
}
