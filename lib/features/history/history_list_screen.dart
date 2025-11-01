// lib/features/history/history_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';

import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo.dart';

class HistoryListScreen extends StatefulWidget {
  const HistoryListScreen({super.key, required this.profileKey});

  /// คีย์ของโปรไฟล์ที่จะดึงประวัติ
  final String profileKey;

  @override
  State<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends State<HistoryListScreen> {
  late Future<List<HistoryRecord>> _future;

  // ---------------- Filters ----------------
  String _tpl = 'all'; // all | fish | pencil | icecream
  String _age = 'all'; // all | 4 | 5
  String _lvl = 'all'; // all | low | normal | high
  bool _desc = true; // ใหม่->เก่า

  @override
  void initState() {
    super.initState();
    _future = HistoryRepo.I.listByProfile(widget.profileKey);
  }

  Future<void> _reload() async {
    setState(() {
      _future = HistoryRepo.I.listByProfile(widget.profileKey);
    });
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบประวัติทั้งหมด'),
        content: const Text(
          'คุณแน่ใจหรือไม่ว่าต้องการลบประวัติทั้งหมดของโปรไฟล์นี้?',
        ),
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
    if (ok != true) return;

    await HistoryRepo.I.clearByProfile(widget.profileKey);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ลบประวัติแล้ว')));
    _reload();
  }

  // ---------------- Helpers ----------------
  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$dd  $hh:$mm';
  }

