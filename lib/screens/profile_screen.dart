import 'package:flutter/material.dart';

import '../services/session.dart';
import '../widgets/common.dart';
import 'server_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    session.biometricsAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  Future<void> _editCapacity() async {
    double value = session.user!.weeklyCapacity;
    final saved = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Weekly capacity'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Hours per week you can give your teams. Used to detect overload.'),
            SizedBox(height: 12),
            Text('${value.round()} h / week', style: Theme.of(ctx).textTheme.titleLarge),
            Slider(value: value, min: 1, max: 60, divisions: 59, onChanged: (v) => setLocal(() => value = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, value), child: Text('Save')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    try {
      await session.updateProfile({'weeklyCapacity': saved.round()});
      if (mounted) showSnack(context, 'Capacity updated');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Profile')),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final u = session.user;
          if (u == null) return SizedBox.shrink();
          return ListView(children: [
            SizedBox(height: 16),
            Center(child: UserAvatar(u, radius: 40)),
            SizedBox(height: 12),
            Center(child: Text(u.name, style: Theme.of(context).textTheme.titleLarge)),
            Center(child: Text(u.email, style: TextStyle(color: Theme.of(context).colorScheme.outline))),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Weekly capacity'),
              subtitle: Text('${u.weeklyCapacity.round()} hours per week'),
              trailing: Icon(Icons.chevron_right),
              onTap: _editCapacity,
            ),
            SwitchListTile(
              secondary: Icon(Icons.fingerprint),
              title: Text('Biometric unlock'),
              subtitle: Text(_bioAvailable ? 'Ask for fingerprint / Face ID when opening the app' : 'Not available on this device'),
              value: session.biometricLock,
              onChanged: _bioAvailable
                  ? (v) async {
                      final ok = await session.setBiometricLock(v);
                      if (!ok && context.mounted) showSnack(context, 'Biometric check failed');
                    }
                  : null,
            ),
            ListTile(
              leading: Icon(Icons.dns_outlined),
              title: Text('Server address'),
              subtitle: Text(session.api.baseUrl),
              trailing: Icon(Icons.circle, size: 10, color: session.live ? AppColors.success : AppColors.muted),
              onTap: () => showServerDialog(context),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: AppColors.danger),
              title: Text('Sign out', style: TextStyle(color: AppColors.danger)),
              onTap: session.logout,
            ),
          ]);
        },
      ),
    );
  }
}
