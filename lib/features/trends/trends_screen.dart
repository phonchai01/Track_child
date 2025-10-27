import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/repositories/session_repo.dart';
import '../../data/models/session.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  late Future<List<Session>> _future;

  @override
  void initState() {
    super.initState();
    _future = SessionRepo().listAll(); // ทั้งหมดก่อน / ภายหลังเลือก template ได้
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('กราฟความคืบหน้า')),
      body: FutureBuilder<List<Session>>(
        future: _future,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.length < 2) return const Center(child: Text('ต้องมีข้อมูลอย่างน้อย 2 ครั้งเพื่อแสดงกราฟ'));

          items.sort((a,b)=> a.createdAt.compareTo(b.createdAt));
          final spotsH = <FlSpot>[];
          for (var i = 0; i < items.length; i++) {
            spotsH.add(FlSpot(i.toDouble(), items[i].h));
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: LineChart(
              LineChartData(
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                ),
                gridData: FlGridData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    spots: spotsH,
                    dotData: FlDotData(show: false),
                    barWidth: 3,
                  ),
                ],
                minY: 0,
                maxY: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}
