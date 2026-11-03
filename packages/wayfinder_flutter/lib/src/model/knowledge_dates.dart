const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// [instant] as a local date: `26 Aug 2026`.
String knowledgeDate(DateTime instant) {
  final local = instant.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// [instant] as a local date and time: `26 Aug 2026, 16:48`.
String knowledgeDateTime(DateTime instant) {
  final local = instant.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${knowledgeDate(local)}, ${two(local.hour)}:${two(local.minute)}';
}
