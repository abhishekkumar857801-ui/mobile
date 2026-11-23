import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'call_screen.dart';

class Meeting {
  final String id;
  final String title;
  final String agenda;
  final DateTime startsAt;
  final int durationMinutes;
  final String link;
  final String createdBy;

  Meeting.fromJson(Map<String, dynamic> j)
      : id = j['_id'].toString(),
        title = j['title'] ?? '',
        agenda = j['agenda'] ?? '',
        startsAt = DateTime.parse('${j['startsAt']}').toLocal(),
        durationMinutes = (j['durationMinutes'] ?? 30) as int,
        link = j['link'] ?? '',
        createdBy = j['createdBy'] is Map ? '${j['createdBy']['name'] ?? ''}' : '';

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));
  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(startsAt.subtract(Duration(minutes: 10))) && now.isBefore(endsAt);
  }
}

String _linkLabel(String url) {
  if (url.contains('meet.google.com')) return 'Join on Google Meet';
  if (url.contains('zoom.us')) return 'Join on Zoom';
  if (url.contains('teams.microsoft') || url.contains('teams.live')) return 'Join on Teams';
  return 'Open meeting link';
}

/// Meetings for one project: the live TeamFlow video call, scheduled meetings
/// (optionally with a Google Meet / Zoom link) and scheduling for managers.
class MeetingsScreen extends StatefulWidget {
  final Project project;
  final bool isManager;
  const MeetingsScreen({super.key, required this.project, required this.isManager});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  List<Meeting>? _upcoming;
  Map<String, dynamic>? _call;
  String? _error;
  bool _starting = false;
  StreamSubscription<LiveEvent>? _sub;

  String get _base => '/projects/${widget.project.id}/meetings';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = session.events.listen((e) {
      final data = e.data;
      if (data is! Map || data['projectId'] != widget.project.id || !mounted) return;
      if (e.name == 'call:updated' || e.name == 'call:started') {
        setState(() => _call = data['call'] is Map ? Map<String, dynamic>.from(data['call']) : null);
      } else if (e.name == 'call:ended') {
        setState(() => _call = null);
      } else if (e.name == 'meeting:changed') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await session.api.get(_base);
      if (!mounted) return;
      setState(() {
        _upcoming = (res['upcoming'] as List).map((m) => Meeting.fromJson(m)).toList();
        _call = res['call'] is Map ? Map<String, dynamic>.from(res['call']) : null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _joinCall() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(projectId: widget.project.id, projectName: widget.project.name, isManager: widget.isManager),
      ),
    );
    _load();
  }

  Future<void> _startCall() async {
    setState(() => _starting = true);
    final res = await session.emitAck('call:start', {'projectId': widget.project.id});
    if (!mounted) return;
    setState(() => _starting = false);
    if (res['ok'] == true) {
      _joinCall();
    } else {
      showSnack(context, '${res['error'] ?? 'Could not start the meeting'}');
    }
  }

  Future<void> _openLink(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, 'Could not open $url');
  }

