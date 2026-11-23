import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/session.dart';

class NewTaskSheet extends StatefulWidget {
  final Team team;
  final List<Project> projects;
  final String? defaultProject;
  const NewTaskSheet({super.key, required this.team, required this.projects, this.defaultProject});
  @override
  State<NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends State<NewTaskSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _estimate = TextEditingController(text: '2');
  late String _project = widget.defaultProject ?? widget.projects.first.id;
  late String? _assignee = session.user?.id;
  String _priority = 'medium';
  DateTime? _due;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.api.post('/teams/${widget.team.id}/tasks', {
        'title': _title.text.trim(),
        'project': _project,
        'assignee': _assignee,
        'priority': _priority,
        'estimateHours': double.tryParse(_estimate.text) ?? 2,
        'dueDate': _due == null ? null : DateTime(_due!.year, _due!.month, _due!.day, 23, 59).toUtc().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Members can only create tasks for themselves; managers can assign anyone.
    final people = widget.team.members.where((m) => widget.team.isManager || m.user.id == session.user?.id).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('New task', style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 16),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            TextFormField(
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(labelText: 'What needs to be done?'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a title' : null,
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _project,
              decoration: InputDecoration(labelText: 'Project'),
              items: [for (final p in widget.projects) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => _project = v!),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _assignee,
              decoration: InputDecoration(labelText: 'Assignee'),
              items: [
                if (widget.team.isManager) DropdownMenuItem(value: null, child: Text('Unassigned')),
                for (final m in people) DropdownMenuItem(value: m.user.id, child: Text(m.user.name)),
              ],
              onChanged: (v) => setState(() => _assignee = v),
            ),
            SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: InputDecoration(labelText: 'Priority'),
                  items: [for (final p in taskPriorities) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: (v) => setState(() => _priority = v!),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _estimate,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Estimate (h)'),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n == null || n < 0.25 || n > 200 ? '0.25–200' : null;
                  },
                ),
              ),
            ]),
            SizedBox(height: 12),
            OutlinedButton.icon(
              icon: Icon(Icons.event),
              label: Text(_due == null ? 'Set due date' : 'Due ${DateFormat('EEE, d MMM').format(_due!)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(Duration(days: 1)),
                  lastDate: DateTime.now().add(Duration(days: 730)),
                );
                if (d != null) setState(() => _due = d);
              },
            ),
            SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              child: Text(_busy ? 'Saving…' : 'Create task'),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _estimate.dispose();
    super.dispose();
  }
}
