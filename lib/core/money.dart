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

  static String format(int minor, [String currency = 'UGX']) {
    final sign = minor < 0 ? '-' : '';
    if (decimals(currency) == 2) {
      final a = minor.abs();
      return '$currency $sign${_commas(a ~/ 100)}.${(a % 100).toString().padLeft(2, '0')}';
    }
    return '$currency $sign${_commas(minor)}';
  }

  /// "10,000" -> 10000 (UGX). "10.50" -> 1050 (KES). Returns null if not a valid positive amount.
  static int? parse(String text, [String currency = 'UGX']) {
    final t = text.replaceAll(',', '').replaceAll(' ', '').trim();
    if (decimals(currency) == 0) {
      final v = int.tryParse(t);
      return (v == null || v <= 0) ? null : v;
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(t)) return null;
    final parts = t.split('.');
    final cents = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
    final v = int.parse(parts[0]) * 100 + int.parse(cents);
    return v <= 0 ? null : v;
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

  /// Members sign in with phone + password, with no SMS cost. The login system needs an email,
  /// so a phone becomes a private address that no mail is ever sent to.
  static String loginEmail(String input, {String dial = '256'}) {
    final t = input.trim().toLowerCase();
    if (t.contains('@')) return t;
    return '${normalize(t, dial: dial) ?? t}@phone.saccoledger.app';
  }

  static bool looksValid(String input, {String dial = '256'}) {
    final t = input.trim();
    if (t.contains('@')) return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    final n = normalize(t, dial: dial);
    return n != null && n.length >= 11 && n.length <= 13;
  }
}

class Dates {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String day(dynamic v) {
    final d = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
    if (d == null) return '-';
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  static String dayTime(dynamic v) {
    final d = v is DateTime ? v : DateTime.tryParse(v?.toString() ?? '');
    if (d == null) return '-';
    final l = d.toLocal();
    return '${day(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
