import 'package:flutter/material.dart';

import '../services/session.dart';
import '../widgets/common.dart';

/// Lets the user point the app at the API server, e.g. the laptop's
/// Wi-Fi address during the demo (http://192.168.x.x:4000) or a deployed URL.
Future<void> showServerDialog(BuildContext context) async {
  final ctrl = TextEditingController(text: session.api.baseUrl);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Server address'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.1.10:4000'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Emulator: http://10.0.2.2:4000\nPhone on same Wi-Fi: http://<laptop IP>:4000\nDeployed: https://your-api.onrender.com',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (saved == true) {
    final url = ctrl.text.trim();
    if (!url.startsWith('http')) {
      if (context.mounted) showSnack(context, 'Address must start with http:// or https://');
      return;
    }
    await session.setServerUrl(url);
    try {
      await session.api.get('/health');
      if (context.mounted) showSnack(context, 'Connected to server ✓');
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }
}
