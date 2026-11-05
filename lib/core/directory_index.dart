import 'database/database.dart';
import 'record_labels.dart';

/// Prepare once per data update, yielding to browser input between batches.
class DirectoryIndex {
  DirectoryIndex._(this.records, this.labels, this.search);
  final List<CachedRecord> records;
  final RecordLabels labels;
  final Map<String, String> search;

  static Future<DirectoryIndex> create(List<CachedRecord> records) async {
    final labels = RecordLabels.lazy(records);
    final titles = <String, String>{};
    final search = <String, String>{};
    String key(CachedRecord r) => '${r.kind}:${r.id}';
    for (var i = 0; i < records.length; i++) {
      if (i % 100 == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final r = records[i];
      final title = labels.title(r.kind, labels.lookup(r.kind, r.id));
      titles[key(r)] = title;
      search[key(r)] = '${r.payload}\n$title'.toLowerCase();
    }
    // Sort small runs and merge with yields instead of one blocking large sort.
    var runs = <List<CachedRecord>>[];
    int compare(CachedRecord a, CachedRecord b) =>
        titles[key(a)]!.compareTo(titles[key(b)]!);
    for (var start = 0; start < records.length; start += 100) {
      final end = (start + 100).clamp(0, records.length);
      runs.add(records.sublist(start, end)..sort(compare));
    }
    while (runs.length > 1) {
      final next = <List<CachedRecord>>[];
      for (var run = 0; run < runs.length; run += 2) {
        if (run + 1 == runs.length) {
          next.add(runs[run]);
          continue;
        }
        final left = runs[run], right = runs[run + 1];
        final merged = <CachedRecord>[];
        var a = 0, b = 0;
        while (a < left.length || b < right.length) {
          if (merged.length % 100 == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          merged.add(b == right.length ||
                  (a < left.length && compare(left[a], right[b]) <= 0)
              ? left[a++]
              : right[b++]);
        }
        next.add(merged);
      }
      runs = next;
    }
    return DirectoryIndex._(runs.isEmpty ? [] : runs.single, labels, search);
  }
}
