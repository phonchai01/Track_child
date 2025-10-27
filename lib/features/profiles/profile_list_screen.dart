import 'package:flutter/material.dart';
import '../../data/repositories/cohort_repo.dart';
import '../templates/template_picker_screen.dart';

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({super.key});

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  final _repo = CohortRepo();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _repo.getAll();
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    int age = 4;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('สร้างโปรไฟล์ใหม่'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'ชื่อเด็ก',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('อายุ:'),
                  const SizedBox(width: 12),
                  StatefulBuilder(
                    builder: (_, setLocal) {
                      return DropdownButton<int>(
                        value: age,
                        items: const [
                          DropdownMenuItem(value: 4, child: Text('4 ขวบ')),
                          DropdownMenuItem(value: 5, child: Text('5 ขวบ')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => age = v);
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _repo.add(name: nameCtrl.text.trim(), age: age);
      await _load();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('ยืนยันการลบ'),
          content: Text('ลบโปรไฟล์ “${item['name']}” ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _repo.remove(item['id'] as String);
      await _load();
    }
  }

  void _openTemplates(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TemplatePickerScreen(),
        settings: RouteSettings(arguments: item), // ส่งโปรไฟล์ไปด้วย
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // ✅ ซ่อนปุ่มย้อนกลับ
        title: Text('เลือกโปรไฟล์เด็ก', style: titleStyle),
        actions: const [],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const _EmptyView()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      tileColor: Theme.of(context).colorScheme.surface,
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(it['name'] as String),
                      subtitle: Text('อายุ: ${(it['age'] as int)} ขวบ'),
                      onTap: () => _openTemplates(it),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(it),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: _items.length,
                ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.child_care, size: 56),
            SizedBox(height: 8),
            Text('ยังไม่มีโปรไฟล์\nกดปุ่ม + เพื่อสร้างโปรไฟล์ใหม่', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
