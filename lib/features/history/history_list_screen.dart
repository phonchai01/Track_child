// lib/features/history/history_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';

import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo.dart';

class HistoryListScreen extends StatefulWidget {
  const HistoryListScreen({super.key, required this.profileKey});
  final String profileKey;

  @override
  State<HistoryListScreen> createState() => _HistoryListScreenState();
}

class _HistoryListScreenState extends State<HistoryListScreen> {
  late Future<List<HistoryRecord>> _future;

  // ---------------- Filters ----------------
  String _tpl = 'all'; // all | fish | pencil | icecream
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file,
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        );
      }
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: 76,
    height: 76,
    decoration: BoxDecoration(
      color: Colors.black12.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: const Icon(Icons.image_not_supported_outlined),
  );

  String _templateLabel(String key) {
    final k = key.toLowerCase();
    if (k.contains('fish') || k.contains('ปลา')) return '🐟 ปลา';
    if (k.contains('pencil') || k.contains('ดินสอ')) return '✏️ ดินสอ';
    if (k.contains('ice')) return '🍦 ไอศกรีม';
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
        .where((r) => _matchTemplate(r) && _matchLevel(r))
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
    final very = s.contains('มาก');
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
    return 3;
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

  Color _levelColor(String level, ColorScheme cs) {
    final n = _normalizeLevel(level);
    switch (n) {
      case 'low':
        return const Color(0xFFFFE2E2);
      case 'high':
        return const Color(0xFFE6FFDA);
      default:
        return cs.secondaryContainer;
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
          _FancyFilterBar(
            tpl: _tpl,
            lvl: _lvl,
            desc: _desc,
            onChanged: (tpl, lvl, desc) {
              setState(() {
                _tpl = tpl;
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
                  return const _EmptyState();
                }

                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final r = items[i];
                      final idx = r.zSum.toStringAsFixed(3);
                      final title = _templateLabel(r.templateKey);
                      final subtitle =
                          '${_fmtDate(r.createdAt)}\n'
                          'H=${r.h.toStringAsFixed(3)}  '
                          'C=${r.c.toStringAsFixed(3)}  '
                          'Blank=${r.blank.toStringAsFixed(3)}  '
                          'COTL=${r.cotl.toStringAsFixed(3)}';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            /* TODO: detail page */
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: cs.outlineVariant.withOpacity(.4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // แถบไล่สีด้านซ้าย
                                Container(
                                  width: 4,
                                  height: 76,
                                  decoration: const BoxDecoration(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(999),
                                    ),
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF7C4DFF),
                                        Color(0xFF5E8BFF),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _thumb(r.imagePath),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
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
                                    // Index badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        'Index  $idx',
                                        style: TextStyle(
                                          color: cs.onPrimaryContainer,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _starRow(r.level),
                                    const SizedBox(height: 4),
                                    // Level badge สีตามระดับ
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _levelColor(r.level, cs),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        r.level,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
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

/// แถบตัวกรองแบบสวย: Template • Level • Sort + ตัวนับ
class _FancyFilterBar extends StatelessWidget {
  const _FancyFilterBar({
    required this.tpl,
    required this.lvl,
    required this.desc,
    required this.onChanged,
  });

  final String tpl; // all | fish | pencil | icecream
  final String lvl; // all | low | normal | high
  final bool desc;
  final void Function(String tpl, String lvl, bool desc) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Color? selectedBg,
    }) {
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: selectedBg ?? cs.secondaryContainer,
        side: BorderSide(color: cs.outlineVariant),
        labelStyle: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? cs.onSecondaryContainer : cs.onSurface,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // แถวบน: Template + Sort + Counter
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    chip(
                      label: 'ทั้งหมด',
                      selected: tpl == 'all',
                      onTap: () => onChanged('all', lvl, desc),
                      selectedBg: const Color(0xFFEDE4FF),
                    ),
                    chip(
                      label: 'ปลา',
                      selected: tpl == 'fish',
                      onTap: () => onChanged('fish', lvl, desc),
                      selectedBg: const Color(0xFFE8F3FF),
                    ),
                    chip(
                      label: 'ดินสอ',
                      selected: tpl == 'pencil',
                      onTap: () => onChanged('pencil', lvl, desc),
                      selectedBg: const Color(0xFFFFF1E3),
                    ),
                    chip(
                      label: 'ไอศกรีม',
                      selected: tpl == 'icecream',
                      onTap: () => onChanged('icecream', lvl, desc),
                      selectedBg: const Color(0xFFE9FFE8),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: desc ? 'เรียง: ใหม่ → เก่า' : 'เรียง: เก่า → ใหม่',
                icon: Icon(desc ? Icons.south : Icons.north),
                onPressed: () => onChanged(tpl, lvl, !desc),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // แถวล่าง: Level
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(
                label: 'ทุกระดับ',
                selected: lvl == 'all',
                onTap: () => onChanged(tpl, 'all', desc),
              ),
              chip(
                label: 'ต่ำ/ต่ำมาก',
                selected: lvl == 'low',
                onTap: () => onChanged(tpl, 'low', desc),
                selectedBg: const Color(0xFFFFE2E2),
              ),
              chip(
                label: 'ปกติ/ตามเกณฑ์',
                selected: lvl == 'normal',
                onTap: () => onChanged(tpl, 'normal', desc),
                selectedBg: cs.secondaryContainer,
              ),
              chip(
                label: 'สูง/สูงมาก',
                selected: lvl == 'high',
                onTap: () => onChanged(tpl, 'high', desc),
                selectedBg: const Color(0xFFE6FFDA),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 72, color: theme.hintColor),
            const SizedBox(height: 12),
            Text('ยังไม่มีข้อมูล', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'เริ่มประเมินครั้งแรกเพื่อดูประวัติที่นี่',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
