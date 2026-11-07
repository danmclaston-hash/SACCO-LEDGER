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

  /// The group's rules (organizations row).
  factory LoanTerms.fromGroup(Map<String, dynamic> o) => LoanTerms(
        interestMode: o['loan_interest_mode']?.toString() ?? 'yearly',
        rate: _d(o['loan_interest_rate'] ?? o['default_interest_rate_pct'], 10),
        calculation: o['loan_calculation']?.toString() ?? 'flat',
        freeMonths: _i(o['loan_free_months'], 0),
        plan: o['loan_repayment_plan']?.toString() ?? 'monthly',
        lateType: o['late_fee_type']?.toString() ?? 'none',
        lateAmount: _i(o['late_fee_amount'], 0),
        latePct: _d(o['late_fee_pct'], 0),
        lateEvery: o['late_fee_every']?.toString() ?? 'once',
        graceDays: _i(o['late_fee_grace_days'], 0),
        capPct: o['late_fee_cap_pct'] == null ? null : _d(o['late_fee_cap_pct'], 0),
      );

  /// One loan's own rules.
  factory LoanTerms.fromLoan(Map<String, dynamic> l) => LoanTerms(
        interestMode: l['interest_mode']?.toString() ?? 'yearly',
        rate: _d(l['interest_rate'] ?? l['interest_rate_pct'], 0),
        calculation: l['calculation_type']?.toString() ?? 'flat',
        freeMonths: _i(l['free_months'], 0),
        plan: l['repayment_plan']?.toString() ?? 'monthly',
        lateType: l['late_fee_type']?.toString() ?? 'none',
        lateAmount: _i(l['late_fee_amount'], 0),
        latePct: _d(l['late_fee_pct'], 0),
        lateEvery: l['late_fee_every']?.toString() ?? 'once',
        graceDays: _i(l['late_fee_grace_days'], 0),
        capPct: l['late_fee_cap_pct'] == null ? null : _d(l['late_fee_cap_pct'], 0),
      );

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
int _rateH(double r) => (r * 100).round();
int _floorDiv(int a, int b) => a ~/ b; // amounts are never negative, so this rounds down

List<Installment> loanSchedule(int principal, int term, LoanTerms t, DateTime start) {
  if (principal <= 0 || term < 1) return const [];
  final rh = _rateH(t.rate);
  // monthly: P*r/100 ; yearly: P*r/1200 ; with r in hundredths -> extra *100
  final d = t.interestMode == 'monthly' ? 10000 : (t.interestMode == 'yearly' ? 120000 : 1);
  final free = t.timeBased ? t.freeMonths.clamp(0, term - 1) : 0;
  if (t.plan == 'end') {
    final interest = switch (t.interestMode) {
      'none' => 0,
      'once' => _floorDiv(principal * rh, 10000),
      _ => _floorDiv(principal * rh * (term - free), d),
    };
    return [Installment(1, addMonths(start, term), principal, interest, principal + interest, 0)];
  }
  final mp = principal ~/ term, pr = principal % term;
  int total = 0, n = 1;
  if (t.interestMode == 'once') {
    total = _floorDiv(principal * rh, 10000);
    n = term;
  } else if (t.timeBased && t.calculation == 'flat') {
    total = _floorDiv(principal * rh * (term - free), d);
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
      interest = i <= free ? 0 : _floorDiv(rem * rh, d);
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
  final each = t.lateType == 'fixed' ? t.lateAmount : _floorDiv(installment * _rateH(t.latePct), 10000);
  final times = switch (t.lateEvery) {
    'once' => 1,
    'day' => late,
    'week' => (late / 7).ceil(),
    _ => (late / 30).ceil(),
  };
  return each * times;
}

/// The most late fees can ever reach on this loan, or null for no limit.
int? lateFeeCap(int principal, LoanTerms t) => t.capPct == null ? null : _floorDiv(principal * _rateH(t.capPct!), 10000);

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
  final grace = t.graceDays > 0 ? ' after ${t.graceDays} grace day${t.graceDays == 1 ? '' : 's'}' : '';
  final cap = t.capPct != null ? ' Never more than ${t.capPct!.toStringAsFixed(t.capPct! % 1 == 0 ? 0 : 2)}% of the loan in total.' : '';
  return 'Late: $what, $when it stays unpaid$grace.$cap';
}
