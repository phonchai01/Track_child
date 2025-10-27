import 'dart:ui';
import 'package:flutter/material.dart';

/// โมเดลข้อมูลต่อเดือน (0..1)
class MonthStat {
  final String monthLabel; // Jan, Feb, ...
  final double value; // 0..1
  MonthStat(this.monthLabel, this.value);
}

/// ---- หน้า Progress/Trends (ตัดรูปพื้นหลังทิ้ง) ----
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({
    super.key,
    this.title = 'Month',
    this.stats,
    this.onMenu,
  });

  /// ชื่อแกนใหญ่ด้านซ้ายบน
  final String title;

  /// ข้อมูลต่อเดือน (ถ้าไม่ส่งมา จะใช้ mock ด้านล่าง)
  final List<MonthStat>? stats;

  /// callback เมื่อกดปุ่มเมนู
  final VoidCallback? onMenu;

  /// mock data (แทนที่ด้วยสถิติจาก History จริงได้)
  List<MonthStat> get _mock => <MonthStat>[
    MonthStat('Jan', .78),
    MonthStat('Feb', .32),
    MonthStat('Mar', .61),
    MonthStat('Apr', .54),
    MonthStat('May', .00),
    MonthStat('Jun', .10),
  ];

  @override
  Widget build(BuildContext context) {
    final data = stats ?? _mock;
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ✅ พื้นหลังแบบกราเดียนท์ (ไม่ต้องใช้ asset)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF7F3FF), Color(0xFFEDE7FF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // เนื้อหาหลัก: ชื่อแกน + เส้นแกน + แท่ง
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // แถบซ้าย (หัวข้อ + เส้นแกน)
                  SizedBox(
                    width: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            shadows: const [
                              Shadow(
                                color: Colors.white,
                                offset: Offset(1, 1),
                                blurRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // เส้นแกนตั้ง
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(width: 3, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // รายการเดือน + แท่ง
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 72),
                      itemCount: data.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final m = data[i];
                        return _MonthBarRow(
                          label: m.monthLabel,
                          value: m.value,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ปุ่มเมนูมุมซ้ายบน (ถ้าอยากซ่อนก็ไม่ส่ง onMenu มาก็ได้)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 6),
                child: _CircleIconButton(
                  icon: Icons.menu,
                  onTap: onMenu ?? () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ),

          // ปุ่มย้อนกลับมุมขวาล่าง
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _CircleIconButton(
                  icon: Icons.arrow_back,
                  gradient: const LinearGradient(
                    colors: [Color(0xffFFD46B), Color(0xffF7A64B)],
                  ),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// แท่งหนึ่งบรรทัด: “Jan |====      | 78%”
class _MonthBarRow extends StatelessWidget {
  const _MonthBarRow({required this.label, required this.value});

  final String label;
  final double value; // 0..1

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = HSLColor.fromAHSL(
      1,
      110 - value * 60,
      0.55,
      0.55,
    ).toColor(); // เขียว -> เหลืองตามค่า

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.black,
              height: 1.1,
              shadows: const [
                Shadow(
                  color: Colors.white,
                  offset: Offset(1, 1),
                  blurRadius: 1,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              final double w = (cons.maxWidth * value).clamp(
                0.0,
                cons.maxWidth,
              );
              return Stack(
                children: [
                  // เฟรมเทาอ่อน
                  Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.05),
                      border: Border.all(color: Colors.black87, width: 2),
                    ),
                  ),
                  // bar สี
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    width: w, // <-- เป็น double แล้ว
                    height: 36,
                    decoration: BoxDecoration(
                      color: barColor,
                      border: Border.all(color: Colors.black87, width: 2),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

/// ปุ่มวงกลมมีกรอบ/กราเดียนท์
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.gradient,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    const w = 48.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              gradient ??
              const LinearGradient(colors: [Colors.white, Colors.white]),
          border: Border.all(color: Colors.black87, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 26, color: Colors.black87),
      ),
    );
  }
}