  Widget _thumb(String? path) {
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      }
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: 64,
    height: 64,
    decoration: BoxDecoration(
      color: Colors.black12.withOpacity(0.06),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.image_not_supported_outlined),
  );

  String _templateLabel(String key) {
    final k = key.toLowerCase();
    if (k.contains('fish') || k.contains('ปลา')) return 'ปลา';
    if (k.contains('pencil') || k.contains('ดินสอ')) return 'ดินสอ';
    if (k.contains('ice')) return 'ไอศกรีม';
    return key;
  }

  bool _matchTemplate(HistoryRecord r) {
    if (_tpl == 'all') return true;
    final k = r.templateKey.toLowerCase();
    switch (_tpl) {
      case 'fish':
        return k.contains('fish') || k.contains('ปลา');
      case 'pencil':
        return k.contains('pencil') || k.contains('ดินสอ');
      case 'icecream':
        return k.contains('ice') ||
            k.contains('ไอศกรีม') ||
            k.contains('ไอติม');
    }
    return true;
  }

  bool _matchAge(HistoryRecord r) {
    if (_age == 'all') return true;
    return r.age.toString() == _age;
  }

  // map ชื่อระดับหลายแบบ -> low/normal/high
  String _normalizeLevel(String s) {
    final x = s.trim().toLowerCase();
    if (x.contains('ต่ำ') || x.contains('below') || x.contains('worse'))
      return 'low';
    if (x.contains('สูง') || x.contains('above') || x.contains('better'))
      return 'high';
    return 'normal';
  }

  bool _matchLevel(HistoryRecord r) {
    if (_lvl == 'all') return true;
    return _normalizeLevel(r.level) == _lvl;
  }

  List<HistoryRecord> _applyFilters(List<HistoryRecord> items) {
    final filtered = items
        .where((r) => _matchTemplate(r) && _matchAge(r) && _matchLevel(r))
        .toList();
    filtered.sort(
      (a, b) => _desc
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );
    return filtered;
  }

  // ---------- ⭐ Stars ----------
  int _starsFromLevel(String level) {
    final s = level.toLowerCase();
    final very = s.contains('มาก'); // very
    final hi =
        s.contains('สูง') ||
        s.contains('above') ||
        s.contains('better') ||
        s.contains('greater');
    final low =
        s.contains('ต่ำ') ||
        s.contains('below') ||
        s.contains('worse') ||
        s.contains('under');
    final normal =
        s.contains('ปกติ') ||
        s.contains('เกณฑ์') ||
        s.contains('within') ||
        s.contains('normal') ||
        s.contains('standard');

    if (hi && very) return 5;
    if (hi) return 4;
    if (low && very) return 1;
    if (low) return 2;
    if (normal) return 3;
    return 3; // fallback กลาง ๆ
  }

  Widget _starRow(String level) {
    final stars = _starsFromLevel(level);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < stars ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: i < stars ? Colors.amber : Colors.grey.shade400,
        ),
      ),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการประเมิน'),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'ลบทั้งหมด',
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            tpl: _tpl,
            age: _age,
            lvl: _lvl,
            desc: _desc,
            onChanged: (tpl, age, lvl, desc) {
              setState(() {
                _tpl = tpl;
                _age = age;
                _lvl = lvl;
                _desc = desc;
              });
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<HistoryRecord>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                final items = _applyFilters(all);

                if (items.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อมูล'));
                }

                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = items[i];
                      final idx = r.zSum.toStringAsFixed(3);
                      final title =
                          '${_templateLabel(r.templateKey)} • อายุ ${r.age == 0 ? "-" : r.age} ขวบ';
                      final subtitle =
                          '${_fmtDate(r.createdAt)}\n'
                          'H=${r.h.toStringAsFixed(3)}  '
                          'C=${r.c.toStringAsFixed(3)}  '
                          'Blank=${r.blank.toStringAsFixed(3)}  '
                          'COTL=${r.cotl.toStringAsFixed(3)}';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            /* เพิ่มหน้ารายละเอียดได้ภายหลัง */
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.black12.withOpacity(0.05),
                              ),
                            ),
                            child: Row(
                              children: [
                                _thumb(r.imagePath),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Index',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    Text(
                                      idx,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    _starRow(r.level), // ⭐ แสดงดาว
                                    const SizedBox(height: 2),
                                    Text(
                                      r.level,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// แถบตัวกรองด้านบน: Template • Age • Level • Sort
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.tpl,
    required this.age,
    required this.lvl,
    required this.desc,
    required this.onChanged,
  });

  final String tpl; // all | fish | pencil | icecream
  final String age; // all | 4 | 5
  final String lvl; // all | low | normal | high
  final bool desc;
  final void Function(String tpl, String age, String lvl, bool desc) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // Template
          Expanded(
            child: _Labeled(
              label: 'เทมเพลต',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: tpl,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('ทั้งหมด')),
                    DropdownMenuItem(value: 'fish', child: Text('ปลา')),
                    DropdownMenuItem(value: 'pencil', child: Text('ดินสอ')),
                    DropdownMenuItem(value: 'icecream', child: Text('ไอศกรีม')),
                  ],
                  onChanged: (v) => onChanged(v ?? 'all', age, lvl, desc),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Age
          Expanded(
            child: _Labeled(
              label: 'อายุ',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: age,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('ทั้งหมด')),
                    DropdownMenuItem(value: '4', child: Text('4 ขวบ')),
                    DropdownMenuItem(value: '5', child: Text('5 ขวบ')),
                  ],
                  onChanged: (v) => onChanged(tpl, v ?? 'all', lvl, desc),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Level
          Expanded(
            child: _Labeled(
              label: 'ระดับผล',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: lvl,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('ทั้งหมด')),
                    DropdownMenuItem(value: 'low', child: Text('ต่ำ/ต่ำมาก')),
                    DropdownMenuItem(
                      value: 'normal',
                      child: Text('ปกติ/ตามเกณฑ์'),
                    ),
                    DropdownMenuItem(value: 'high', child: Text('สูง/สูงมาก')),
                  ],
                  onChanged: (v) => onChanged(tpl, age, v ?? 'all', desc),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Sort
          _Labeled(
            label: 'เรียง',
            child: IconButton.filledTonal(
              tooltip: desc ? 'ใหม่ → เก่า' : 'เก่า → ใหม่',
              icon: Icon(desc ? Icons.south : Icons.north),
              onPressed: () => onChanged(tpl, age, lvl, !desc),
            ),
          ),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: child,
        ),
      ],
    );
  }
}
