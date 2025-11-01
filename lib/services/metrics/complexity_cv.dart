// lib/services/metrics/complexity_cv.dart
//
// LMC Statistical Complexity จาก Bandt–Pompe
// C = (D / D*) * Hn  (D = JS divergence ถึง uniform, Hn = normalized entropy)
// คุณสมบัติ: all-inside windows, flat-check, zero-floor (อิง Hn), รองรับ dartcv4

import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

const double _EPS_FLAT = 1.0;
const double _FLAT_OUTLIER_FRAC = 0.002;
const double _H_ZERO_FLOOR = 0.03; // ถ้า Hn ≤ 0.03 ⇒ C = 0

class ComplexityCV {
  static double edgeDensity(
    cv.Mat bgr, {
    cv.Mat? mask,
    int dx = 2,
    int dy = 2,
    int? bleedFixPx,
    double? zeroFloorH,
  }) {
    print('🚀 ComplexityCV vNEW called (dx=$dx, dy=$dy) mask?=${mask != null}');
    final cv.Mat? safeMask = (mask == null)
        ? null
        : _prepareBinaryMask(mask, dx: dx, dy: dy, bleedFixPx: bleedFixPx);

    if (safeMask != null) {
      final m8 = (safeMask.type == 0) ? safeMask : cv.convertScaleAbs(safeMask);
      print('   └insidePx=${cv.countNonZero(m8)} size=${m8.cols}x${m8.rows}');
    }

    final _GrayMask gm = _prepareGrayAndMask(bgr, safeMask);
    if (_isFlatRegion(gm)) return 0.0;

    final counts = _countPermDistribution(gm, dx: dx, dy: dy);

    int total = 0;
    for (final c in counts) total += c;
    if (total == 0) return 0.0;

    final p = List<double>.generate(counts.length, (i) => counts[i] / total);

    final hn = _entropyNormalizedFromP(p).clamp(0.0, 1.0);
    final thr = zeroFloorH ?? _H_ZERO_FLOOR;
    if (hn <= thr) {
      print('📊 ComplexityCV: Hn=$hn ≤ $thr → C=0');
      return 0.0;
    }

    final d = _jsDivToUniform(p);
    final ds = _dStar(p.length);
    final c = (ds > 0) ? (d * hn / ds) : 0.0;
    final out = (c < 1e-9) ? 0.0 : c.clamp(0.0, 1.0);
    print('📊 ComplexityCV: Hn=$hn  D=$d  D*=$ds  C=$out');
    return out;
  }

  static double computeLMC(
    cv.Mat bgr, {
    cv.Mat? mask,
    int dx = 2,
    int dy = 2,
    int? bleedFixPx,
    double? zeroFloorH,
  }) {
    return edgeDensity(
      bgr,
      mask: mask,
      dx: dx,
      dy: dy,
      bleedFixPx: bleedFixPx,
      zeroFloorH: zeroFloorH,
    );
  }
}

// -------- helpers (อยู่นอกคลาส) --------

cv.Mat _prepareBinaryMask(
  cv.Mat mask, {
  required int dx,
  required int dy,
  int? bleedFixPx,
}) {
  final mGray = (mask.channels > 1)
      ? cv.cvtColor(mask, cv.COLOR_BGR2GRAY)
      : mask.clone();
  final mBin = cv
      .threshold(mGray, 0.0, 255.0, cv.THRESH_BINARY | cv.THRESH_OTSU)
      .$2;

  // ดีฟอลต์หดอย่างน้อย 2px กันหน้าต่าง 2×2 ชนขอบเส้น
  final k = (bleedFixPx ?? math.max(2, math.max(dx, dy) - 1)).clamp(0, 32);
  if (k > 0) {
    final ker = cv.getStructuringElement(0, (2 * k + 1, 2 * k + 1));
    return cv.erode(mBin, ker);
  }
  return mBin;
}

class _GrayMask {
  final int w, h;
  final List<int> r, g, b;
  final List<int>? mask;
  _GrayMask(this.w, this.h, this.r, this.g, this.b, this.mask);
  double grayAt(int idx) => (r[idx] + g[idx] + b[idx]) / 3.0;
}

bool _isFlatRegion(_GrayMask gm) {
  final int W = gm.w, H = gm.h;
  double? base;
  int total = 0, outlier = 0;

  if (gm.mask == null) {
    for (int i = 0, n = W * H; i < n; i++) {
      final v = gm.grayAt(i);
      base ??= v;
      total++;
      if ((v - base!).abs() > _EPS_FLAT) outlier++;
    }
  } else {
    for (int i = 0, n = W * H; i < n; i++) {
      if (gm.mask![i] == 0) continue;
      final v = gm.grayAt(i);
      base ??= v;
      total++;
      if ((v - base!).abs() > _EPS_FLAT) outlier++;
    }
  }
  if (total == 0) return false;
  return (outlier / total) <= _FLAT_OUTLIER_FRAC;
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
          vals[k++] = gm.grayAt(row + (x + xx));
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
