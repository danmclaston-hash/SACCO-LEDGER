enum AppLanguage {
  en('English'),
  lg('Oluganda'),
  sw('Kiswahili');

  final String label;
  const AppLanguage(this.label);
}

/// Words carried over from the original app, looked up by their English text.
/// Anything not listed shows in English.
const _t = <String, Map<AppLanguage, String>>{
  'SACCO Ledger': {AppLanguage.lg: 'Ekitabo kya SACCO', AppLanguage.sw: 'Daftari la SACCO'},
  'Home': {AppLanguage.lg: 'Awaka', AppLanguage.sw: 'Nyumbani'},
  'Pay': {AppLanguage.lg: 'Sasula', AppLanguage.sw: 'Lipa'},
  'More': {AppLanguage.lg: 'Ebirala', AppLanguage.sw: 'Zaidi'},
  'My money': {AppLanguage.lg: 'Ssente zange', AppLanguage.sw: 'Pesa zangu'},
  'Help': {AppLanguage.lg: 'Obuyambi', AppLanguage.sw: 'Msaada'},
  'Overview': {AppLanguage.lg: 'Ebikulu', AppLanguage.sw: 'Dashibodi'},
  'Meetings': {AppLanguage.lg: 'Enkiiko', AppLanguage.sw: 'Mikutano'},
  'Loans': {AppLanguage.lg: 'Ebyewolo', AppLanguage.sw: 'Mikopo'},
  'Members': {AppLanguage.lg: 'Bammemba', AppLanguage.sw: 'Wanachama'},
  'Emergency': {AppLanguage.lg: "Ensawo Y'obuyambi", AppLanguage.sw: 'Mfuko wa Dharura'},
  'Ledger & Audit': {AppLanguage.lg: "Ebitabo n'Okubala", AppLanguage.sw: 'Leja na Ukaguzi'},
  'Ledger': {AppLanguage.lg: 'Ebitabo', AppLanguage.sw: 'Leja'},
  'Share-Out': {AppLanguage.lg: 'Okugaba Ensimbi', AppLanguage.sw: 'Mugawanyo'},
  'My Account': {AppLanguage.lg: 'Akawunti Yange', AppLanguage.sw: 'Akaunti Yangu'},
  'Goals': {AppLanguage.lg: 'Ebigendererwa', AppLanguage.sw: 'Malengo'},
  'Open Weekly Meeting': {AppLanguage.lg: 'Ggulawo Olukiiko', AppLanguage.sw: 'Fungua Mkutano'},
  'Close Meeting (Reconcile Cash)': {AppLanguage.lg: 'Ggalawo Olukiiko', AppLanguage.sw: 'Funga Mkutano'},
  'Quorum Reached': {AppLanguage.lg: 'Omuwendo Guweredde', AppLanguage.sw: 'Idadi Kamili Imefikiwa'},
  'Cash Reconciled': {AppLanguage.lg: 'Ensimbi Zituuse Bulungi', AppLanguage.sw: 'Pesa Zimelinganishwa'},
  'AI suggests, never acts on money': {
    AppLanguage.lg: 'AI ewa amagezi, tegulawo wadde okukwata ensimbi',
    AppLanguage.sw: 'AI inapendekeza tu, haigusi pesa zako',
  },
};

String translate(String english, AppLanguage lang) => _t[english]?[lang] ?? english;
