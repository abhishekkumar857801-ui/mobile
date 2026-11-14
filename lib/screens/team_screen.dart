import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'new_task_sheet.dart';
import 'task_detail_screen.dart';

/// One team: its task list and a phone-sized view of the risk dashboard.
class TeamScreen extends StatefulWidget {
  final Team team;
  const TeamScreen({super.key, required this.team});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Task>? _tasks;
  List<Project> _projects = [];
  Map<String, dynamic>? _dashboard;
  String? _projectFilter;
  String? _error;
  StreamSubscription<LiveEvent>? _sub;
  Timer? _debounce;

  String get _teamId => widget.team.id;

  @override
  void initState() {
    super.initState();
    session.subscribeTeam(_teamId);
    _load();
    _sub = session.events.listen((e) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), _load);
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
      final results = await Future.wait([
        session.api.get('/teams/$_teamId/tasks'),
        session.api.get('/teams/$_teamId/projects'),
        session.api.get('/teams/$_teamId/dashboard'),
      ]);
      if (!mounted) return;
      setState(() {
        _tasks = (results[0]['tasks'] as List).map((t) => Task.fromJson(t)).toList();
        _projects = (results[1]['projects'] as List).map((p) => Project.fromJson(p)).toList();
        _dashboard = results[2] as Map<String, dynamic>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _newTask() async {
    if (_projects.isEmpty) {
      showSnack(context, 'This team has no projects yet. A manager can create one on the web app.');
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewTaskSheet(team: widget.team, projects: _projects, defaultProject: _projectFilter),
    );
    if (created == true) {
      _load();
      if (mounted) showSnack(context, 'Task created. It is already on the web board.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.team.name),
          actions: [
            IconButton(
              tooltip: 'Copy join code',
              icon: const Icon(Icons.person_add_alt),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.team.joinCode));
                showSnack(context, 'Join code ${widget.team.joinCode} copied');
              },
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Tasks'), Tab(text: 'Risk')]),
        ),
        floatingActionButton: FloatingActionButton(onPressed: _newTask, tooltip: 'New task', child: const Icon(Icons.add_task)),
        body: _tasks == null
            ? (_error != null
                ? EmptyState(icon: Icons.cloud_off, title: 'Could not load team', subtitle: _error)
                : const Center(child: CircularProgressIndicator()))
            : TabBarView(children: [_tasksTab(), _riskTab()]),
      ),
    );
  }

  Widget _tasksTab() {
    final tasks = _tasks!.where((t) => _projectFilter == null || t.project?.id == _projectFilter).toList()
      ..sort((a, b) {
        final s = taskStatuses.indexOf(a.status).compareTo(taskStatuses.indexOf(b.status));
        return s != 0 ? s : (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999));
      });
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            ChoiceChip(label: const Text('All'), selected: _projectFilter == null, onSelected: (_) => setState(() => _projectFilter = null)),
            for (final p in _projects)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: hexColor(p.color), radius: 5),
                  label: Text(p.name),
                  selected: _projectFilter == p.id,
                  onSelected: (_) => setState(() => _projectFilter = p.id),
                ),
              ),
          ]),
        ),
        if (tasks.isEmpty) const EmptyState(icon: Icons.inbox_outlined, title: 'No tasks here yet'),
        for (final t in tasks)
          TaskTile(
            task: t,
            showTeam: false,
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id)));
              _load();
            },
          ),
      ]),
    );
  }

  Widget _riskTab() {
    final d = _dashboard!;
    final summary = d['summary'] as Map<String, dynamic>;
    final members = (d['members'] as List).cast<Map<String, dynamic>>();
    final projects = (d['projects'] as List).cast<Map<String, dynamic>>();
    final atRisk = (d['atRiskTasks'] as List).cast<Map<String, dynamic>>();
    final scheme = Theme.of(context).colorScheme;

    Widget stat(String label, dynamic v, {bool alert = false}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text('$v', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: alert && v != 0 ? AppColors.danger : null)),
                Text(label, style: TextStyle(fontSize: 11, color: scheme.outline), textAlign: TextAlign.center),
              ]),
            ),
          ),
        );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          stat('Open', summary['openTasks']),
          stat('Overdue', summary['overdueTasks'], alert: true),
          stat('Overloaded', summary['overloadedMembers'], alert: true),
          stat('At risk', summary['projectsAtRisk'], alert: true),
        ]),
        const SizedBox(height: 12),
        Text('Team workload', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final m in members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              UserAvatar(AppUser.fromJson(m['user'])),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(m['user']['name'], style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${m['loadPercent']}%  '),
                    Pill(m['status'], levelColors[m['status']] ?? Colors.grey),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ((m['loadPercent'] as num) / 150).clamp(0, 1).toDouble(),
                      minHeight: 8,
                      color: levelColors[m['status']],
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Text('Project deadline risk', style: Theme.of(context).textTheme.titleMedium),
        for (final p in projects)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: levelColors[p['riskLevel']] ?? Colors.grey, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(p['project']['name'], style: const TextStyle(fontWeight: FontWeight.w700))),
                  Pill(p['riskLevel'] == 'done' ? 'complete' : '${p['riskLevel']} · ${p['riskScore']}', levelColors[p['riskLevel']] ?? Colors.grey),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: (p['completion'] as num) / 100, minHeight: 6, borderRadius: BorderRadius.circular(6)),
                const SizedBox(height: 6),
                Text(
                  '${p['completion']}% done · ${(p['daysLeft'] as num) > 0 ? '${p['daysLeft']} days left' : 'deadline passed'} · ${p['remainingHours']}h remaining',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                for (final r in (p['reasons'] as List)) Text('• $r', style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        if (atRisk.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Needs attention', style: Theme.of(context).textTheme.titleMedium),
          for (final r in atRisk)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: UserAvatar(AppUser.maybe(r['task']['assignee'])),
              title: Text(r['task']['title']),
              trailing: Pill(r['reason'], r['reason'] == 'Overdue' ? AppColors.danger : AppColors.warn),
            ),
        ],
      ]),
    );
  }
}
