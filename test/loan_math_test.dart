import 'package:flutter_test/flutter_test.dart';
import 'package:sacco_ledger/core/loan_math.dart';

// Same numbers as the database tests (supabase/tests/run_tests.sql, LOAN RULES), so phone and books agree.
void main() {
  final start = DateTime(2026, 1, 31);
  List<int> totals(List<Installment> s) => s.map((i) => i.total).toList();
  List<int> interest(List<Installment> s) => s.map((i) => i.interest).toList();
  int sumInterest(List<Installment> s) => s.fold(0, (a, i) => a + i.interest);

  test('5% a month flat, first month free', () {
    expect(totals(loanSchedule(12000, 3, const LoanTerms(interestMode: 'monthly', rate: 5, freeMonths: 1), start)), [4000, 4600, 4600]);
  });
  test('5% a month reducing, first month free', () {
    expect(interest(loanSchedule(12000, 3, const LoanTerms(interestMode: 'monthly', rate: 5, calculation: 'reducing_balance', freeMonths: 1), start)),
        [0, 400, 200]);
  });
  test('pay everything at the end, 3 calendar months later', () {
    final s = loanSchedule(12000, 3, const LoanTerms(interestMode: 'monthly', rate: 5, freeMonths: 1, plan: 'end'), start);
    expect(totals(s), [13200]);
    expect(s.single.due, DateTime(2026, 4, 30));
  });
  test('one-time 10% spread over the months', () {
    expect(interest(loanSchedule(12000, 3, const LoanTerms(interestMode: 'once', rate: 10), start)), [400, 400, 400]);
  });
  test('no interest', () {
    expect(sumInterest(loanSchedule(12000, 3, const LoanTerms(interestMode: 'none', rate: 0, freeMonths: 2), start)), 0);
  });
  test('yearly rates, no rounding slip', () {
    expect(sumInterest(loanSchedule(12000, 3, const LoanTerms(interestMode: 'yearly', rate: 12), start)), 360);
    expect(sumInterest(loanSchedule(12000, 1, const LoanTerms(interestMode: 'yearly', rate: 10), start)), 100);
    expect(sumInterest(loanSchedule(10000, 4, const LoanTerms(interestMode: 'monthly', rate: 2.5, calculation: 'reducing_balance'), start)), 624);
  });
  test('every shilling of the loan is scheduled', () {
    final s = loanSchedule(10001, 3, const LoanTerms(interestMode: 'monthly', rate: 5, calculation: 'reducing_balance'), start);
    expect(s.fold<int>(0, (a, i) => a + i.principal), 10001);
    expect(s.last.left, 0);
  });
  test('month ends like the database', () {
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
  });
  test('late fees', () {
    const pct = LoanTerms(lateType: 'percent', latePct: 10, lateEvery: 'week', graceDays: 3);
    expect(lateFeeFor(4000, 17, pct), 800);
    expect(lateFeeFor(4000, 3, pct), 0);
    expect(lateFeeFor(4000, 10, const LoanTerms(lateType: 'fixed', lateAmount: 500, lateEvery: 'day')), 5000);
    expect(lateFeeFor(4000, 40, const LoanTerms(lateType: 'fixed', lateAmount: 1000, lateEvery: 'once')), 1000);
    expect(lateFeeFor(4000, 31, const LoanTerms(lateType: 'percent', latePct: 5, lateEvery: 'month')), 400);
    expect(lateFeeCap(12000, const LoanTerms(capPct: 5)), 600);
  });
  test('plain words', () {
    expect(describeInterest(const LoanTerms(interestMode: 'monthly', rate: 5, freeMonths: 1)), '5% every month on the full loan, first month free.');
    expect(describeInterest(const LoanTerms(interestMode: 'none', rate: 0)), startsWith('No interest'));
  });
}
