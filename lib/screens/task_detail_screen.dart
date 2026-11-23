import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/session.dart';
import '../widgets/common.dart';

/// View and update one task: status, progress, and photo proof from the camera.
class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  Task? _task;
  String? _error;
  bool _busy = false;
  double? _progressDraft;
  // Owners/managers can edit everything; a member can only update status,
  // progress and proof on a task assigned to them.
  bool _isManager = false;

  bool get _canUpdate => _isManager || _task?.assignee?.id == session.user?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await session.api.get('/tasks/${widget.taskId}');
      final task = Task.fromJson(res['task']);
      final teamRes = await session.api.get('/teams/${task.teamId}');
      final role = teamRes['team']['myRole'];
      if (mounted) {
        setState(() {
          _task = task;
          _isManager = role == 'owner' || role == 'manager';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _update(Map<String, dynamic> changes, String message) async {
    setState(() => _busy = true);
    try {
      final res = await session.api.patch('/tasks/${widget.taskId}', changes);
      if (!mounted) return;
      setState(() {
        _task = Task.fromJson(res['task']);
        _progressDraft = null;
      });
      showSnack(context, message);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final res = await session.api.uploadFile('/tasks/${widget.taskId}/attachments', File(picked.path));
      if (!mounted) return;
      setState(() => _task = Task.fromJson(res['task']));
      showSnack(context, 'Photo attached. It is visible on the web board now.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDue() async {
    final t = _task!;
    final picked = await showDatePicker(
      context: context,
      initialDate: t.dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 730)),
    );
    if (picked != null) {
      final endOfDay = DateTime(picked.year, picked.month, picked.day, 23, 59);
      _update({'dueDate': endOfDay.toUtc().toIso8601String()}, 'Due date updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null
            ? EmptyState(icon: Icons.error_outline, title: 'Could not open task', subtitle: _error)
            : Center(child: CircularProgressIndicator()),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final (due, dueColor) = dueLabel(t);
    final progress = _progressDraft ?? t.progress;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.project?.name ?? 'Task'),
        bottom: _busy ? PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.all(16), children: [
          Row(children: [
            Pill(t.priority, priorityColors[t.priority] ?? AppColors.muted),
            SizedBox(width: 8),
            if (t.teamName.isNotEmpty) Text(t.teamName, style: TextStyle(color: scheme.outline)),
          ]),
          SizedBox(height: 8),
          Text(t.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (t.description.isNotEmpty) ...[
            SizedBox(height: 8),
            Text(t.description),
          ],
          SizedBox(height: 16),
          Card(
            child: Column(children: [
              ListTile(
                leading: UserAvatar(t.assignee),
                title: Text(t.assignee?.name ?? 'Unassigned'),
                subtitle: Text('Assignee'),
              ),
              ListTile(
                leading: Icon(Icons.event_outlined),
                title: Text(t.dueDate == null ? 'No due date' : DateFormat('EEE, d MMM yyyy').format(t.dueDate!)),
                subtitle: Text(due, style: TextStyle(color: dueColor)),
                trailing: _isManager ? Icon(Icons.edit_calendar_outlined) : null,
                onTap: _busy || !_isManager ? null : _pickDue,
              ),
              ListTile(
                leading: Icon(Icons.timer_outlined),
                title: Text('${t.estimateHours.toStringAsFixed(t.estimateHours % 1 == 0 ? 0 : 1)} hours estimated'),
              ),
            ]),
          ),
          SizedBox(height: 16),
          Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final s in taskStatuses)
                ButtonSegment(value: s, label: Text(statusLabels[s]!, style: TextStyle(fontSize: 12))),
            ],
            selected: {t.status},
            onSelectionChanged: _busy || !_canUpdate ? null : (v) => _update({'status': v.first}, 'Moved to ${statusLabels[v.first]}'),
          ),
          SizedBox(height: 20),
          Row(children: [
            Text('Progress', style: TextStyle(fontWeight: FontWeight.w700)),
            Spacer(),
            Text('${progress.round()}%'),
          ]),
          Slider(
            value: progress,
            max: 100,
            divisions: 20,
            label: '${progress.round()}%',
            onChanged: t.isDone || _busy || !_canUpdate ? null : (v) => setState(() => _progressDraft = v),
            onChangeEnd: (v) {
              final changes = <String, dynamic>{'progress': v.round()};
              if (v > 0 && t.status == 'todo') changes['status'] = 'in_progress';
              _update(changes, 'Progress saved');
            },
          ),
          SizedBox(height: 12),
          Row(children: [
            Text('Photo proof', style: TextStyle(fontWeight: FontWeight.w700)),
            Spacer(),
            IconButton.filledTonal(
              tooltip: 'Take photo',
              onPressed: _busy || !_canUpdate ? null : () => _attach(ImageSource.camera),
              icon: Icon(Icons.photo_camera_outlined),
            ),
            SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Choose from gallery',
              onPressed: _busy || !_canUpdate ? null : () => _attach(ImageSource.gallery),
              icon: Icon(Icons.photo_library_outlined),
            ),
          ]),
          SizedBox(height: 8),
          if (t.attachments.isEmpty)
            Text('No attachments yet. Snap a photo of finished work.', style: TextStyle(color: scheme.outline))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in t.attachments)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: a.isImage
                      ? Image.network(
                          session.api.fileUrl('/api/tasks/${widget.taskId}/attachments/${a.id}'),
                          headers: {'Authorization': 'Bearer ${session.api.token}'},
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(width: 96, height: 96, color: scheme.surfaceContainerHighest, child: Icon(Icons.broken_image_outlined)),
                        )
                      : Container(
                          width: 96,
                          height: 96,
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.picture_as_pdf_outlined),
                        ),
                ),
            ]),
          SizedBox(height: 24),
          if (!t.isDone)
            FilledButton.icon(
              onPressed: _busy || !_canUpdate ? null : () => _update({'status': 'done'}, 'Task completed 🎉'),
              icon: Icon(Icons.check),
              label: Text('Mark as done'),
              style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
            ),
        ]),
      ),
    );
  }
}
