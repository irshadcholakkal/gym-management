import 'package:flutter/material.dart';

import 'install_client.dart';

class InstallAppCard extends StatefulWidget {
  const InstallAppCard({super.key});
  @override
  State<InstallAppCard> createState() => _InstallAppCardState();
}

class _InstallAppCardState extends State<InstallAppCard> {
  bool busy = false;
  late String state = appInstallState();

  Future<void> install() async {
    setState(() => busy = true);
    try {
      final result = await installApp();
      if (!mounted) return;
      setState(() => state = appInstallState());
      if (result == 'installed' || result == 'dismissed') return;
      final message = switch (result) {
        'accepted' =>
          'Installation requested. Follow your browser’s instructions to finish, then open GymPro from your home screen or app launcher.',
        'ios' =>
          'Open GymPro in Safari. Tap Share, choose Add to Home Screen, then tap Add. If shown, keep Open as Web App enabled.',
        'android' =>
          'Open your browser menu and choose Install app or Add to Home screen. If the option is missing, open GymPro in Chrome and try again.',
        'mac' =>
          'In Safari, choose File → Add to Dock. In Chrome or Edge, use the install icon in the address bar or the browser menu’s Install app option.',
        _ =>
          'In Chrome or Edge, use the install icon in the address bar, or open the browser menu and choose Install GymPro / Install this site as an app. If unavailable, try a supported browser outside private browsing.',
      };
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result == 'accepted'
              ? 'Finish installing GymPro'
              : 'Install GymPro'),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'))
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not open installation. Try the Install app option in your browser menu.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = state == 'installed' || state == 'native';
    return Card(
      child: Padding(
        padding:
            EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.install_mobile_rounded, size: 22),
            const SizedBox(height: 12),
            Text('GymPro on your device',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(installed
                ? 'You’re already using GymPro as an app.'
                : 'Add GymPro to your home screen or desktop for quick access in its own app window.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: installed || busy ? null : install,
              icon: Icon(installed
                  ? Icons.check_circle_outline
                  : Icons.download_rounded),
              label: Text(installed
                  ? 'Already installed'
                  : busy
                      ? 'Opening installer…'
                      : 'Install app'),
            ),
          ],
        ),
      ),
    );
  }
}
