import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'task_detail_screen.dart';

/// The main phone screen: everything assigned to me across all teams,
/// grouped by urgency, with live updates from the web app.
class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});
  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  List<Task>? _tasks;
  String? _error;
  bool _showDone = false;
  StreamSubscription<LiveEvent>? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = session.events.listen((e) {
      if (e.name.startsWith('task') || e.name == 'notify') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), _load);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await session.api.get('/tasks/mine');
      if (!mounted) return;
      setState(() {
        _tasks = (res['tasks'] as List).map((t) => Task.fromJson(t)).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _quickStatus(Task t, String status) async {
    try {
      await session.api.patch('/tasks/${t.id}', {'status': status});
      await _load();
      if (mounted) showSnack(context, '"${t.title}" → ${statusLabels[status]}');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _open(Task t) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My tasks'),
        actions: [
          ListenableBuilder(
            listenable: session,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: session.live ? 'Live sync on' : 'Offline: pull to refresh',
                child: Icon(Icons.circle, size: 10, color: session.live ? AppColors.success : AppColors.muted),
              ),
            ),
          ),
          IconButton(
            tooltip: _showDone ? 'Hide completed' : 'Show completed',
            icon: Icon(_showDone ? Icons.visibility_off_outlined : Icons.done_all),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: tasks == null
            ? ListView(children: [
                const SizedBox(height: 120),
                if (_error != null)
                  EmptyState(icon: Icons.cloud_off, title: 'Could not load tasks', subtitle: _error)
                else
                  const Center(child: CircularProgressIndicator()),
              ])
            : _buildList(tasks),
      ),
    );
  }

  Widget _buildList(List<Task> tasks) {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final endOfWeek = endOfToday.add(const Duration(days: 7));
    final open = tasks.where((t) => !t.isDone).toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));

    final groups = <(String, List<Task>)>[
      ('Overdue', open.where((t) => t.isOverdue).toList()),
      ('Today', open.where((t) => !t.isOverdue && t.dueDate != null && !t.dueDate!.isAfter(endOfToday)).toList()),
      ('This week', open.where((t) => t.dueDate != null && t.dueDate!.isAfter(endOfToday) && !t.dueDate!.isAfter(endOfWeek)).toList()),
      ('Later', open.where((t) => t.dueDate == null || t.dueDate!.isAfter(endOfWeek)).toList()),
      if (_showDone) ('Completed', tasks.where((t) => t.isDone).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();

    if (groups.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 100),
        EmptyState(icon: Icons.celebration_outlined, title: 'All caught up!', subtitle: 'No open tasks assigned to you.'),
      ]);
    }

    final overdue = open.where((t) => t.isOverdue).length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SummaryCard(open: open.length, overdue: overdue, done: tasks.length - open.length),
        for (final (label, items) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              '$label (${items.length})',
              style: TextStyle(fontWeight: FontWeight.w700, color: label == 'Overdue' ? AppColors.danger : AppColors.text),
            ),
          ),
          for (final t in items)
            Dismissible(
              key: ValueKey(t.id),
              direction: t.isDone ? DismissDirection.none : DismissDirection.startToEnd,
              background: Container(
                color: AppColors.success,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 24),
                child: const Row(children: [Icon(Icons.check, color: Colors.white), SizedBox(width: 8), Text('Done', style: TextStyle(color: Colors.white))]),
              ),
              confirmDismiss: (_) async {
                await _quickStatus(t, 'done');
                return false; // list reloads from the server instead
              },
              child: TaskTile(task: t, onTap: () => _open(t)),
            ),
        ],
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Tip: swipe a task right to mark it done.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int open, overdue, done;
  const _SummaryCard({required this.open, required this.overdue, required this.done});

  @override
  Widget build(BuildContext context) {
    final total = open + done;
    final pct = total == 0 ? 0.0 : done / total;
    final hour = DateTime.now().hour;
    final hello = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    Widget stat(String label, int v, IconData icon, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 2),
              Text('$v', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$hello,', style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w600)),
              Text(
                session.user?.name.split(' ').first ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                overdue > 0 ? '$overdue task(s) overdue.' : 'You\'re on track today.',
                style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 13),
              ),
            ]),
          ),
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: pct,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                color: AppColors.yellow,
                backgroundColor: Colors.white24,
                constraints: const BoxConstraints.tightFor(width: 64, height: 64),
              ),
              Text('${(pct * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          stat('Open', open, Icons.inbox_rounded, AppColors.primary),
          const SizedBox(width: 8),
          stat('Overdue', overdue, Icons.local_fire_department_rounded, AppColors.orange),
          const SizedBox(width: 8),
          stat('Done', done, Icons.check_circle_rounded, AppColors.success),
        ]),
      ]),
    );
  }
}
