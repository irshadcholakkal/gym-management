import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync/workspace_repository.dart';
import '../data/receipt_design_repository.dart';
import 'receipt_preview.dart';

class ReceiptDesignCard extends StatelessWidget {
  const ReceiptDesignCard({super.key, this.invoice = false});
  final bool invoice;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(invoice ? 'Invoice design' : 'Receipt design',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
                'Customize the HTML and CSS used for ${invoice ? 'invoice' : 'receipt'} viewing and printing in the web app.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
                icon: const Icon(Icons.code),
                label:
                    Text(invoice ? 'Edit invoice HTML' : 'Edit receipt HTML'),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ReceiptDesignEditor(
                              repository: ReceiptDesignRepository(
                                  context.read<SupabaseClient>(),
                                  context
                                      .read<WorkspaceRepository>()
                                      .access
                                      .gymId,
                                  isInvoice: invoice),
                              gymName: context
                                  .read<WorkspaceRepository>()
                                  .access
                                  .gymName,
                            )))),
          ])));
}

class ReceiptDesignEditor extends StatefulWidget {
  const ReceiptDesignEditor(
      {super.key, required this.repository, required this.gymName});
  final ReceiptDesignRepository repository;
  final String gymName;
  @override
  State<ReceiptDesignEditor> createState() => _ReceiptDesignEditorState();
}

class _ReceiptDesignEditorState extends State<ReceiptDesignEditor> {
  String get name => widget.repository.documentName;
  final controller = TextEditingController();
  bool loading = true, busy = false, dirty = false;
  int version = 0;
  String? message;
  String saved = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final design = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        controller.text = design.html;
        saved = design.html;
        version = design.version;
        loading = false;
        dirty = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          message =
              'Could not load the ${name.toLowerCase()} design. Reconnect and try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> preview() async {
    final error = widget.repository.validate(controller.text);
    if (error != null) {
      setState(() => message = error);
      return;
    }
    final supported = await previewReceiptHtml(
        widget.repository.preview(controller.text, widget.gymName),
        '$name design preview');
    if (!supported && mounted) {
      setState(() => message =
          'Open GymPro in your web browser to preview and print the HTML design.');
    }
  }

  Future<void> save() async {
    final error = widget.repository.validate(controller.text);
    if (error != null) {
      setState(() => message = error);
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final design = await widget.repository.save(controller.text, version);
      if (mounted) {
        setState(() {
          version = design.version;
          saved = design.html;
          dirty = controller.text != saved;
          message = '$name design saved for your gym.';
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => message = error.code == '40001'
            ? 'Another administrator changed this design. Copy your edits, then reopen the editor to load the latest version.'
            : ['42P01', 'PGRST202', 'PGRST205'].contains(error.code)
                ? '$name design storage is not available yet. Ask the app administrator to apply the latest database update.'
                : 'Could not save the design. Check your connection and administrator access.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => message =
            'Could not save the ${name.toLowerCase()} design. Reconnect and try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirmExit() async {
    if (!dirty) return true;
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    actionsOverflowButtonSpacing: 8,
                    title: const Text('Discard unsaved changes?'),
                    content:
                        const Text('Your saved design will stay unchanged.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Keep editing')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Discard'))
                    ])) ??
        false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !dirty && !busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !busy && await confirmExit() && context.mounted) {
          setState(() => dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
          appBar: AppBar(title: Text('$name HTML design')),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              FilledButton.icon(
                                  onPressed: busy ? null : save,
                                  icon: const Icon(Icons.save_outlined),
                                  label:
                                      Text(busy ? 'Saving...' : 'Save design')),
                              OutlinedButton.icon(
                                  onPressed: busy ? null : preview,
                                  icon: const Icon(Icons.preview_outlined),
                                  label: const Text('Preview')),
                              TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => setState(() {
                                            controller.text =
                                                widget.repository.defaultDesign;
                                            dirty = controller.text != saved;
                                            message = null;
                                          }),
                                  child: const Text('Restore default')),
                            ]),
                            if (message != null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(message!)),
                            ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text('$name placeholders'),
                                children: [
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: SizedBox(
                                          height: 100,
                                          child: SingleChildScrollView(
                                              child: SelectableText(widget
                                                  .repository.placeholders
                                                  .map((key) => '{{$key}}')
                                                  .join('  ')))))
                                ]),
                            const SizedBox(height: 8),
                            Expanded(
                                child: TextField(
                                    controller: controller,
                                    enabled: !busy,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    keyboardType: TextInputType.multiline,
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 13),
                                    decoration: const InputDecoration(
                                        labelText: 'HTML / CSS',
                                        alignLabelWithHint: true),
                                    onChanged: (value) {
                                      final changed = value != saved;
                                      if (changed != dirty) {
                                        setState(() => dirty = changed);
                                      }
                                    })),
                            const SizedBox(height: 8),
                            Text(
                                dirty
                                    ? 'Unsaved changes'
                                    : version == 0
                                        ? 'Default design (not saved)'
                                        : 'Saved design',
                                style: Theme.of(context).textTheme.bodySmall),
                          ])))));
}
