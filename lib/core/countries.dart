/// Countries the app supports. Picking one sets the phone code, money and a suggested language.
class Country {
  final String code; // ISO, e.g. UG
  final String name;
  final String flag;
  final String dial; // phone country code without +
  final String currency;
  final String language; // suggested app language (AppLanguage name)
  final int localLength; // digits after the country code
  final String example;
  const Country(this.code, this.name, this.flag, this.dial, this.currency, this.language, this.localLength, this.example);
}

const countries = [
  Country('UG', 'Uganda', '🇺🇬', '256', 'UGX', 'en', 9, '0772 123456'),
  Country('KE', 'Kenya', '🇰🇪', '254', 'KES', 'sw', 9, '0712 345678'),
  Country('TZ', 'Tanzania', '🇹🇿', '255', 'TZS', 'sw', 9, '0754 123456'),
  Country('RW', 'Rwanda', '🇷🇼', '250', 'RWF', 'en', 9, '0788 123456'),
];

Country countryByCode(String? code) => countries.firstWhere((c) => c.code == code, orElse: () => countries.first);

/// Sensible first share price, so a new group does not start with a strange number.
int suggestedSharePrice(String currency) => switch (currency) {
      'KES' => 10000, // KES 100.00 (stored in cents)
      'TZS' => 5000,
      'RWF' => 2000,
      _ => 5000,
    };
