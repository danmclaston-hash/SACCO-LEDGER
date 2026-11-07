/// "Ann Namubiru" -> "AN", "ben" -> "B".
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  if (parts.length == 1) return first.toUpperCase();
  return (first + parts.last[0]).toUpperCase();
}
