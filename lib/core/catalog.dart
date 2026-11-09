/// The app's words for roles, payment purposes, channels and group types, in one place.
/// The database enforces the same rules. This copy only decides what the screens offer.
library;

enum Role {
  orgAdmin('org_admin', 'Organization Admin', 'Org Admin'),
  treasurer('treasurer', 'Treasurer', 'Treasurer'),
  secretary('secretary', 'Secretary', 'Secretary'),
  loanOfficer('loan_officer', 'Loan Officer', 'Loan Officer'),
  auditor('auditor', 'Auditor', 'Auditor'),
  member('member', 'Member', 'Member'),
  platformAdmin('platform_admin', 'Platform Admin', 'Platform');

  final String code;
  final String label;
  final String short;
  const Role(this.code, this.label, this.short);

  static Role parse(String? code) => values.firstWhere((r) => r.code == code, orElse: () => member);
  static String labelOf(String? code) => values.where((r) => r.code == code).firstOrNull?.label ?? (code ?? '');

  /// Roles a group admin can give. Platform admin is not a group role.
  static const assignable = [member, orgAdmin, treasurer, secretary, loanOfficer, auditor];

  bool get isOfficer => this != member;
  bool get isOrgAdmin => this == orgAdmin;

  /// Confirms payment records, disburses loans, forgives late fees, closes the cycle, connects online payments.
  bool get handlesMoney => this == orgAdmin || this == treasurer;
  bool get canManageMembers => this == orgAdmin || this == secretary;

  /// Runs meetings and records money for any member.
  bool get canRunMeetings => this == orgAdmin || this == treasurer || this == secretary;
  bool get canApproveLoans => this == orgAdmin || this == loanOfficer;
  bool get canApplyForOthers => canRunMeetings || this == loanOfficer;
}

enum Purpose {
  shares('shares', 'Buy shares'),
  savings('savings', 'Savings deposit'),
  fine('fine', 'Fine'),
  loanRepayment('loan_repayment', 'Loan repayment'),
  emergencyContribution('emergency_contribution', 'Emergency contribution'),
  withdrawal('withdrawal', 'Savings withdrawal'),
  expense('expense', 'Group expense');

  final String code;
  final String label;
  const Purpose(this.code, this.label);

  static Purpose parse(String? code) => values.firstWhere((p) => p.code == code, orElse: () => savings);
  static String labelOf(String? code) => values.where((p) => p.code == code).firstOrNull?.label ?? (code ?? '');

  /// Savings can carry a goal label. The money still goes into the one savings account.
  bool get takesGoal => this == shares || this == savings;
  bool get takesLoan => this == loanRepayment;
  bool get forMember => this != expense;
  bool get needsReason => this == fine || this == withdrawal || this == expense;

  /// Money leaving the group: only money officers record it, and never through online payment.
  bool get isPayout => this == withdrawal || this == expense;

  static List<Purpose> choices({required bool handlesMoney, required bool online}) => values.where((p) => !p.isPayout || (handlesMoney && !online)).toList();
}

enum Channel {
  mtnMomo('mtn_momo', 'MTN MoMo'),
  airtelMoney('airtel_money', 'Airtel Money'),
  bank('bank', 'Bank'),
  cash('cash', 'Cash'),
  // Set only by the server, after the gateway confirms the payment.
  flutterwave('flutterwave', 'Flutterwave', online: true),
  pesapal('pesapal', 'Pesapal', online: true);

  final String code;
  final String name;
  final bool online;
  const Channel(this.code, this.name, {this.online = false});

  static Channel parse(String? code) => values.firstWhere((c) => c.code == code, orElse: () => cash);
  static String labelOf(String? code) => values.where((c) => c.code == code).firstOrNull?.label ?? (code ?? '');

  /// Channels a person can pick by hand.
  static List<Channel> get byHand => values.where((c) => !c.online).toList();

  String get label => online ? '$name (verified)' : name;

  /// Every channel but cash leaves a transaction ID to check against the statement.
  bool get needsRef => this != cash;
}

enum Edition {
  vsla('tier_1_vsla', 'Tier 1', 'Community Groups', 'VSLA meetings, attendance, quorum, shares, fines, emergency fund, cycle share-out'),
  sacco('tier_2_sacco', 'Tier 2', 'Digital SACCO', 'Individual accounts, deposits, withdrawals, loan products, repayment schedules'),
  intelligent('tier_3_intelligent', 'Tier 3', 'Intelligent Finance', 'Full SACCO plus portfolio risk dashboards and risk flags');

  final String code;
  final String tier;
  final String title;
  final String hint;
  const Edition(this.code, this.tier, this.title, this.hint);

  static Edition parse(String? code) => values.firstWhere((e) => e.code == code, orElse: () => vsla);
  String get label => '$tier: $title';
}

/// The looks a person can pick in My Account. Each has a light and a dark side.
enum AppLook {
  emerald('emerald', 'Emerald and Gold', 'Green and gold, soft corners'),
  passbook('passbook', 'Passbook', 'Ink blue on paper, like a bank book');

  final String code;
  final String label;
  final String hint;
  const AppLook(this.code, this.label, this.hint);

  static AppLook parse(String? code) => values.firstWhere((l) => l.code == code, orElse: () => emerald);
}
