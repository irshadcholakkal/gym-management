import 'package:flutter/material.dart';

import 'install_client.dart';

class InstallAppCard extends StatefulWidget {
  const InstallAppCard({super.key});
  @override
  State<InstallAppCard> createState() => _InstallAppCardState();
}

class _InstallAppCardState extends State<InstallAppCard> {
  bool busy = false, checking = false, updateReady = false;
  String? updateMessage;
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
          'Web app installation requested. Complete the browser confirmation, then open GymPro from your device app launcher. It opens in its own app window.',
        'ios' =>
          'Open GymPro in Safari. Tap Share, choose Add to Home Screen, then tap Add. If shown, keep Open as Web App enabled.',
        'android' =>
          'Open GymPro in Chrome. Open the browser menu, choose Install and create shortcut, then choose Install. On older versions, choose Install app.',
        'mac' =>
          'In Safari, choose File → Add to Dock. In Chrome or Edge, use the install icon in the address bar or the browser menu’s Install app option.',
        _ =>
          'In Chrome or Edge, use the install icon in the address bar, or open the browser menu and choose Install GymPro / Install this site as an app. If unavailable, try a supported browser outside private browsing.',
      };
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actionsOverflowButtonSpacing: 8,
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

  Future<void> updateApp() async {
    setState(() {
      checking = true;
      updateMessage = null;
    });
    try {
      final result = await checkAppUpdate(apply: updateReady);
      if (!mounted) return;
      setState(() {
        updateReady = result == 'ready';
        updateMessage = switch (result) {
          'ready' =>
            'An update is ready. Save any open work before installing it.',
          'applying' => 'Installing update. GymPro will reload shortly.',
          'current' => 'GymPro is up to date.',
          'checking' => 'The update is still downloading. Check again shortly.',
          _ =>
            'Updates are unavailable here. Open GymPro in your browser and try again.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() => updateMessage =
            'Could not check for updates. Reconnect and try again.');
      }
    } finally {
      if (mounted) setState(() => checking = false);
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
            Text('App & updates',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(installed
                ? 'GymPro is installed on this device.'
                : 'Install GymPro as a standalone web app through your browser.'),
            const SizedBox(height: 10),
            const Text('Opens in its own app window.\n'
                'Supports cached data and some offline work. Saved changes sync when connected.\n'
                'Receives updates through App & updates.'),
            const SizedBox(height: 8),
            const Text(
                'Browser installation does not require you to download an APK or EXE file.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: installed || busy ? null : install,
              icon: Icon(installed
                  ? Icons.check_circle_outline
                  : Icons.install_mobile_rounded),
              label: Text(installed
                  ? 'Already installed'
                  : busy
                      ? 'Opening installer…'
                      : 'Install web app'),
            ),
            if (state != 'native') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: checking ? null : updateApp,
                icon: const Icon(Icons.system_update_alt),
                label: Text(checking
                    ? 'Checking...'
                    : updateReady
                        ? 'Install update & reload'
                        : 'Check for updates'),
              ),
              if (updateMessage != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(updateMessage!)),
            ],
          ],
        ),
      ),
    );
  }
}