  Future<void> _cancel(Meeting m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancel "${m.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Cancel meeting')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await session.api.delete('$_base/${m.id}');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _schedule() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScheduleSheet(base: _base),
    );
    if (created == true) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    return Scaffold(
      appBar: AppBar(title: Text('Meetings · ${widget.project.name}', overflow: TextOverflow.ellipsis)),
      floatingActionButton: widget.isManager
          ? FloatingActionButton.extended(onPressed: _schedule, icon: Icon(Icons.event), label: Text('Schedule'))
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          if (call != null)
            Card(
              color: Color(0xFFF4EDE0),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(children: [
                  Icon(Icons.circle, color: Color(0xFFFF6B5B), size: 12),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Live meeting in progress', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF14213D))),
                      Text(
                        'Started by ${call['startedBy']?['name'] ?? ''} · ${(call['participants'] as List?)?.length ?? 0} in the call',
                        style: TextStyle(fontSize: 12, color: Color(0xFF14213D)),
                      ),
                    ]),
                  ),
                  FilledButton.icon(onPressed: _joinCall, icon: Icon(Icons.videocam), label: Text('Join')),
                ]),
              ),
            )
          else if (widget.isManager)
            FilledButton.icon(
              onPressed: _starting ? null : _startCall,
              icon: Icon(Icons.videocam),
              label: Text(_starting ? 'Starting…' : 'Start a video meeting now'),
              style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 16)),
            )
          else
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
              child: Text(
                'No live meeting right now. The owner or a manager can start one, and you will get a notification.',
                style: TextStyle(color: AppColors.text2),
              ),
            ),
          SizedBox(height: 20),
          Text('UPCOMING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.6)),
          SizedBox(height: 8),
          if (_upcoming == null && _error == null) Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) EmptyState(icon: Icons.cloud_off, title: 'Could not load meetings', subtitle: _error),
          if (_upcoming != null && _upcoming!.isEmpty)
            EmptyState(icon: Icons.event_available_outlined, title: 'No meetings scheduled'),
          for (final m in _upcoming ?? <Meeting>[])
            Card(
              shape: m.isNow
                  ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Color(0xFFFF6B5B)))
                  : null,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 52,
                    padding: EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(6)),
                    child: Column(children: [
                      Text('${m.startsAt.day}', style: TextStyle(fontFamily: monoFont, fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
                      Text(DateFormat('MMM').format(m.startsAt).toUpperCase(),
                          style: TextStyle(fontFamily: monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.cream)),
                    ]),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(m.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                        if (m.isNow) ...[SizedBox(width: 6), Pill('now', AppColors.danger)],
                      ]),
                      SizedBox(height: 2),
                      Text(
                        '${DateFormat('EEE, h:mm a').format(m.startsAt)} – ${DateFormat('h:mm a').format(m.endsAt)} · by ${m.createdBy}',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      if (m.agenda.isNotEmpty) ...[SizedBox(height: 6), Text(m.agenda)],
                      SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        if (m.link.isNotEmpty)
                          FilledButton.tonalIcon(
                            onPressed: () => _openLink(m.link),
                            icon: Icon(Icons.open_in_new, size: 18),
                            label: Text(_linkLabel(m.link)),
                          )
                        else if (call != null)
                          FilledButton.tonalIcon(onPressed: _joinCall, icon: Icon(Icons.videocam, size: 18), label: Text('Join TeamFlow call'))
                        else if (widget.isManager)
                          FilledButton.tonalIcon(
                            onPressed: _starting ? null : _startCall,
                            icon: Icon(Icons.videocam, size: 18),
                            label: Text('Start TeamFlow call'),
                          )
                        else
                          Pill('TeamFlow video · opens when the host starts it', AppColors.muted),
                        if (widget.isManager)
                          TextButton(onPressed: () => _cancel(m), child: Text('Cancel', style: TextStyle(color: AppColors.danger))),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ScheduleSheet extends StatefulWidget {
  final String base;
  const _ScheduleSheet({required this.base});
  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _link = TextEditingController();
  final _agenda = TextEditingController();
  late DateTime _when;
  int _duration = 30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final soon = DateTime.now().add(Duration(minutes: 30));
    _when = DateTime(soon.year, soon.month, soon.day, soon.hour, soon.minute < 30 ? 30 : 0).add(Duration(hours: soon.minute < 30 ? 0 : 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _agenda.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(Duration(days: 1)),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.api.post(widget.base, {
        'title': _title.text.trim(),
        'startsAt': _when.toUtc().toIso8601String(),
        'durationMinutes': _duration,
        'link': _link.text.trim(),
        'agenda': _agenda.text.trim(),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Schedule a meeting', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(height: 14),
            if (_error != null) ...[Text(_error!, style: TextStyle(color: AppColors.danger)), SizedBox(height: 8)],
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: 'Title', hintText: 'e.g. Sprint review'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a title' : null,
            ),
            SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event),
              title: Text(DateFormat('EEE, d MMM yyyy · h:mm a').format(_when)),
              subtitle: Text('Tap to change date & time'),
              onTap: _pickDateTime,
            ),
            DropdownButtonFormField<int>(
              initialValue: _duration,
              decoration: InputDecoration(labelText: 'Duration'),
              items: [15, 30, 45, 60, 90, 120]
                  .map((m) => DropdownMenuItem(value: m, child: Text(m < 60 ? '$m min' : '${m ~/ 60} h${m % 60 == 0 ? '' : ' 30 min'}')))
                  .toList(),
              onChanged: (v) => setState(() => _duration = v ?? 30),
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Meeting link (optional)',
                hintText: 'https://meet.google.com/…',
                helperText: 'Leave empty to use TeamFlow video',
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || t.startsWith('https://') ? null : 'Link must start with https://';
              },
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _agenda,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: 'Agenda (optional)'),
            ),
            SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              child: Text(_busy ? 'Scheduling…' : 'Schedule & notify team'),
            ),
          ]),
        ),
      ),
    );
  }
}
