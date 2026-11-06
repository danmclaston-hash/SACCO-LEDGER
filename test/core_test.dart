import 'package:flutter_test/flutter_test.dart';
import 'package:sacco_ledger/core/app_lock.dart';
import 'package:sacco_ledger/core/money.dart';
import 'package:sacco_ledger/core/risk.dart';
import 'package:sacco_ledger/core/search_index.dart';
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
      final m = RiskEngine.metrics({'active_portfolio': 100, 'member_savings': 100, 'cash_box': 50, 'momo_bank': 0, 'par30_amount': 0, 'par90_amount': 0, 'scheduled_month': 0, 'collected_month': 0});
      expect(m.score, 100);
    });
    test('late loans reduce score and raise a flag', () {
      final d = {'active_portfolio': 100, 'member_savings': 100, 'cash_box': 5, 'par30_amount': 50, 'par90_amount': 50, 'scheduled_month': 100, 'collected_month': 10};
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
    test('finds pages by words', () {
      expect(searchAppIndex('licence', officer: false).first.page, AppPage.licences);
      expect(searchAppIndex('momo', officer: false).first.page, AppPage.channels);
      expect(searchAppIndex('x', officer: false), isEmpty);
    });
    test('hides officer pages from members', () {
      expect(searchAppIndex('checker', officer: false), isEmpty);
      expect(searchAppIndex('checker', officer: true).first.page, AppPage.approvals);
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
}
