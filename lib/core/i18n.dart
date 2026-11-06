enum AppLanguage {
  en('English'),
  lg('Oluganda'),
  sw('Kiswahili');

  final String label;
  const AppLanguage(this.label);
}

/// Words carried over from the original app. Anything not listed shows in English.
const _t = <String, Map<AppLanguage, String>>{
  'app_title': {AppLanguage.en: 'SACCO Ledger', AppLanguage.lg: 'Ekitabo kya SACCO', AppLanguage.sw: 'Daftari la SACCO'},
  'dashboard': {AppLanguage.en: 'Overview', AppLanguage.lg: 'Ebikulu', AppLanguage.sw: 'Dashibodi'},
  'meetings': {AppLanguage.en: 'Meetings', AppLanguage.lg: 'Enkiiko', AppLanguage.sw: 'Mikutano'},
  'loans': {AppLanguage.en: 'Loans', AppLanguage.lg: 'Ebyewolo', AppLanguage.sw: 'Mikopo'},
  'members': {AppLanguage.en: 'Members', AppLanguage.lg: 'Bammemba', AppLanguage.sw: 'Wanachama'},
  'emergency': {AppLanguage.en: 'Emergency', AppLanguage.lg: "Ensawo Y'obuyambi", AppLanguage.sw: 'Mfuko wa Dharura'},
  'ledger': {AppLanguage.en: 'Ledger', AppLanguage.lg: "Ebitabo n'Okubala", AppLanguage.sw: 'Leja na Ukaguzi'},
  'share_out': {AppLanguage.en: 'Share-Out', AppLanguage.lg: 'Okugaba Ensimbi', AppLanguage.sw: 'Mugawanyo'},
  'my_account': {AppLanguage.en: 'My Account', AppLanguage.lg: 'Akawunti Yange', AppLanguage.sw: 'Akaunti Yangu'},
  'reports': {AppLanguage.en: 'Reports', AppLanguage.lg: 'Alipoota', AppLanguage.sw: 'Ripoti'},
  'open_meeting': {AppLanguage.en: 'Open Weekly Meeting', AppLanguage.lg: 'Ggulawo Olukiiko', AppLanguage.sw: 'Fungua Mkutano'},
  'close_meeting': {AppLanguage.en: 'Close Meeting (Reconcile Cash)', AppLanguage.lg: 'Ggalawo Olukiiko', AppLanguage.sw: 'Funga Mkutano'},
  'quorum_reached': {AppLanguage.en: 'Quorum Reached', AppLanguage.lg: 'Omuwendo Guweredde', AppLanguage.sw: 'Idadi Kamili Imefikiwa'},
  'cash_reconciled': {AppLanguage.en: 'Cash Reconciled', AppLanguage.lg: 'Ensimbi Zituuse Bulungi', AppLanguage.sw: 'Pesa Zimelinganishwa'},
  'ai_notice': {
    AppLanguage.en: 'AI suggests, never acts on money',
    AppLanguage.lg: 'AI ewa amagezi, tegulawo wadde okukwata ensimbi',
    AppLanguage.sw: 'AI inapendekeza tu, haigusi pesa zako'
  },
};

String translate(String key, AppLanguage lang) => _t[key]?[lang] ?? _t[key]?[AppLanguage.en] ?? key;
