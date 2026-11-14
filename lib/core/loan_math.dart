/// Loan maths on the phone. Exactly the same rules as the database (calc_schedule2 and late_fee_for),
/// so the calculator shows what the group's books will really say. Whole money units, rounded down.
library;

class LoanTerms {
  /// none | once | monthly | yearly
  final String interestMode;

  /// Percent, up to 2 decimals (2.5 means 2.5%).
  final double rate;

  /// flat | reducing_balance (monthly and yearly only)
  final String calculation;

  /// First months with no interest (monthly and yearly only).
  final int freeMonths;

  /// monthly | end
  final String plan;

  /// none | fixed | percent
  final String lateType;
  final int lateAmount; // fixed fee, in money units
  final double latePct; // % of the missed payment
  /// once | day | week | month
  final String lateEvery;
  final int graceDays;

  /// Late fees never pass this % of the loan. Null = no limit.
  final double? capPct;

  const LoanTerms({
    this.interestMode = 'yearly',
    this.rate = 10,
    this.calculation = 'flat',
    this.freeMonths = 0,
    this.plan = 'monthly',
    this.lateType = 'none',
    this.lateAmount = 0,
    this.latePct = 0,
    this.lateEvery = 'once',
    this.graceDays = 0,
    this.capPct,
  });

  static double _d(dynamic v, double or) => v == null ? or : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? or);
  static int _i(dynamic v, int or) => v == null ? or : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? or);

  /// The database names the interest columns differently on a group and on a loan, and keeps an older
  /// whole-number rate column beside the new one. Late-fee columns have the same names on both.
  factory LoanTerms._read(Map<String, dynamic> j,
          {required String mode,
          required String rate,
          required String oldRate,
          required String calc,
          required String free,
          required String plan,
          required double defaultRate}) =>
      LoanTerms(
        interestMode: j[mode]?.toString() ?? 'yearly',
        rate: _d(j[rate] ?? j[oldRate], defaultRate),
        calculation: j[calc]?.toString() ?? 'flat',
        freeMonths: _i(j[free], 0),
        plan: j[plan]?.toString() ?? 'monthly',
        lateType: j['late_fee_type']?.toString() ?? 'none',
        lateAmount: _i(j['late_fee_amount'], 0),
        latePct: _d(j['late_fee_pct'], 0),
        lateEvery: j['late_fee_every']?.toString() ?? 'once',
        graceDays: _i(j['late_fee_grace_days'], 0),
        capPct: j['late_fee_cap_pct'] == null ? null : _d(j['late_fee_cap_pct'], 0),
      );

  /// The group's rules (organizations row).
  factory LoanTerms.fromGroup(Map<String, dynamic> o) => LoanTerms._read(o,
      mode: 'loan_interest_mode',
      rate: 'loan_interest_rate',
      oldRate: 'default_interest_rate_pct',
      calc: 'loan_calculation',
      free: 'loan_free_months',
      plan: 'loan_repayment_plan',
      defaultRate: 10);

  /// One loan's own rules.
  factory LoanTerms.fromLoan(Map<String, dynamic> l) => LoanTerms._read(l,
      mode: 'interest_mode',
      rate: 'interest_rate',
      oldRate: 'interest_rate_pct',
      calc: 'calculation_type',
      free: 'free_months',
      plan: 'repayment_plan',
      defaultRate: 0);

  Map<String, dynamic> toJson() => {
        'interest_mode': interestMode,
        'interest_rate': rate,
        'calculation': calculation,
        'free_months': freeMonths,
        'repayment_plan': plan,
        'late_fee_type': lateType,
        'late_fee_amount': lateAmount,
        'late_fee_pct': latePct,
        'late_fee_every': lateEvery,
        'late_fee_grace_days': graceDays,
        'late_fee_cap_pct': capPct,
      };

  LoanTerms copyWith({
    String? interestMode,
    double? rate,
    String? calculation,
    int? freeMonths,
    String? plan,
    String? lateType,
    int? lateAmount,
    double? latePct,
    String? lateEvery,
    int? graceDays,
    double? capPct,
    bool clearCap = false,
  }) =>
      LoanTerms(
        interestMode: interestMode ?? this.interestMode,
        rate: rate ?? this.rate,
        calculation: calculation ?? this.calculation,
        freeMonths: freeMonths ?? this.freeMonths,
        plan: plan ?? this.plan,
        lateType: lateType ?? this.lateType,
        lateAmount: lateAmount ?? this.lateAmount,
        latePct: latePct ?? this.latePct,
        lateEvery: lateEvery ?? this.lateEvery,
        graceDays: graceDays ?? this.graceDays,
        capPct: clearCap ? null : (capPct ?? this.capPct),
      );

  bool get hasInterest => interestMode != 'none' && rate > 0;
  bool get timeBased => interestMode == 'monthly' || interestMode == 'yearly';
}

class Installment {
  final int n;
  final DateTime due;
  final int principal;
  final int interest;
  final int total;
  final int left;
  const Installment(this.n, this.due, this.principal, this.interest, this.total, this.left);
}

