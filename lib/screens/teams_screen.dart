import 'package:flutter/material.dart';

import '../models.dart';
import '../services/session.dart';
import '../widgets/common.dart';
import 'team_screen.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});
  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  List<Team>? _teams;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await session.api.get('/teams');
      if (mounted) {
        setState(() {
          _teams = (res['teams'] as List).map((t) => Team.fromJson(t)).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _joinOrCreate({required bool create}) async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(create ? 'Create a team' : 'Join a team'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          textCapitalization: create ? TextCapitalization.words : TextCapitalization.characters,
          maxLength: create ? 80 : 6,
          decoration: InputDecoration(labelText: create ? 'Team name' : 'Invite code (e.g. BIN7K2)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(create ? 'Create' : 'Join')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = create
          ? await session.api.post('/teams', {'name': nameCtrl.text.trim()})
          : await session.api.post('/teams/join', {'joinCode': nameCtrl.text.trim().toUpperCase()});
      final team = Team.fromJson(res['team']);
      session.subscribeTeam(team.id);
      await _load();
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(team: team)));
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final teams = _teams;
    return Scaffold(
      appBar: AppBar(title: Text('Teams'), actions: [
        IconButton(tooltip: 'Join with code', icon: Icon(Icons.qr_code_2), onPressed: () => _joinOrCreate(create: false)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _joinOrCreate(create: true),
        icon: Icon(Icons.add),
        label: Text('New team'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: teams == null
            ? ListView(children: [
                SizedBox(height: 120),
                _error != null
                    ? EmptyState(icon: Icons.cloud_off, title: 'Could not load teams', subtitle: _error)
                    : Center(child: CircularProgressIndicator()),
              ])
            : teams.isEmpty
                ? ListView(children: [
                    SizedBox(height: 80),
                    EmptyState(icon: Icons.groups_outlined, title: 'No teams yet', subtitle: 'Create a team or join one with a code from your manager.'),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: () => _joinOrCreate(create: false),
                        icon: Icon(Icons.login),
                        label: Text('Join with code'),
                      ),
                    ),
                  ])
                : ListView(
                    padding: EdgeInsets.only(bottom: 96),
                    children: [
                      for (final t in teams)
                        Card(
                          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(t.name, style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Row(children: [
                                for (final m in t.members.take(5))
                                  Padding(padding: EdgeInsets.only(right: 4), child: UserAvatar(m.user, radius: 12)),
                                SizedBox(width: 4),
                                Text('${t.members.length} members'),
                              ]),
                            ),
                            trailing: Pill(t.myRole, Theme.of(context).colorScheme.primary),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(team: t)));
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
