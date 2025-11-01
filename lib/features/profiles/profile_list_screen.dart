// lib/features/profiles/profile_list_screen.dart
import 'package:flutter/material.dart';
import '../../data/repositories/cohort_repo.dart';
import '../templates/template_picker_screen.dart';
import '../../routes.dart';

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
    final data = await _repo.getAll(); // [{id, name, age, ...}]
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  // ----------------- Add/Edit/Delete -----------------
  Future<void> _openEditor({Map<String, dynamic>? edit}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ProfileEditor(initial: edit),
    );
    if (result == null) return;

    if (edit == null) {
      await _repo.add(
        name: result['name'] as String,
        age: result['age'] as int,
      );
    } else {
      // ถ้า CohortRepo มี update ให้ใช้ด้านล่างแทน
      // await _repo.update(id: edit['id'], name: result['name'], age: result['age']);
      await _repo.remove(edit['id'] as String);
      await _repo.add(
        name: result['name'] as String,
        age: result['age'] as int,
      );
    }
    await _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ลบโปรไฟล์นี้?'),
        content: Text('“${item['name']}” (อายุ ${item['age']} ขวบ) จะถูกลบ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo.remove(item['id'] as String);
      await _load();
    }
  }

  void _openTemplates(Map<String, dynamic> item) {
    // ไปหน้า TemplatePicker พร้อมส่ง profile object ทั้งก้อน
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TemplatePickerScreen(),
        settings: RouteSettings(arguments: {'profile': item}),
      ),
    );
  }

  void _openHistory(Map<String, dynamic> item) {
    final key = (item['id'] ?? item['key'] ?? item['name']).toString();
    Nav.toHistory(context, key);
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('เลือกโปรไฟล์เด็ก'),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text('${_items.length} โปรไฟล์'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? _EmptyState(onAdd: () => _openEditor())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final it = _items[i];
                final idOrKey = (it['id'] ?? it['key'] ?? it['name'])
                    .toString();
                return Dismissible(
                  key: ValueKey(idOrKey),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) async {
                    await _confirmDelete(it);
                    return false; // เราจัดการลบเอง แล้วรีเฟรช
                  },
                  background: _deleteBg(cs.errorContainer, cs.onErrorContainer),
                  child: _ProfileCard(
                    name: (it['name'] as String?)?.trim().isEmpty == true
                        ? 'ไม่ทราบชื่อ'
                        : it['name'] as String,
                    age: (it['age'] as int?) ?? 0,
                    onOpen: () => _openTemplates(it),
                    onEdit: () => _openEditor(edit: it),
                    onDelete: () => _confirmDelete(it),
                  ),
                );
              },
            ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add_rounded),
        label: const Text('โปรไฟล์ใหม่'),
      ),
    );
  }

  Widget _deleteBg(Color bg, Color fg) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(Icons.delete_rounded, color: fg),
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.age,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final int age;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '👦';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      elevation: 0.5,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Avatar(initials: initials),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'อายุ $age ขวบ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'แก้ไข',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: 'ลบ',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.family_restroom_rounded,
              size: 72,
              color: theme.hintColor,
            ),
            const SizedBox(height: 12),
            Text('ยังไม่มีโปรไฟล์เด็ก', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'เพิ่มโปรไฟล์แรกเพื่อเริ่มต้นวัดผลการระบายสี',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('สร้างโปรไฟล์ใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}

/// BottomSheet สร้าง/แก้ไขโปรไฟล์ (ชื่อ + อายุ 4/5)
class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  int _age = 4;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _nameCtrl.text = (widget.initial!['name'] as String?) ?? '';
      _age = (widget.initial!['age'] as int?) ?? 4;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {'name': _nameCtrl.text.trim(), 'age': _age});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Form(
        key: _form,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.initial == null ? 'สร้างโปรไฟล์ใหม่' : 'แก้ไขโปรไฟล์',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'ชื่อเด็ก',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'กรอกชื่อก่อนนะ';
                  if (v.trim().length < 2) return 'ชื่อสั้นไปนิด';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('อายุ', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('4 ขวบ'),
                    selected: _age == 4,
                    onSelected: (_) => setState(() => _age = 4),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('5 ขวบ'),
                    selected: _age == 5,
                    onSelected: (_) => setState(() => _age = 5),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('ยืนยัน'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
