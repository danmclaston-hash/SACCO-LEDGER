/// Pages of the app. Used by navigation and by the search box.
enum AppPage { account, overview, approvals, members, meetings, loans, emergency, ledger, shareOut, channels, statements, licences, settings, platform }

class IndexEntry {
  final AppPage page;
  final String title;
  final String hint;
  final List<String> words;
  final bool officerOnly;
  const IndexEntry(this.page, this.title, this.hint, this.words, {this.officerOnly = false});
}

/// The fixed part of the index: where things live in the app.
/// The live part (people, transactions, loans...) comes from the database search.
const appIndex = <IndexEntry>[
  IndexEntry(AppPage.overview, 'Overview', 'Group money position and risk', [
    'dashboard',
    'home',
    'balance',
    'cash',
    'lockbox',
    'par',
    'risk',
    'liquidity',
    'health',
    'score',
  ]),
  IndexEntry(AppPage.channels, 'Channels: pay and record', 'Pay with MoMo or Airtel, then record the transaction ID', [
    'pay',
    'payment',
    'momo',
    'mtn',
    'airtel',
    'ussd',
    '165',
    '185',
    'mobile money',
    'deposit',
    'shares',
    'savings',
    'record',
    'transaction',
  ]),
  IndexEntry(AppPage.approvals, 'Approvals', 'Payment records waiting for a second person', [
    'approve',
    'confirm',
    'reject',
    'pending',
    'review',
    'queue',
    'maker',
    'checker',
  ], officerOnly: true),
  IndexEntry(AppPage.meetings, 'Meetings', 'Open, attendance, quorum, cash count, minutes', [
    'meeting',
    'quorum',
    'attendance',
    'minutes',
    'count',
    'reconcile',
    'fine',
    'counter',
  ]),
  IndexEntry(AppPage.loans, 'Loans', 'Apply, approve, pay out, repayments, arrears', [
    'loan',
    'borrow',
    'credit',
    'witness',
    'guarantor',
    'interest',
    'repay',
    'arrears',
    'schedule',
    'disburse',
  ]),
  IndexEntry(AppPage.emergency, 'Emergency fund', 'Separate welfare pot and relief claims', [
    'emergency',
    'welfare',
    'relief',
    'claim',
    'hospital',
    'funeral',
    'social',
  ]),
  IndexEntry(AppPage.ledger, 'Ledger and audit trail', 'Journals, trial balance, tamper check', [
    'ledger',
    'journal',
    'audit',
    'trial balance',
    'reversal',
    'reverse',
    'history',
    'hash',
    'trail',
  ]),
  IndexEntry(AppPage.statements, 'Statements', 'Who paid what, by cycle. PDF and CSV', [
    'statement',
    'report',
    'pdf',
    'csv',
    'export',
    'print',
    'cycle',
    'circle',
    'transactions',
  ]),
  IndexEntry(AppPage.shareOut, 'Share-out', 'End of cycle payouts, largest remainder', [
    'share out',
    'shareout',
    'cycle',
    'circle',
    'payout',
    'dividend',
    'profit',
    'close cycle',
  ]),
  IndexEntry(AppPage.members, 'Members', 'People, roles, invite codes', [
    'member',
    'people',
    'role',
    'treasurer',
    'secretary',
    'invite',
    'code',
    'phone',
    'nin',
    'next of kin',
    'password',
    'reset',
  ], officerOnly: true),
  IndexEntry(AppPage.licences, 'Licences and compliance', 'Which licences apply, your group licence and expiry', [
    'licence',
    'license',
    'umra',
    'bank of uganda',
    'bou',
    'nita',
    'pdpo',
    'data protection',
    'fia',
    'aml',
    'legal',
    'compliance',
    'registration',
  ]),
  IndexEntry(AppPage.account, 'My Account', 'Profile, password, PIN lock, theme, text size, my data', [
    'account',
    'profile',
    'my',
    'photo',
    'password',
    'pin',
    'lock',
    'fingerprint',
    'security',
    'sign in',
    'devices',
    'theme',
    'dark',
    'text size',
    'language',
    'privacy',
    'download',
    'delete',
    'close account',
  ]),
  IndexEntry(AppPage.settings, 'Settings', 'Share price, loan limit, interest, quorum', [
    'settings',
    'share price',
    'interest rate',
    'multiplier',
    'quorum',
    'merchant',
    'group',
  ], officerOnly: true),
];

List<IndexEntry> searchAppIndex(String q, {required bool officer}) {
  final t = q.trim().toLowerCase();
  if (t.length < 2) return const [];
  return appIndex.where((e) {
    if (e.officerOnly && !officer) return false;
    return e.title.toLowerCase().contains(t) || e.hint.toLowerCase().contains(t) || e.words.any((w) => w.contains(t) || t.contains(w));
  }).toList();
}
