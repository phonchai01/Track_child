// lib/features/profiles/profile_insights_screen.dart
import 'package:flutter/material.dart';
import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo.dart';

class ProfileInsightsScreen extends StatefulWidget {
  const ProfileInsightsScreen({
    super.key,
    required this.profileKey,
    required this.displayName,
  });

  final String profileKey;
  final String displayName;

  @override
  State<ProfileInsightsScreen> createState() => _ProfileInsightsScreenState();
}

enum Metric { z, h, c, blank, cotl }

class _ProfileInsightsScreenState extends State<ProfileInsightsScreen> {
  late Future<List<HistoryRecord>> _future;
  Metric _metric = Metric.z;

  @override
  void initState() {
    super.initState();
    _future = HistoryRepo.I.listByProfile(widget.profileKey);
  }

  List<double> _series(List<HistoryRecord> rs) {
    rs.sort((a, b) => a.createdAt.compareTo(b.createdAt)); // เก่า->ใหม่
    switch (_metric) {
      case Metric.z:
        return rs.map((e) => e.zSum).toList();
      case Metric.h:
        return rs.map((e) => e.h).toList();
      case Metric.c:
        return rs.map((e) => e.c).toList();
      case Metric.blank:
        return rs.map((e) => e.blank).toList();
      case Metric.cotl:
        return rs.map((e) => e.cotl).toList();
    }
  }

  String _metricLabel(Metric m) {
    switch (m) {
      case Metric.z:
        return 'Index (z)';
      case Metric.h:
        return 'Entropy (H)';
      case Metric.c:
        return 'Complexity (C)';
      case Metric.blank:
        return 'Blank';
      case Metric.cotl:
        return 'COTL';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('อินไซต์: ${widget.displayName}'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: () {
              setState(() {
                _future = HistoryRepo.I.listByProfile(widget.profileKey);
              });
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data ?? [];
          if (all.isEmpty) {
            return const Center(child: Text('ยังไม่มีข้อมูลของโปรไฟล์นี้'));
          }

          final pts = _series(all);
          final latest = pts.isNotEmpty ? pts.last : null;
          final prev = pts.length >= 2 ? pts[pts.length - 2] : null;
          final delta = (latest != null && prev != null) ? latest - prev : null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // ตัวเลือก Metric
              SegmentedButton<Metric>(
                segments: const [
                  ButtonSegment(value: Metric.z, label: Text('Index')),
                  ButtonSegment(value: Metric.h, label: Text('H')),
                ], // ต่อแถวแรก
                selected: {_metric == Metric.z ? Metric.z : Metric.h},
                multiSelectionEnabled: false,
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: const VisualDensity(
                    horizontal: -1,
                    vertical: -2,
                  ),
                ),
                onSelectionChanged: (s) {
                  final v = s.first;
                  setState(() => _metric = v);
                },
              ),
              const SizedBox(height: 8),
              SegmentedButton<Metric>(
                segments: const [
                  ButtonSegment(value: Metric.c, label: Text('C')),
                  ButtonSegment(value: Metric.blank, label: Text('Blank')),
                  ButtonSegment(value: Metric.cotl, label: Text('COTL')),
                ],
                selected: {_metric},
                multiSelectionEnabled: false,
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: const VisualDensity(
                    horizontal: -1,
                    vertical: -2,
                  ),
                ),
                onSelectionChanged: (s) {
                  setState(() => _metric = s.first);
                },
              ),

              const SizedBox(height: 16),

              // Header + ค่า + Δ
              Row(
                children: [
                  Text(
                    _metricLabel(_metric),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (latest != null)
                    Text(
                      latest.toStringAsFixed(3),
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (delta != null) _DeltaBadge(value: delta),
                ],
              ),
              const SizedBox(height: 8),

              // กราฟใหญ่
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                  gradient: LinearGradient(
                    colors: [
                      cs.surface,
                      cs.surfaceContainerHighest.withOpacity(0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                child: _BigSparkline(points: pts),
              ),

              const SizedBox(height: 12),

              // ตารางค่าสรุปสั้น ๆ (ล่าสุด 5 รายการ)
              Text('ล่าสุด 5 ครั้ง', style: tt.titleSmall),
              const SizedBox(height: 6),
              _RecentTable(
                records: all.reversed.take(5).toList(),
                metric: _metric,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecentTable extends StatelessWidget {
  const _RecentTable({required this.records, required this.metric});
  final List<HistoryRecord> records; // เรียงใหม่->เก่าเข้ามาแล้ว
  final Metric metric;

  double _get(HistoryRecord r) {
    switch (metric) {
      case Metric.z:
        return r.zSum;
      case Metric.h:
        return r.h;
      case Metric.c:
        return r.c;
      case Metric.blank:
        return r.blank;
      case Metric.cotl:
        return r.cotl;
    }
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$dd  $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < records.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fmtDate(records[i].createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    _get(records[i]).toStringAsFixed(3),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BigSparkline extends StatelessWidget {
  const _BigSparkline({required this.points});
  final List<double> points;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _SparkPainter(
        points,
        const Color(0xFF5E8BFF),
        const Color(0x335E8BFF),
        cs.outlineVariant,
      ),
      size: Size.infinite,
    );
  }
}

// ===== Sparkline painter re-use =====
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.stroke, this.fill, this.guideColor);

  final List<double> points;
  final Color stroke;
  final Color fill;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final guide = Paint()
      ..color = guideColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - 1), Offset(w, h - 1), guide);

    if (w <= 0 || h <= 0 || points.isEmpty) return;

    final minV = points.reduce((a, b) => a < b ? a : b);
    final maxV = points.reduce((a, b) => a > b ? a : b);
    final pad = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV) * 0.2;
    final lo = minV - pad;
    final hi = maxV + pad;

    double xStep = points.length <= 1 ? w : w / (points.length - 1);
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final x = i * xStep;
      final t = (points[i] - lo) / (hi - lo);
      final y = h - (t.clamp(0.0, 1.0) * (h - 2)) - 1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final area = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fill;
    canvas.drawPath(area, fillPaint);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = stroke;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.stroke != stroke ||
        oldDelegate.fill != fill ||
        oldDelegate.guideColor != guideColor;
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final up = value >= 0;
    final color = up ? const Color(0xFF1B8C3B) : const Color(0xFFB82E2E);
    final bg = up ? const Color(0x331B8C3B) : const Color(0x33B82E2E);
    final icon = up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          Text(
            value >= 0
                ? '+${value.toStringAsFixed(3)}'
                : value.toStringAsFixed(3),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
