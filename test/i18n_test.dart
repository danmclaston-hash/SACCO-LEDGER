import 'package:flutter/material.dart' hide Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:sacco_ledger/core/i18n.dart';
import 'package:sacco_ledger/ui/text.dart';

void main() {
  tearDown(() => Lang.current = AppLanguage.en);

  test('words change with the language, and unknown text stays English', () {
    expect(translate('Home', AppLanguage.sw), 'Nyumbani');
    expect(translate('Home', AppLanguage.lg), 'Awaka');
    expect(translate('Home', AppLanguage.en), 'Home');
    expect(translate('zzz not a real sentence', AppLanguage.sw), 'zzz not a real sentence');
  });

  test('counted words translate, but never swallow a whole sentence', () {
    expect(translate('3 payments', AppLanguage.sw), 'malipo 3');
    expect(translate('Laston Savers has many members', AppLanguage.sw), 'Laston Savers has many members');
  });

  testWidgets('the whole screen switches when the language changes', (t) async {
    Widget app(AppLanguage l) => MaterialApp(home: LangScope(language: l, child: const Scaffold(body: Text('Home'))));
    await t.pumpWidget(app(AppLanguage.en));
    expect(find.text('Home'), findsOneWidget);
    Lang.current = AppLanguage.sw;
    await t.pumpWidget(app(AppLanguage.sw));
    expect(find.text('Nyumbani'), findsOneWidget);
    Lang.current = AppLanguage.lg;
    await t.pumpWidget(app(AppLanguage.lg));
    expect(find.text('Awaka'), findsOneWidget);
  });
}
