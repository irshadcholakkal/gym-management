/// Preserve the server-assigned number; never truncate or invent an offline ID.
String memberId(Object? number) {
  final value = int.tryParse(number?.toString() ?? '');
  return value == null || value <= 0 ? '' : value.toString().padLeft(4, '0');
}

String memberNameWithId(Map data, {String fallback = 'Member unavailable'}) {
  final name = data['full_name']?.toString() ??
      data['member_name']?.toString() ??
      fallback;
  final id = memberId(data['member_number']);
  return id.isEmpty ? name : '$name · ID $id';
}
