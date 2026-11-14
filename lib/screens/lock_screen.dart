import 'package:flutter/material.dart';

import '../services/session.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => session.unlock());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.fingerprint, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('TeamFlow is locked', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Hi ${session.user?.name ?? ''}, unlock to continue'),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: session.unlock, icon: const Icon(Icons.lock_open), label: const Text('Unlock')),
          TextButton(onPressed: session.logout, child: const Text('Sign in with password instead')),
        ]),
      ),
    );
  }
}
