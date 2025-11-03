// lib/features/profiles/profile_list_screen.dart
import 'package:flutter/material.dart';

import '../../data/repositories/cohort_repo.dart';
import '../templates/template_picker_screen.dart';
import '../../routes.dart';

// ⭐ เพิ่ม: ใช้ดึงประวัติมาทำกราฟย่อ
import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo.dart';

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({super.key});

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  final _repo = CohortRepo();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  int? _ageFilter; // null | 4 | 5
  String _sort = 'recent'; // recent | name

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose(); // กัน memory leak
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _repo.getAll();
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  String _profileKeyOf(Map<String, dynamic> it) =>
      (it['id'] ?? it['key'] ?? it['name']).toString();

  List<Map<String, dynamic>> get _visible {
    var list = List<Map<String, dynamic>>.from(_items);

    if (_ageFilter != null) {
      list = list.where((e) => (e['age'] as int?) == _ageFilter).toList();
    }

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((e) => (e['name']?.toString().toLowerCase() ?? '').contains(q))
          .toList();
    }

    if (_sort == 'name') {
      list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    } else {
      // recent: อันล่าสุดอยู่บนสุด
      list = list.reversed.toList();
    }
    return list;
  }

  Future<void> _openEditor({Map<String, dynamic>? edit}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProfileEditor(initial: edit),
    );

    if (result == null) return;

    if (edit == null) {
      await _repo.add(name: result['name'], age: result['age']);
    } else {
      // โค้ดง่ายๆ: ลบแล้วเพิ่มใหม่ (ถ้า _repo มี update() ใช้แทนได้)
      await _repo.remove(edit['id'] as String);
      await _repo.add(name: result['name'], age: result['age']);
    }
    await _load();
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const TemplatePickerScreen(),
        settings: RouteSettings(arguments: {'profile': item}),
      ),
    );
  }

  void _openHistory(Map<String, dynamic> item) {
    final key = _profileKeyOf(item);
    Nav.toHistory(context, key);
  }

  // ===== Palette (โทนสด) ตามอายุ =====
  List<Color> _avatarGradient(int age) => age == 5
      ? const [Color(0xFFFF8A80), Color(0xFFFFD54F)] // coral -> sunshine
      : const [Color(0xFF7CC8FF), Color(0xFFA97BFF)]; // sky   -> violet
  Color _cardBorder(int age) =>
      age == 5 ? const Color(0xFFFFC1B3) : const Color(0xFFBDA7FF);
  Color _badgeBg(int age) =>
      age == 5 ? const Color(0xFFFFE3DC) : const Color(0xFFE8DEFF);
  Color _badgeFg(int age) =>
      age == 5 ? const Color(0xFF5D2B23) : const Color(0xFF2E1E6B);
  Color _chipSelectedBg(int? age) =>
      age == 5 ? const Color(0xFFFFF0E0) : const Color(0xFFEDE4FF);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ความสูงการ์ดแบบคงที่/ยืดหยุ่นเล็กน้อย (กันล้นแนวตั้งทุกจอ)
    final screenH = MediaQuery.of(context).size.height;
    final double cardHeight = screenH < 700
        ? 250
        : (screenH < 820 ? 264 : 276); // ⤴ สูงขึ้นนิดเผื่อกราฟ
    final bottomInsets = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add_rounded),
        label: const Text('โปรไฟล์ใหม่'),
        backgroundColor: const Color(0xFF7C4DFF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  // ---------- SliverAppBar + Search ----------
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 118,
                    title: const Text('เลือกโปรไฟล์เด็ก'),
                    flexibleSpace: FlexibleSpaceBar(
                      background: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 56, 16, 8),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) =>
                                FocusScope.of(context).unfocus(),
                            decoration: InputDecoration(
                              hintText: 'ค้นหาชื่อ…',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_searchCtrl.text.isNotEmpty)
                                    IconButton(
                                      tooltip: 'ล้าง',
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.clear_rounded),
                                    ),
                                  PopupMenuButton<String>(
                                    tooltip: 'จัดเรียง',
                                    onSelected: (v) =>
                                        setState(() => _sort = v),
                                    itemBuilder: (_) => [
                                      CheckedPopupMenuItem(
                                        checked: _sort == 'recent',
                                        value: 'recent',
                                        child: const Text('ล่าสุดอยู่บน'),
                                      ),
                                      CheckedPopupMenuItem(
                                        checked: _sort == 'name',
                                        value: 'name',
                                        child: const Text('เรียงตามชื่อ ก-ฮ'),
                                      ),
                                    ],
                                    child: const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.sort_rounded),
                                    ),
                                  ),
                                ],
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFEFF7FF),
                              border: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: Color(0xFFB3E0FF),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: Color(0xFFB3E0FF),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(
                                  color: Color(0xFF7C4DFF),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ---------- Sticky Filter ----------
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyWrapHeader(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _ColoredChoiceChip(
                            label: 'ทั้งหมด',
                            selected: _ageFilter == null,
                            selectedBg: const Color(0xFFEDE4FF),
                            onTap: () => setState(() => _ageFilter = null),
                          ),
                          _ColoredChoiceChip(
                            label: '4 ขวบ',
                            selected: _ageFilter == 4,
                            selectedBg: _chipSelectedBg(4),
                            onTap: () => setState(() => _ageFilter = 4),
                          ),
                          _ColoredChoiceChip(
                            label: '5 ขวบ',
                            selected: _ageFilter == 5,
                            selectedBg: _chipSelectedBg(5),
                            onTap: () => setState(() => _ageFilter = 5),
                          ),
                          // ตัวนับจำนวนทั้งหมด
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4FF),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFB3E0FF),
                              ),
                            ),
                            child: Text(
                              '${_items.length}',
                              style: const TextStyle(
                                color: Color(0xFF0B3D91),
                                fontWeight: FontWeight.w800,
                                letterSpacing: .2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ---------- Content ----------
                  if (_visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(onAdd: _openEditor),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        90 + bottomInsets,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: cardHeight, // ✅ กันล้นแนวตั้ง
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _visible.length,
                        itemBuilder: (_, i) {
                          final it = _visible[i];
                          final idOrKey = _profileKeyOf(it);

                          return Dismissible(
                            key: ValueKey(idOrKey),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              await _confirmDelete(it);
                              return false;
                            },
                            background: _deleteBg(
                              cs.errorContainer,
                              cs.onErrorContainer,
                            ),
                            child: _GridProfileCard(
                              name:
                                  (it['name'] as String?)?.trim().isEmpty ==
                                      true
                                  ? 'ไม่ทราบชื่อ'
                                  : it['name'] as String,
                              age: (it['age'] as int?) ?? 0,
                              onOpen: () => _openTemplates(it),
                              onEdit: () => _openEditor(edit: it),
                              onDelete: () => _confirmDelete(it),
                              onHistory: () => _openHistory(it),
                              avatarGradient: _avatarGradient(
                                (it['age'] as int?) ?? 0,
                              ),
                              cardBorder: _cardBorder((it['age'] as int?) ?? 0),
                              badgeBg: _badgeBg((it['age'] as int?) ?? 0),
                              badgeFg: _badgeFg((it['age'] as int?) ?? 0),

                              // ⭐ ใหม่: สำหรับโหลดกราฟย่อ
                              profileKey: idOrKey,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
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

// ===== Sticky header สำหรับ Wrap =====
class _StickyWrapHeader extends SliverPersistentHeaderDelegate {
  _StickyWrapHeader({required this.child});
  final Widget child;

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(context, shrinkOffset, overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickyWrapHeader oldDelegate) => false;
}

// ===== ChoiceChip แบบสดชื่น =====
class _ColoredChoiceChip extends StatelessWidget {
  const _ColoredChoiceChip({
    required this.label,
    required this.selected,
    required this.selectedBg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      side: const BorderSide(color: Color(0xFFB3E0FF)),
      selectedColor: selectedBg,
      labelStyle: TextStyle(
        color: selected
            ? const Color(0xFF0B3D91)
            : Theme.of(context).colorScheme.onSurface,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

// ===== การ์ดแบบ Grid (fix overflow) + สปาร์คไลน์ =====
class _GridProfileCard extends StatelessWidget {
  const _GridProfileCard({
    required this.name,
    required this.age,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onHistory,
    required this.avatarGradient,
    required this.cardBorder,
    required this.badgeBg,
    required this.badgeFg,
    required this.profileKey,
  });

  final String name;
  final int age;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onHistory;

  final List<Color> avatarGradient;
  final Color cardBorder;
  final Color badgeBg;
  final Color badgeFg;

  final String profileKey;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '👦';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  Future<_TrendData> _loadTrend() async {
    final list = await HistoryRepo.I.listByProfile(profileKey);
    // เก่า -> ใหม่
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final last = list.length > 8 ? list.sublist(list.length - 8) : list;
    final points = last.map((e) => e.zSum).toList();
    final latest = points.isNotEmpty ? points.last : null;
    final prev = points.length >= 2 ? points[points.length - 2] : null;
    return _TrendData(points: points, latest: latest, previous: prev);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      elevation: 0.5,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: avatarGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ชื่อ (1 บรรทัด, ellipsis)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E2554),
                  ),
                ),

                const SizedBox(height: 4),

                // ป้ายอายุ
                _AgeBadge(age: age, bg: badgeBg, fg: badgeFg),

                // ===== มินิกราฟ Index (zSum) + Δ =====
                const SizedBox(height: 10),
                FutureBuilder<_TrendData>(
                  future: _loadTrend(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const SizedBox(
                        height: 50,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final data = snap.data ?? _TrendData.empty();
                    final latest = data.latest;
                    final prev = data.previous;
                    final delta = (latest != null && prev != null)
                        ? (latest - prev)
                        : null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Index (z)',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.hintColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (latest != null)
                              Text(
                                latest.toStringAsFixed(2),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            const SizedBox(width: 6),
                            if (delta != null) _DeltaBadge(value: delta),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 34,
                          child: _Sparkline(
                            points: data.points,
                            stroke: const Color(0xFF5E8BFF),
                            fill: const Color(0x335E8BFF),
                            guideColor: theme.dividerColor,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const Spacer(),

                // แถวปุ่มล่าง
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'ประวัติ',
                      onPressed: onHistory,
                      icon: const Icon(Icons.timeline_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF7FF),
                        foregroundColor: const Color(0xFF0056B3),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'เพิ่มเติม',
                      onSelected: (v) {
                        if (v == 'open') onOpen();
                        if (v == 'edit') onEdit();
                        if (v == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'open',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.play_arrow_rounded),
                            title: Text('เริ่มเลือกเทมเพลต'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.edit_rounded),
                            title: Text('แก้ไขโปรไฟล์'),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            iconColor: Theme.of(context).colorScheme.error,
                            textColor: Theme.of(context).colorScheme.error,
                            leading: const Icon(Icons.delete_outline_rounded),
                            title: const Text('ลบโปรไฟล์'),
                          ),
                        ),
                      ],
                      child: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendData {
  final List<double> points;
  final double? latest;
  final double? previous;
  const _TrendData({
    required this.points,
    required this.latest,
    required this.previous,
  });
  factory _TrendData.empty() =>
      const _TrendData(points: [], latest: null, previous: null);
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
                ? '+${value.toStringAsFixed(2)}'
                : value.toStringAsFixed(2),
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

class _Sparkline extends StatelessWidget {
  const _Sparkline({
    required this.points,
    required this.stroke,
    required this.fill,
    required this.guideColor,
  });

  final List<double> points;
  final Color stroke;
  final Color fill;
  final Color guideColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparkPainter(points, stroke, fill, guideColor),
      size: Size.infinite,
    );
  }
}

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

    // เส้น guide ล่าง
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

    final xStep = points.length <= 1 ? w : w / (points.length - 1);
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

    // เงาใต้กราฟ
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

class _AgeBadge extends StatelessWidget {
  const _AgeBadge({required this.age, required this.bg, required this.fg});
  final int age;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'อายุ $age ขวบ',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: fg,
        ),
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

/// ===== BottomSheet: สร้าง/แก้ไขโปรไฟล์ =====
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
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: inset),
      child: Material(
        color: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _form,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // handle
                  Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  // title
                  Text(
                    widget.initial == null
                        ? 'สร้างโปรไฟล์ใหม่'
                        : 'แก้ไขโปรไฟล์',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),

                  // name field
                  TextFormField(
                    controller: _nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'ชื่อเด็ก',
                      filled: true,
                      fillColor: const Color(0xFFEFF7FF),
                      prefixIcon: Container(
                        margin: const EdgeInsets.only(left: 8, right: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCEBFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.badge_outlined),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFB3E0FF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFB3E0FF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF7C4DFF)),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'กรอกชื่อก่อนนะ';
                      }
                      if (v.trim().length < 2) return 'ชื่อสั้นไปนิด';
                      return null;
                    },
                  ),

                  const SizedBox(height: 14),

                  // age chips
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'อายุ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check_circle, size: 18),
                            SizedBox(width: 6),
                            Text('4 ขวบ'),
                          ],
                        ),
                        selected: _age == 4,
                        onSelected: (_) => setState(() => _age = 4),
                        selectedColor: const Color(0xFFEDE4FF),
                        side: const BorderSide(color: Color(0xFFB3E0FF)),
                        labelStyle: TextStyle(
                          fontWeight: _age == 4
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _age == 4
                              ? const Color(0xFF0B3D91)
                              : cs.onSurface,
                        ),
                      ),
                      ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check_circle, size: 18),
                            SizedBox(width: 6),
                            Text('5 ขวบ'),
                          ],
                        ),
                        selected: _age == 5,
                        onSelected: (_) => setState(() => _age = 5),
                        selectedColor: const Color(0xFFFFF0E0),
                        side: const BorderSide(color: Color(0xFFB3E0FF)),
                        labelStyle: TextStyle(
                          fontWeight: _age == 5
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _age == 5
                              ? const Color(0xFF0B3D91)
                              : cs.onSurface,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('ยกเลิก'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                            side: BorderSide(color: cs.outlineVariant),
                            foregroundColor: const Color(0xFF6B5FB2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GradientButton(
                          onPressed: _submit,
                          icon: Icons.check_rounded,
                          label: 'ยืนยัน',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มแคปซูลไล่สี (ม่วง→ฟ้า)
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(50),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7C4DFF), Color(0xFF5E8BFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
