import 'i18n.dart';

/// Countries the app supports. Picking one sets the phone code, money and a suggested language.
class Country {
  final String code; // ISO, e.g. UG
  final String name;
  final String flag;
  final String dial; // phone country code without +
  final String currency;
  final AppLanguage language; // suggested app language
  final String example;
  const Country(this.code, this.name, this.flag, this.dial, this.currency, this.language, this.example);
}

const countries = [
  Country('UG', 'Uganda', '🇺🇬', '256', 'UGX', AppLanguage.en, '0772 123456'),
  Country('KE', 'Kenya', '🇰🇪', '254', 'KES', AppLanguage.sw, '0712 345678'),
  Country('TZ', 'Tanzania', '🇹🇿', '255', 'TZS', AppLanguage.sw, '0754 123456'),
  Country('RW', 'Rwanda', '🇷🇼', '250', 'RWF', AppLanguage.en, '0788 123456'),
];

Country countryByCode(String? code) => countries.firstWhere((c) => c.code == code, orElse: () => countries.first);

/// Sensible first share price, so a new group does not start with a strange number.
int suggestedSharePrice(String currency) => switch (currency) {
      'KES' => 10000, // KES 100.00 (stored in cents)
      'TZS' => 5000,
      'RWF' => 2000,
      _ => 5000,
    };
