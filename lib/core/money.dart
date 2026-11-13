import 'i18n.dart';

/// All money is a whole number in minor units. UGX, TZS, RWF have no cents. KES has 100 cents.
class Money {
  static int decimals(String currency) => currency == 'KES' ? 2 : 0;

  static String _commas(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// The number without the currency, as a person would type it: 10000 -> "10,000", KES 1050 -> "10.50".
  static String plain(int minor, [String currency = 'UGX']) {
    final sign = minor < 0 ? '-' : '';
    final a = minor.abs();
    if (decimals(currency) == 2) return '$sign${_commas(a ~/ 100)}.${(a % 100).toString().padLeft(2, '0')}';
    return '$sign${_commas(a)}';
  }

  static String format(int minor, [String currency = 'UGX']) => '$currency ${plain(minor, currency)}';

  /// "10,000" -> 10000 (UGX). "10.50" -> 1050 (KES). Returns null if not a valid amount.
  /// Zero is refused unless [allowZero], like an empty cash box.
  static int? parse(String text, [String currency = 'UGX', bool allowZero = false]) {
    final t = text.replaceAll(',', '').replaceAll(' ', '').trim();
    int? v;
    if (decimals(currency) == 0) {
      v = RegExp(r'^\d+$').hasMatch(t) ? int.parse(t) : null;
    } else if (RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) {
      final parts = t.split('.');
      v = int.parse(parts[0]) * 100 + int.parse(parts.length == 2 ? parts[1].padRight(2, '0') : '00');
    }
    if (v == null || v < 0 || (v == 0 && !allowZero)) return null;
    return v;
  }

  static String maskPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '-';
    if (phone.length < 8) return phone;
    return '${phone.substring(0, 6)} *** *${phone.substring(phone.length - 3)}';
  }

  static String maskNationalId(String? nin) {
    if (nin == null || nin.isEmpty) return '-';
    if (nin.length < 6) return nin;
    return '${nin.substring(0, 2)}*****${nin.substring(nin.length - 3)}';
  }
}

class Phones {
  /// Members sign in with phone + password, with no SMS cost. The login system needs an email,
  /// so a phone becomes a private address that no mail is ever sent to.
  static const _privateDomain = '@phone.saccoledger.app';

  /// 0772 123456 -> 256772123456. Same rule as the database.
  /// [dial] is the country code (256 Uganda, 254 Kenya, 255 Tanzania, 250 Rwanda).
  /// A number typed with its own country code (+254...) keeps it.
  static String? normalize(String? p, {String dial = '256'}) {
    if (p == null) return null;
    var d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return null;
    if (d.length == 10 && d.startsWith('0')) d = '$dial${d.substring(1)}';
    if (d.length == 9) d = '$dial$d';
    return d;
  }

  /// A normalized number of a sensible length. The database checks the same 11 to 13 digits.
  static bool isValidNumber(String? normalized) => normalized != null && normalized.length >= 11 && normalized.length <= 13;

  /// 256772123456 -> 0772123456, the way people write their own number. Other countries' numbers stay as they are.
  static String local(String? p, {String dial = '256'}) {
    final d = (p ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return d.startsWith(dial) && d.length == dial.length + 9 ? '0${d.substring(dial.length)}' : d;
  }

  static String loginEmail(String input, {String dial = '256'}) {
    final t = input.trim().toLowerCase();
    if (t.contains('@')) return t;
    return '${normalize(t, dial: dial) ?? t}$_privateDomain';
  }

  /// What a person signs in with, in their own words: "phone +256..." or their email.
  static String signInLabel(String loginId) =>
      loginId.endsWith(_privateDomain) ? 'phone +${loginId.substring(0, loginId.length - _privateDomain.length)}' : loginId;

  static bool looksValid(String input, {String dial = '256'}) {
    final t = input.trim();
    if (t.contains('@')) return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    return isValidNumber(normalize(t, dial: dial));
  }
}

class Dates {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static const _monthsLg = ['Jan', 'Feb', 'Mar', 'Apr', 'Mey', 'Jun', 'Jul', 'Agu', 'Seb', 'Oki', 'Nov', 'Des'];
  static const _monthsSw = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];

  /// Short month names follow the chosen language.
  static String monthShort(int month) => switch (Lang.current) {
        AppLanguage.lg => _monthsLg,
        AppLanguage.sw => _monthsSw,
        AppLanguage.en => _months,
      }[(month - 1).clamp(0, 11)];

  /// Today at midnight, so schedules start on a whole day.
  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// 2026-11-07, the way the database writes a day.
  static String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String day(dynamic v) {
    final d = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
    if (d == null) return '-';
    final l = d.toLocal();
    return '${l.day} ${monthShort(l.month)} ${l.year}';
  }

  static String dayTime(dynamic v) {
    final d = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
    if (d == null) return '-';
    final l = d.toLocal();
    return '${day(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
