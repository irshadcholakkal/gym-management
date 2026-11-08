import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync/workspace_repository.dart';
import '../data/reports_repository.dart';
import '../domain/period_report.dart';
import '../domain/report_exports.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.repository});
  final ReportsRepository? repository;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController year;
  late int month;
  bool yearly = false, busy = false;
  PeriodReport? report;
  String? error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 4));
    year = TextEditingController(text: '${now.year}');
    month = now.month;
  }

  @override
  void dispose() {
    year.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    if (!form.currentState!.validate()) return;
    final access = context.read<WorkspaceRepository>().access;
    if (!access.finances) return;
    final repository = widget.repository ??
        ReportsRepository(context.read<SupabaseClient>(), access.gymId);
    setState(() {
      busy = true;
      error = null;
      report = null;
    });
    try {
      final result = await repository.generate(
          int.parse(year.text.trim()), yearly ? null : month);
      if (mounted) setState(() => report = result);
    } catch (exception) {
      if (mounted) {
        setState(() => error = exception is PostgrestException &&
                exception.code == 'PGRST202'
            ? 'Reports are not enabled on the server yet. Ask your administrator to enable reports.'
            : 'Unable to generate this report. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export(String format) async {
    final selected = report;
    if (selected == null ||
        !context.read<WorkspaceRepository>().access.finances) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final latin = format == 'pdf'
          ? (await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
              .buffer
              .asUint8List()
          : null;
      final arabic = format == 'pdf'
          ? (await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'))
              .buffer
              .asUint8List()
          : null;
      final bytes =
          await compute(encodeReport, (selected.data, format, latin, arabic));
      final result = await FileSaver.instance.saveAs(
        name: selected.filename,
        bytes: bytes,
        fileExtension: format,
        mimeType: switch (format) {
          'pdf' => MimeType.pdf,
          'xlsx' => MimeType.microsoftExcel,
          _ => MimeType.csv
        },
      );
      if (mounted && result != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Report exported.')));
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => error = 'Unable to export the report. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!context.read<WorkspaceRepository>().access.finances) {
      return const Center(
          child: Text('You do not have permission to view financial reports.'));
    }
    final current = report;
    return ListView(children: [
      Text('Monthly & yearly reports',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
          'Choose a period and generate a full report, then download PDF, Excel or CSV. Sync pending changes first.'),
      const SizedBox(height: 16),
      Form(
          key: form,
          child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Monthly')),
                    ButtonSegment(value: true, label: Text('Yearly'))
                  ],
                  selected: {yearly},
                  onSelectionChanged: busy
                      ? null
                      : (value) => setState(() {
                            yearly = value.first;
                            report = null;
                          }),
                ),
                SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: year,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Year'),
                      onChanged: (_) => setState(() => report = null),
                      validator: (value) {
                        final parsed = int.tryParse(value?.trim() ?? '');
                        return parsed == null || parsed < 1900 || parsed > 9998
                            ? '1900–9998'
                            : null;
                      },
                    )),
                if (!yearly)
                  SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: month,
                        decoration: const InputDecoration(labelText: 'Month'),
                        items: [
                          for (var i = 1; i <= 12; i++)
                            DropdownMenuItem(
                                value: i,
                                child: Text(DateFormat.MMMM()
                                    .format(DateTime(2000, i))))
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                  month = value!;
                                  report = null;
                                }),
                      )),
                FilledButton.icon(
                    onPressed: busy ? null : generate,
                    icon: const Icon(Icons.assessment_outlined),
                    label: const Text('Generate report')),
              ])),
      if (busy)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator()),
      if (error != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (current != null) ...[
        const SizedBox(height: 20),
        Text('${current.gym} · ${current.label}',
            style: Theme.of(context).textTheme.titleMedium),
        Text('Generated ${current.generatedAt} (${current.timezone})'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final item in [
            ('pdf', 'Download PDF', Icons.picture_as_pdf_outlined),
            ('xlsx', 'Export Excel', Icons.table_chart_outlined),
            ('csv', 'Export CSV', Icons.download_outlined)
          ])
            OutlinedButton.icon(
                onPressed: busy ? null : () => export(item.$1),
                icon: Icon(item.$3),
                label: Text(item.$2)),
        ]),
        const SizedBox(height: 12),
        const Text(PeriodReport.notes),
        const SizedBox(height: 16),
        for (final totals in current.totals)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${totals['currency']} totals',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        Wrap(spacing: 28, runSpacing: 16, children: [
                          for (final metric in [
                            ('Billed', 'billed'),
                            ('Discounts', 'discount'),
                            ('Tax', 'tax'),
                            ('Gross collections', 'collections'),
                            ('Reversals', 'reversals'),
                            ('Net collections', 'net'),
                            ('Current balance on period invoices', 'balance')
                          ])
                            SizedBox(
                                width: 190,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(metric.$1),
                                      Text(
                                          '${totals['currency']} ${ReportExports.display(totals[metric.$2]!)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium)
                                    ])),
                        ]),
                      ]))),
        const SizedBox(height: 12),
        for (final table
            in current.tables.where((table) => table.name != 'Totals'))
          Card(
              child: ExpansionTile(
            title: Text(table.name),
            subtitle: Text('${table.rows.length} rows'),
            children: [
              if (table.rows.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No records for this period.'))
              else
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: table.columns
                          .map((c) => DataColumn(label: Text(c.label)))
                          .toList(),
                      rows: table.rows
                          .take(50)
                          .map((row) => DataRow(
                              cells: table.columns
                                  .map((c) => DataCell(SizedBox(
                                      width:
                                          table.name == 'Overview' ? 260 : 140,
                                      child: Text(
                                          ReportExports.display(
                                              table.value(row, c)),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis))))
                                  .toList()))
                          .toList(),
                    )),
              if (table.rows.length > 50)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'Preview shows the first 50 rows. Exports include every row.')),
            ],
          )),
      ] else if (!busy)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('Your report will appear here after generation.')),
      const SizedBox(height: 24),
    ]);
  }
}
