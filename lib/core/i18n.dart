import 'i18n_table.dart';

enum AppLanguage {
  en('English'),
  lg('Oluganda'),
  sw('Kiswahili');

  final String label;
  const AppLanguage(this.label);
}

/// The language the whole app is showing right now. Set by the app state; read by every piece of text.
class Lang {
  static AppLanguage current = AppLanguage.en;
}

final Map<AppLanguage, Map<String, String>> _cache = {AppLanguage.lg: {}, AppLanguage.sw: {}};
List<(RegExp, String, int)>? _patterns;

/// Sentences with a changing part, like "Meeting #{0} is open now". Built once, the first time they are needed.
List<(RegExp, String, int)> _loadPatterns() {
  final out = <(RegExp, String, int)>[];
  for (final e in i18nTable.entries) {
    if (!e.key.contains('{0')) continue;
    var n = 0;
    // {0} matches any words; {0#} matches only a number, so "{0#} members" never swallows a whole sentence.
    final re = RegExp.escape(e.key).replaceAllMapped(RegExp(r'\\\{(\d)(#?)\\\}|\{(\d)(#?)\}'), (m) {
      n++;
      return (m.group(2) ?? m.group(4)) == '#' ? r'(\d[\d,.]*)' : '(.+?)';
    });
    out.add((RegExp('^$re\$', dotAll: true), e.key, n));
  }
  // Longer, more exact sentences first, so "{0} payments to check" wins over "{0}".
  out.sort((a, b) => b.$2.length.compareTo(a.$2.length));
  return out;
}

/// Turns English text into the chosen language. Text it does not know stays in English, so nothing ever goes blank.
String translate(String english, [AppLanguage? lang]) {
  final l = lang ?? Lang.current;
  if (l == AppLanguage.en || english.trim().isEmpty) return english;
  final cache = _cache[l]!;
  final hit = cache[english];
  if (hit != null) return hit;
  final out = _lookup(english, l);
  if (cache.length < 5000) cache[english] = out;
  return out;
}

String _lookup(String english, AppLanguage l) {
  final i = l == AppLanguage.lg ? 0 : 1;
  final exact = i18nTable[english];
  if (exact != null) return exact[i];
  // Keep spaces and full stops around the words as they were.
  final trimmed = english.trim();
  if (trimmed != english) {
    final t = i18nTable[trimmed];
    if (t != null) return english.replaceFirst(trimmed, t[i]);
  }
  _patterns ??= _loadPatterns();
  for (final (re, key, n) in _patterns!) {
    final m = re.firstMatch(english);
    if (m == null) continue;
    var out = i18nTable[key]![i];
    for (var k = 0; k < n; k++) {
      // The changing parts may themselves be words we know, like "3 payments".
      out = out.replaceAll('{$k}', translate(m.group(k + 1)!, l));
    }
    return out;
  }
  // Text made of lines: translate each line on its own.
  if (english.contains('\n')) {
    final lines = english.split('\n');
    if (lines.length > 1) return lines.map((x) => translate(x, l)).join('\n');
  }
  return english;
}

/// Every English text the app shows that has no translation yet, for the coverage check.
bool hasTranslation(String english) => i18nTable.containsKey(english);
