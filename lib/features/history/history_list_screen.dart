import 'package:flutter/material.dart';
import '../../data/repositories/session_repo.dart';
import '../../data/models/session.dart';

class HistoryListScreen extends StatefulWidget {
  const HistoryListScreen({super.key});

  @override
  State<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends State<HistoryListScreen> {
  late Future<List<Session>> _future;

  @override
  void initState() {
    super.initState();
    _future = SessionRepo().listAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติการประเมิน')),
      body: FutureBuilder<List<Session>>(
        future: _future,
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('ยังไม่มีข้อมูล'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = items[i];
              return ListTile(
                title: Text('${s.templateKey}  •  ${s.createdAt.toLocal()}'),
                subtitle: Text('H=${s.h.toStringAsFixed(3)}  D*=${s.dstar.toStringAsFixed(3)}  '
                    'Blank=${s.blank.toStringAsFixed(3)}  COTL=${s.cotl.toStringAsFixed(3)}'),
              );
            },
          );
        },
      ),
    );
  }
}
