class MembershipStatus {
  MembershipStatus(this.data, {DateTime? now}) {
    final dubai = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 4));
    today = DateTime.utc(dubai.year, dubai.month, dubai.day);
  }
  final Map data;
  late final DateTime today;
  DateTime? date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  DateTime? get end => date(data['end_exclusive']);
  int? get days => end?.difference(today).inDays;
  String get status {
    final raw = data['status']?.toString() ?? 'draft';
    if (raw != 'active') return raw;
    if (days != null && days! <= 0) return 'expired';
    if (days != null && days! <= 7) return 'expiring_soon';
    return raw;
  }

  String get countdown {
    if (status == 'paused') {
      return 'Countdown paused · expiry recalculates on resume';
    }
    if (status == 'cancelled' ||
        status == 'draft' ||
        status == 'pending_activation') {
      return '';
    }
    if (status == 'scheduled_renewal') {
      final start = date(data['start_date']);
      if (start != null && start.isAfter(today)) {
        return 'Starts in ${start.difference(today).inDays} days';
      }
      return 'Awaiting activation';
    }
    final remaining = days;
    if (remaining == null) return 'Expiry date unavailable';
    if (remaining <= 0) {
      return remaining == 0
          ? 'Expired today'
          : 'Expired ${-remaining} days ago';
    }
    return remaining == 1 ? 'Last day today' : '$remaining days remaining';
  }
}

String? whatsappPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[\s()+.\-]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  // Local UAE mobile numbers; international numbers keep their country code.
  if (RegExp(r'^05\d{8}$').hasMatch(digits)) {
    digits = '971${digits.substring(1)}';
  }
  if (!RegExp(r'^[1-9]\d{7,14}$').hasMatch(digits)) return null;
  return digits;
}
