import 'package:flutter_test/flutter_test.dart';
import 'package:sacco_ledger/core/app_lock.dart';
import 'package:sacco_ledger/core/goal_math.dart';
import 'package:sacco_ledger/core/money.dart';
import 'package:sacco_ledger/core/names.dart';
import 'package:sacco_ledger/core/risk.dart';
import 'package:sacco_ledger/core/pages.dart';
import 'package:sacco_ledger/core/share_out.dart';

void main() {
  group('share-out', () {
    test('worked example A pays exactly the pool', () {
      final r = ShareOut.calculate(40083, const [ShareOutInput('ann', 'Ann', 20000), ShareOutInput('ben', 'Ben', 10000), ShareOutInput('cy', 'Cy', 10000)]);
      expect(r.map((e) => e.payout).toList(), [20041, 10021, 10021]);
      expect(r.fold<int>(0, (a, e) => a + e.payout), 40083);
    });
    test('worked example B gives 34, 33, 33', () {
      final r = ShareOut.calculate(100, const [ShareOutInput('a', 'A', 10), ShareOutInput('b', 'B', 10), ShareOutInput('c', 'C', 10)]);
      expect(r.map((e) => e.payout).toList(), [34, 33, 33]);
    });
    test('big numbers do not overflow', () {
      final r = ShareOut.calculate(9000000000000, const [ShareOutInput('a', 'A', 3000000000000), ShareOutInput('b', 'B', 6000000000001)]);
      expect(r.fold<int>(0, (a, e) => a + e.payout), 9000000000000);
    });
    test('nothing to share gives empty', () {
      expect(ShareOut.calculate(0, const [ShareOutInput('a', 'A', 10)]), isEmpty);
      expect(ShareOut.calculate(10, const [ShareOutInput('a', 'A', 0)]), isEmpty);
    });
  });

  group('money', () {
    test('formats UGX and KES', () {
      expect(Money.format(1234567), 'UGX 1,234,567');
      expect(Money.format(0), 'UGX 0');
      expect(Money.format(150050, 'KES'), 'KES 1,500.50');
      expect(Money.format(-5000), 'UGX -5,000');
    });
    test('parses safely', () {
      expect(Money.parse('10,000'), 10000);
      expect(Money.parse('10.5'), null);
      expect(Money.parse('-5'), null);
      expect(Money.parse('abc'), null);
      expect(Money.parse('10.5', 'KES'), 1050);
      expect(Money.parse('10.555', 'KES'), null);
    });
    test('masks', () {
      expect(Money.maskPhone('256772123456'), '256772 *** *456');
      expect(Money.maskNationalId('CM12345678ABCD'), 'CM*****BCD');
    });
  });

  group('phones', () {
    test('normalizes Uganda numbers', () {
      expect(Phones.normalize('0772 123456'), '256772123456');
      expect(Phones.normalize('+256772123456'), '256772123456');
      expect(Phones.normalize('772123456'), '256772123456');
    });
    test('login email', () {
      expect(Phones.loginEmail('0772123456'), '256772123456@phone.saccoledger.app');
      expect(Phones.loginEmail('Boss@Mail.com '), 'boss@mail.com');
    });
    test('validation', () {
      expect(Phones.looksValid('0772123456'), isTrue);
      expect(Phones.looksValid('123'), isFalse);
      expect(Phones.looksValid('a@b.co'), isTrue);
      expect(Phones.looksValid('a@b'), isFalse);
    });
  });

  group('risk', () {
    test('healthy group scores 100', () {
      final m = RiskEngine.metrics({
        'active_portfolio': 100,
        'member_savings': 100,
        'cash_box': 50,
        'momo_bank': 0,
        'par30_amount': 0,
        'par90_amount': 0,
        'scheduled_month': 0,
        'collected_month': 0
      });
      expect(m.score, 100);
    });
    test('late loans reduce score and raise a flag', () {
      final d = {
        'active_portfolio': 100,
        'member_savings': 100,
        'cash_box': 5,
        'par30_amount': 50,
        'par90_amount': 50,
        'scheduled_month': 100,
        'collected_month': 10
      };
      final m = RiskEngine.metrics(d);
      expect(m.score, lessThan(60));
      expect(RiskEngine.flags(d, m).any((f) => f.severity == RiskSeverity.high), isTrue);
    });
    test('arrears bands', () {
      expect(arrearsBand(0), 'Current');
      expect(arrearsBand(30), 'Watch');
      expect(arrearsBand(31), 'Substandard');
      expect(arrearsBand(90), 'Doubtful');
      expect(arrearsBand(91), 'Loss');
    });
  });

  group('app index', () {
    bool member(AppPage p) => p.audience == Audience.everyone;
    bool officer(AppPage p) => p.audience != Audience.platform;
    test('finds pages by words', () {
      expect(searchPages('licence', member).first, AppPage.licences);
      expect(searchPages('momo', member).first, AppPage.channels);
      expect(searchPages('x', member), isEmpty);
    });
    test('hides officer pages from members', () {
      expect(searchPages('checker', member), isEmpty);
      expect(searchPages('checker', officer).first, AppPage.approvals);
    });
  });

  group('app lock', () {
    test('right PIN opens, wrong PIN does not', () {
      final salt = PinLock.newSalt();
      final h = PinLock.hash('2580', salt);
      expect(PinLock.check('2580', salt, h), isTrue);
      expect(PinLock.check('2581', salt, h), isFalse);
    });
    test('same PIN gives a different hash on another phone', () {
      expect(PinLock.hash('2580', PinLock.newSalt()) == PinLock.hash('2580', PinLock.newSalt()), isFalse);
    });
    test('PIN must be 4 to 6 numbers', () {
      expect(PinLock.validPin('1234'), isTrue);
      expect(PinLock.validPin('123456'), isTrue);
      expect(PinLock.validPin('123'), isFalse);
      expect(PinLock.validPin('12a4'), isFalse);
      expect(PinLock.validPin('1234567'), isFalse);
    });
    test('initials', () {
      expect(initials('Ann Namubiru'), 'AN');
      expect(initials('ben'), 'B');
      expect(initials('  '), '?');
      expect(initials('Okecho Danmark Laston'), 'OL');
    });
  });

  group('savings goals', () {
    test('500,000 for 5 people over 7 days: 14,286 exact, 14,500 to carry', () {
      expect(GoalMath.exactPerPerson(500000, 5, 7), 14286);
      expect(GoalMath.perPerson(500000, 5, 7), 14500);
      expect(GoalMath.reach(5, 14500, 7) >= 500000, isTrue);
    });
    test('10,000 each per day reaches 500,000 in 10 days', () {
      expect(GoalMath.periodsNeeded(500000, 5, 10000), 10);
    });
    test('10,000 each for 7 days reaches 350,000', () {
      expect(GoalMath.reach(5, 10000, 7), 350000);
    });
    test('periods between dates', () {
      final s = DateTime(2026, 11, 1);
      expect(GoalMath.periodsBetween(s, DateTime(2026, 11, 7), Frequency.daily), 7);
      expect(GoalMath.periodsBetween(s, DateTime(2026, 11, 14), Frequency.weekly), 2);
      expect(GoalMath.periodsBetween(s, DateTime(2027, 1, 1), Frequency.monthly), 3);
      expect(GoalMath.periodsBetween(s, DateTime(2026, 10, 1), Frequency.daily), 0);
    });
    test('friendly rounding never rounds down', () {
      expect(GoalMath.friendlyUp(14286), 14500);
      expect(GoalMath.friendlyUp(14500), 14500);
      expect(GoalMath.friendlyUp(730), 800);
      expect(GoalMath.friendlyUp(21001), 22000);
      expect(GoalMath.friendlyUp(0), 0);
    });
    test('bad input gives zero, not a crash', () {
      expect(GoalMath.perPerson(500000, 0, 7), 0);
      expect(GoalMath.periodsNeeded(500000, 5, 0), 0);
    });
    test('status: behind and catch-up amount', () {
      final st = GoalStatus.of(
          target: 500000,
          collected: 100000,
          people: 5,
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 10),
          frequency: Frequency.daily,
          today: DateTime(2026, 11, 5));
      expect(st.planned, 250000);
      expect(st.behindBy, 150000);
      expect(st.onTrack, isFalse);
      expect(st.periodsLeft, 6);
      expect(st.catchUpEach, 13500); // 400,000 left / 5 people / 6 days = 13,334, rounded up to 13,500
    });
    test('status: done', () {
      final st = GoalStatus.of(target: 100, collected: 120, people: 2, start: DateTime(2026), frequency: Frequency.weekly, today: DateTime(2026, 2));
      expect(st.done, isTrue);
      expect(st.left, 0);
    });
  });
}
