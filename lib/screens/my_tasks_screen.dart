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
        _debounce = Timer(Duration(milliseconds: 250), _load);
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
      if (mounted) showSnack(context, '${t.serial} → ${statusLabels[status]}');
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
        title: Text('My tasks'),
        actions: [
          ListenableBuilder(
            listenable: session,
            builder: (context, _) => Padding(
              padding: EdgeInsets.only(right: 4),
              child: Tooltip(
                message: session.live ? 'Live sync on' : 'Offline: pull to refresh',
                child: Icon(Icons.circle, size: 10, color: session.live ? AppColors.coral : AppColors.cream.withValues(alpha: .5)),
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
                SizedBox(height: 120),
                if (_error != null)
                  EmptyState(icon: Icons.cloud_off, title: 'Could not load tasks', subtitle: _error)
                else
                  Center(child: CircularProgressIndicator()),
              ])
            : _buildList(tasks),
      ),
    );
  }

  Widget _buildList(List<Task> tasks) {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final endOfWeek = endOfToday.add(Duration(days: 7));
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
      return ListView(children: [
        _SummaryCard(open: 0, overdue: 0, done: tasks.length),
        SizedBox(height: 24),
        EmptyState(icon: Icons.celebration_outlined, title: 'All caught up!', subtitle: 'No open tasks assigned to you.'),
      ]);
    }

    final overdue = open.where((t) => t.isOverdue).length;
    return ListView(
      padding: EdgeInsets.only(bottom: 24),
      children: [
        _SummaryCard(open: open.length, overdue: overdue, done: tasks.length - open.length),
        for (final (label, items) in groups) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              '$label · ${items.length}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: label == 'Overdue' ? AppColors.danger : AppColors.text),
            ),
          ),
          for (final t in items)
            Dismissible(
              key: ValueKey(t.id),
              direction: t.isDone ? DismissDirection.none : DismissDirection.startToEnd,
              background: Container(
                color: AppColors.strong,
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.only(left: 24),
                child: Row(children: [Icon(Icons.check, color: AppColors.onStrong), SizedBox(width: 8), Text('Done', style: TextStyle(color: AppColors.onStrong))]),
              ),
              confirmDismiss: (_) async {
                await _quickStatus(t, 'done');
                return false; // list reloads from the server instead
              },
              child: TaskTile(task: t, onTap: () => _open(t), onPunch: (status) => _quickStatus(t, status)),
            ),
        ],
        Padding(
          padding: EdgeInsets.all(16),
          child: Text('Tip: swipe a ticket right to punch it Done.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
    final hour = DateTime.now().hour;
    final hello = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    final name = session.user?.name.split(' ').first ?? '';
    final line = overdue > 0
        ? 'Review overdue tasks first.'
        : open == 0
            ? 'You’re all caught up.'
            : 'Your tasks are on track.';
    Widget cell(String label, int value, {bool hot = false, bool first = false}) => Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              border: first ? null : Border(left: BorderSide(color: AppColors.border, width: 1.5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
              SizedBox(height: 2),
              Text('$value',
                  style: TextStyle(fontFamily: monoFont, fontSize: 22, fontWeight: FontWeight.w700, color: hot ? AppColors.danger : AppColors.text)),
            ]),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? hello : '$hello, $name', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, color: AppColors.cream)),
          SizedBox(height: 4),
          Text(line, style: TextStyle(color: AppColors.navyInk, fontSize: 14.5)),
          SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: IntrinsicHeight(
              child: Row(children: [
                cell('Open', open, first: true),
                cell('Late', overdue, hot: overdue > 0),
                cell('Done', done),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
