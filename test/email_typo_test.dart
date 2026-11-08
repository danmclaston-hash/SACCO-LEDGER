import 'package:flutter_test/flutter_test.dart';
import 'package:sacco_ledger/ui/screens/auth_screen.dart';

void main() {
  test('common email slips are caught', () {
    expect(emailTypo('jane@gmial.com'), 'jane@gmail.com');
    expect(emailTypo('jane@yahoo.co'), 'jane@yahoo.com');
    expect(emailTypo('jane@gmail.com'), isNull);
    expect(emailTypo('jane@company.co.ug'), isNull);
  });
}
