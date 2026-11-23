import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'new_task_sheet.dart';
import 'call_screen.dart';
import 'meetings_screen.dart';
import 'project_chat_screen.dart';
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
  List<Map<String, dynamic>> _liveCalls = []; // live video meetings in this team
  StreamSubscription<LiveEvent>? _sub;
  Timer? _debounce;

  String get _teamId => widget.team.id;

  @override
  void initState() {
    super.initState();
    session.subscribeTeam(_teamId);
    _load();
    _loadCalls();
    _sub = session.events.listen((e) {
      if (e.name == 'call:started' || e.name == 'call:updated' || e.name == 'call:ended') {
        _loadCalls();
        return;
      }
      // Ignore chat and call signalling traffic; reload only for task/team changes.
      if (e.name.startsWith('call:') || e.name.startsWith('chat:') || e.name == 'meeting:changed') return;
      _debounce?.cancel();
      _debounce = Timer(Duration(milliseconds: 300), _load);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _punch(Task t, String status) async {
    try {
      await session.api.patch('/tasks/${t.id}', {'status': status});
      await _load();
      if (mounted) showSnack(context, '${t.serial} → ${statusLabels[status]}');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _loadCalls() async {
    try {
      final res = await session.api.get('/teams/$_teamId/calls');
      if (mounted) {
        setState(() => _liveCalls = (res['calls'] as List).map((c) => Map<String, dynamic>.from(c as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _joinLiveCall(Map<String, dynamic> call) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          projectId: '${call['projectId']}',
          projectName: '${call['projectName']}',
          isManager: widget.team.isManager,
        ),
      ),
    );
    _loadCalls();
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

  // Creates a single-use invite code (e.g. BIN7K2) and copies it.
  Future<void> _newInvite() async {
    try {
      final res = await session.api.post('/teams/$_teamId/invites', {});
      final code = res['invite']['code'] as String;
      try {
        await Clipboard.setData(ClipboardData(text: code));
        if (mounted) showSnack(context, 'Invite code copied');
      } catch (_) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Copy invite code'),
            content: SelectableText(code),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
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
            if (widget.team.isManager)
              IconButton(
                tooltip: 'New invite code',
                icon: Icon(Icons.person_add_alt),
                onPressed: _newInvite,
              ),
          ],
          bottom: TabBar(tabs: [Tab(text: 'Tasks'), Tab(text: 'Risk')]),
        ),
        // Only the owner and managers can create tasks.
        floatingActionButton: widget.team.isManager
            ? FloatingActionButton(onPressed: _newTask, tooltip: 'New task', child: Icon(Icons.add_task))
            : null,
        body: _tasks == null
            ? (_error != null
                ? EmptyState(icon: Icons.cloud_off, title: 'Could not load team', subtitle: _error)
                : Center(child: CircularProgressIndicator()))
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
      child: ListView(padding: EdgeInsets.only(bottom: 96), children: [
        for (final call in _liveCalls)
          Card(
            margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
            color: Color(0xFFF4EDE0),
            child: ListTile(
              leading: Icon(Icons.circle, color: Color(0xFFFF6B5B), size: 14),
              title: Text('Live meeting · ${call['projectName']}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF14213D))),
              subtitle: Text('Started by ${call['startedBy']?['name'] ?? ''} · ${(call['participants'] as List?)?.length ?? 0} in the call',
                  style: TextStyle(color: Color(0xFF14213D))),
              trailing: FilledButton(onPressed: () => _joinLiveCall(call), child: Text('Join')),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            ChoiceChip(label: Text('All'), selected: _projectFilter == null, onSelected: (_) => setState(() => _projectFilter = null)),
            for (final p in _projects)
              Padding(
                padding: EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(p.name),
                  selected: _projectFilter == p.id,
                  onSelected: (_) => setState(() => _projectFilter = p.id),
                ),
              ),
          ]),
        ),
        if (_projectFilter != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    final project = _projects.firstWhere((p) => p.id == _projectFilter);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProjectChatScreen(project: project, isManager: widget.team.isManager)),
                    );
                  },
                  icon: Icon(Icons.chat_bubble_outline),
                  label: Text('Chat'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final project = _projects.firstWhere((p) => p.id == _projectFilter);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => MeetingsScreen(project: project, isManager: widget.team.isManager)),
                    );
                    _loadCalls();
                  },
                  icon: Icon(_liveCalls.any((c) => c['projectId'] == _projectFilter) ? Icons.circle : Icons.videocam_outlined,
                      color: _liveCalls.any((c) => c['projectId'] == _projectFilter) ? AppColors.danger : null, size: 18),
                  label: Text('Meetings'),
                ),
              ),
            ]),
          )
        else if (_projects.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text('Tip: pick a project above to open its chat.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        if (tasks.isEmpty) EmptyState(icon: Icons.inbox_outlined, title: 'No tasks here yet'),
        for (final t in tasks)
          TaskTile(
            task: t,
            showTeam: false,
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id)));
              _load();
            },
            // Owners/managers can punch any ticket; members only their own.
            onPunch: widget.team.isManager || t.assignee?.id == session.user?.id ? (status) => _punch(t, status) : null,
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
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text('$v', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: alert && v != 0 ? AppColors.danger : null)),
                Text(label, style: TextStyle(fontSize: 11, color: scheme.outline), textAlign: TextAlign.center),
              ]),
            ),
          ),
        );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.all(12), children: [
        Row(children: [
          stat('Open', summary['openTasks']),
          stat('Overdue', summary['overdueTasks'], alert: true),
          stat('Overloaded', summary['overloadedMembers'], alert: true),
          stat('At risk', summary['projectsAtRisk'], alert: true),
        ]),
        SizedBox(height: 12),
        Text('Team workload', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: 4),
        for (final m in members)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              UserAvatar(AppUser.fromJson(m['user'])),
              SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(m['user']['name'], style: TextStyle(fontWeight: FontWeight.w600))),
                    Text('${m['loadPercent']}%  '),
                    Pill(m['status'], levelColors[m['status']] ?? AppColors.muted),
                  ]),
                  SizedBox(height: 4),
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
        SizedBox(height: 12),
        Text('Project deadline risk', style: Theme.of(context).textTheme.titleMedium),
        for (final p in projects)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: levelColors[p['riskLevel']] ?? AppColors.muted, width: 1.5),
            ),
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(p['project']['name'], style: TextStyle(fontWeight: FontWeight.w700))),
                  Pill(p['riskLevel'] == 'done' ? 'complete' : '${p['riskLevel']} · ${p['riskScore']}', levelColors[p['riskLevel']] ?? AppColors.muted),
                ]),
                SizedBox(height: 8),
                LinearProgressIndicator(value: (p['completion'] as num) / 100, minHeight: 6, borderRadius: BorderRadius.circular(6)),
                SizedBox(height: 6),
                Text(
                  '${p['completion']}% done · ${(p['daysLeft'] as num) > 0 ? '${p['daysLeft']} days left' : 'deadline passed'} · ${p['remainingHours']}h remaining',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                for (final r in (p['reasons'] as List)) Text('• $r', style: TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        if (atRisk.isNotEmpty) ...[
          SizedBox(height: 12),
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
