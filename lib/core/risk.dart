import 'json.dart';

enum RiskSeverity { low, medium, high }

class RiskFlag {
  final RiskSeverity severity;
  final String title;
  final String recommendation;
  const RiskFlag(this.severity, this.title, this.recommendation);
}

class RiskMetrics {
  final double par30;
  final double par90;
  final double liquidity;
  final double collection;
  final int score;
  const RiskMetrics(this.par30, this.par90, this.liquidity, this.collection, this.score);
}

/// Rule-based advice carried over from the original app. It suggests. It never acts on money.
class RiskEngine {
  static RiskMetrics metrics(Json d) {
    final portfolio = d.i('active_portfolio');
    final savings = d.i('member_savings');
    final cash = d.i('cash_box') + d.i('momo_bank');
    final scheduled = d.i('scheduled_month');
    final par30 = portfolio > 0 ? d.i('par30_amount') / portfolio * 100 : 0.0;
    final par90 = portfolio > 0 ? d.i('par90_amount') / portfolio * 100 : 0.0;
    final liq = savings > 0 ? cash / savings * 100 : 100.0;
    final coll = scheduled > 0 ? d.i('collected_month') / scheduled * 100 : 100.0;
    var score = 100;
    if (par30 > 5) score -= (((par30 - 5) * 3).toInt()).clamp(0, 40);
    if (par90 > 2) score -= (((par90 - 2) * 5).toInt()).clamp(0, 30);
    if (liq < 15) score -= 20;
    if (coll < 90) score -= 15;
    return RiskMetrics(par30, par90, liq, coll, score.clamp(0, 100));
  }

  static List<RiskFlag> flags(Json d, RiskMetrics m) {
    final out = <RiskFlag>[];
    if (m.par30 > 10) {
      out.add(const RiskFlag(RiskSeverity.high, 'Elevated Portfolio at Risk (PAR 30 > 10%)',
          'Halt new large loan disbursements until delinquent borrowers are engaged by loan officers.'));
    }
    if (m.liquidity < 15) {
      out.add(
          const RiskFlag(RiskSeverity.high, 'Critically Low Cash Liquidity (< 15%)', 'Pause non-emergency loan disbursements to prevent liquidity shortage.'));
    } else if (m.liquidity > 70 && d.i('active_portfolio') < 50000) {
      out.add(
          const RiskFlag(RiskSeverity.low, 'High Idle Cash Reserve', 'Encourage qualified members with solid savings records to apply for seasonal loans.'));
    }
    final portfolio = d.i('active_portfolio');
    if (portfolio > 0 && d.i('top_loan_amount') / portfolio * 100 > 35 && d.i('active_loans') > 1) {
      out.add(RiskFlag(RiskSeverity.medium, 'Borrower Concentration Risk (> 35%)',
          'Loan ${d.s('top_loan_number')} is a big part of the portfolio. Check witnesses and collateral.'));
    }
    if (out.isEmpty) {
      out.add(const RiskFlag(
          RiskSeverity.low, 'Portfolio Operating within Safe Thresholds', 'Continue standard weekly meeting reconciliation and dual-counter verification.'));
    }
    return out;
  }
}

String arrearsBand(int days) {
  if (days <= 0) return 'Current';
  if (days <= 30) return 'Watch';
  if (days <= 60) return 'Substandard';
  if (days <= 90) return 'Doubtful';
  return 'Loss';
}
