/// Every page of the app: its name, what it is for, the words that find it in search, and who may open it.
/// Menus, tabs and the search box all read this one list.
library;

enum Audience { everyone, officers, platform }

enum AppPage {
  overview('Overview', 'Group money position and risk', ['dashboard', 'home', 'balance', 'cash', 'lockbox', 'par', 'risk', 'liquidity', 'health', 'score'],
      tab: 'Home'),
  approvals('Approvals', 'Payment records waiting for a second person', ['approve', 'confirm', 'reject', 'pending', 'review', 'queue', 'maker', 'checker'],
      audience: Audience.officers),
  goals('Goals', 'Plan a savings target, see who brings how much, track progress',
      ['goal', 'target', 'plan', 'projection', 'forecast', 'calculator', 'how much', 'per day', 'per week', 'how long', 'save', 'fund', 'chart', 'progress']),
  members('Members', 'People, roles, invite codes',
      ['member', 'people', 'role', 'treasurer', 'secretary', 'invite', 'code', 'phone', 'nin', 'next of kin', 'password', 'reset'],
      audience: Audience.officers),
  meetings(
      'Meetings', 'Open, attendance, quorum, cash count, minutes', ['meeting', 'quorum', 'attendance', 'minutes', 'count', 'reconcile', 'fine', 'counter']),
  loans('Loans', 'Apply, approve, pay out, repayments, arrears',
      ['loan', 'borrow', 'credit', 'witness', 'guarantor', 'interest', 'repay', 'arrears', 'schedule', 'disburse']),
  emergency('Emergency', 'Separate welfare pot and relief claims', ['emergency', 'welfare', 'relief', 'claim', 'hospital', 'funeral', 'social']),
  ledger('Ledger & Audit', 'Journals, trial balance, tamper check',
      ['ledger', 'journal', 'audit', 'trial balance', 'reversal', 'reverse', 'history', 'hash', 'trail'],
      audience: Audience.officers, tab: 'Ledger'),
  statements('Statements', 'Who paid what, by cycle. PDF and CSV', ['statement', 'report', 'pdf', 'csv', 'export', 'print', 'cycle', 'circle', 'transactions']),
  shareOut('Share-Out', 'End of cycle payouts, largest remainder', ['share out', 'shareout', 'cycle', 'circle', 'payout', 'dividend', 'profit', 'close cycle']),
  channels('Channels', 'Pay with MoMo or Airtel, then record the transaction ID',
      ['pay', 'payment', 'momo', 'mtn', 'airtel', 'ussd', '165', '185', 'mobile money', 'deposit', 'shares', 'savings', 'record', 'transaction'],
      tab: 'Pay'),
  licences('Licences', 'Which licences apply, your group licence and expiry',
      ['licence', 'license', 'umra', 'bank of uganda', 'bou', 'nita', 'pdpo', 'data protection', 'fia', 'aml', 'legal', 'compliance', 'registration'],
      audience: Audience.officers),
  settings(
      'Group Settings', 'Share price, loan limit, interest, quorum', ['settings', 'share price', 'interest rate', 'multiplier', 'quorum', 'merchant', 'group'],
      audience: Audience.officers),
  circles('My circles', 'Every circle I am in and my role there, invitations, start or join a circle',
      ['circle', 'circles', 'group', 'groups', 'my groups', 'switch', 'invite', 'invitation', 'join', 'role', 'admin', 'treasurer', 'new group', 'create']),
  account('My Account', 'Profile, password, PIN lock, theme, text size, my data', [
    'account', 'profile', 'my', 'photo', 'password', 'pin', 'lock',
    'fingerprint', 'security', 'sign in', 'devices', //
    'theme', 'dark', 'text size', 'language', 'privacy', 'download', 'delete',
    'close account',
  ]),
  platform('All groups', 'Every group on the platform, administrators, account closing requests', ['all groups', 'platform', 'administrator', 'owner'],
      audience: Audience.platform);

  final String title;
  final String hint;
  final List<String> words;
  final Audience audience;
  final String? _tab;
  const AppPage(this.title, this.hint, this.words, {this.audience = Audience.everyone, String? tab}) : _tab = tab;

  /// Shorter name for the phone's bottom bar.
  String get tab => _tab ?? title;
}

/// Pages whose name, hint or words match what was typed.
List<AppPage> searchPages(String q, bool Function(AppPage) canSee) {
  final t = q.trim().toLowerCase();
  if (t.length < 2) return const [];
  return AppPage.values.where((p) {
    if (!canSee(p)) return false;
    return p.title.toLowerCase().contains(t) || p.hint.toLowerCase().contains(t) || p.words.any((w) => w.contains(t) || t.contains(w));
  }).toList();
}
