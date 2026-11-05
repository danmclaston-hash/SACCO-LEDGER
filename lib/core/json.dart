typedef Json = Map<String, dynamic>;

extension JsonRead on Json {
  int i(String k) {
    final v = this[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  String s(String k) => this[k]?.toString() ?? '';
  String? n(String k) => this[k]?.toString();
  bool b(String k) => this[k] == true;
  List<Json> l(String k) => asJsonList(this[k]);
  Json m(String k) => this[k] is Map ? Map<String, dynamic>.from(this[k] as Map) : <String, dynamic>{};
}

List<Json> asJsonList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Json asJson(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