/// Same as Postgres: Jan 31 + 1 month = Feb 28 (or 29).
DateTime addMonths(DateTime d, int m) {
  final y = d.year + ((d.month - 1 + m) ~/ 12);
  final mo = (d.month - 1 + m) % 12 + 1;
  final last = DateTime(y, mo + 1, 0).day;
  return DateTime(y, mo, d.day > last ? last : d.day);
}

// Rates are kept as hundredths of a percent (2.5% -> 250) so the maths is exact, like the database.
// Amounts are never negative, so ~/ rounds down, like the database.
int _rateH(double r) => (r * 100).round();

List<Installment> loanSchedule(int principal, int term, LoanTerms t, DateTime start) {
  if (principal <= 0 || term < 1) return const [];
  final rh = _rateH(t.rate);
  final d = t.interestMode == 'monthly' ? 10000 : (t.interestMode == 'yearly' ? 120000 : 1);
  final free = t.timeBased ? t.freeMonths.clamp(0, term - 1) : 0;
  if (t.plan == 'end') {
    final interest = switch (t.interestMode) {
      'none' => 0,
      'once' => (principal * rh) ~/ 10000,
      _ => (principal * rh * (term - free)) ~/ d,
    };
    return [Installment(1, addMonths(start, term), principal, interest, principal + interest, 0)];
  }
  final mp = principal ~/ term, pr = principal % term;
  int total = 0, n = 1;
  if (t.interestMode == 'once') {
    total = (principal * rh) ~/ 10000;
    n = term;
  } else if (t.timeBased && t.calculation == 'flat') {
    total = (principal * rh * (term - free)) ~/ d;
    n = term - free;
  }
  final base = total ~/ n, rest = total % n;
  var rem = principal;
  final out = <Installment>[];
  for (var i = 1; i <= term; i++) {
    final p = mp + (i == term ? pr : 0);
    int interest;
    if (t.interestMode == 'once') {
      interest = base + (i == term ? rest : 0);
    } else if (t.timeBased && t.calculation == 'flat') {
      interest = i <= free ? 0 : base + (i == term ? rest : 0);
    } else if (t.timeBased) {
      interest = i <= free ? 0 : (rem * rh) ~/ d;
    } else {
      interest = 0;
    }
    rem -= p;
    out.add(Installment(i, addMonths(start, i), p, interest, p + interest, rem < 0 ? 0 : rem));
  }
  return out;
}

/// Late fee for one payment [days] past its due date. Same as the database's late_fee_for.
int lateFeeFor(int installment, int days, LoanTerms t) {
  final late = days - t.graceDays;
  if (t.lateType == 'none' || late <= 0) return 0;
  final each = t.lateType == 'fixed' ? t.lateAmount : (installment * _rateH(t.latePct)) ~/ 10000;
  final times = switch (t.lateEvery) {
    'once' => 1,
    'day' => late,
    'week' => (late / 7).ceil(),
    _ => (late / 30).ceil(),
  };
  return each * times;
}

/// The most late fees can ever reach on this loan, or null for no limit.
int? lateFeeCap(int principal, LoanTerms t) => t.capPct == null ? null : (principal * _rateH(t.capPct!)) ~/ 10000;

String _free(int m) => m <= 0 ? '' : (m == 1 ? ', first month free' : ', first $m months free');

/// Plain words: "5% every month on the full loan, first month free".
String describeInterest(LoanTerms t) {
  if (!t.hasInterest) return 'No interest. Pay back exactly what you borrowed.';
  final r = t.rate == t.rate.roundToDouble() ? t.rate.toStringAsFixed(0) : t.rate.toString();
  final how = t.calculation == 'flat' ? 'on the full loan' : 'on what is still owed';
  return switch (t.interestMode) {
    'once' => 'A one-time $r% of the loan.',
    'monthly' => '$r% every month $how${_free(t.freeMonths)}.',
    _ => '$r% a year $how${_free(t.freeMonths)}.',
  };
}

String describeLateFee(LoanTerms t, String Function(int) fmt) {
  if (t.lateType == 'none') return 'No late fee.';
  final what =
      t.lateType == 'fixed' ? fmt(t.lateAmount) : '${t.latePct == t.latePct.roundToDouble() ? t.latePct.toStringAsFixed(0) : t.latePct}% of the missed payment';
  final when = switch (t.lateEvery) { 'once' => 'once', 'day' => 'every day', 'week' => 'every week', _ => 'every month' };
  final grace = t.graceDays <= 0 ? '' : (t.graceDays == 1 ? ' after 1 grace day' : ' after ${t.graceDays} grace days');
  final cap = t.capPct != null ? ' Never more than ${t.capPct!.toStringAsFixed(t.capPct! % 1 == 0 ? 0 : 2)}% of the loan in total.' : '';
  return 'Late: $what, $when it stays unpaid$grace.$cap';
}
