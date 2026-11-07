import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/json.dart';

/// A message safe to show the user. Rule errors from the database are written for people.
class ApiError implements Exception {
  final String message;
  final bool isNetwork;
  const ApiError(this.message, {this.isNetwork = false});
  @override
  String toString() => message;
}

/// Thin door to the database. Every read and write goes through a named, rule-checked function.
class Api {
  SupabaseClient get _c => Supabase.instance.client;

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) async {
    try {
      return await _c.rpc(name, params: params);
    } on PostgrestException catch (e) {
      throw ApiError(e.message);
    } on AuthException catch (e) {
      throw ApiError(e.message);
    } catch (e) {
      throw const ApiError('No connection. Check your internet and try again.', isNetwork: true);
    }
  }

  /// Calls a server function (online payments). Same friendly errors as the database.
  Future<Json> _fn(String name, Json body) async {
    try {
      final r = await _c.functions.invoke(name, body: body);
      return asJson(r.data);
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map && d['error'] != null ? d['error'].toString() : 'The payment server said no (${e.status}). Try again.';
      throw ApiError(msg);
    } catch (e) {
      throw const ApiError('No connection. Check your internet and try again.', isNetwork: true);
    }
  }

  // ----- Sign in -----
  User? get user {
    try {
      return _c.auth.currentUser;
    } catch (_) {
      return null; // not started yet (tests, or before Supabase starts)
    }
  }

  Stream<AuthState> get authChanges => _c.auth.onAuthStateChange;

  Future<void> signIn(String email, String password) async {
    try {
      await _c.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw ApiError(e.message);
    } catch (e) {
      throw const ApiError('No connection. Check your internet and try again.', isNetwork: true);
    }
  }

  /// Google sign-in. Web comes back to the same page; phones come back through the app link.
  static const mobileRedirect = 'com.saccoledger.app://login-callback';

  Future<void> signInWithGoogle({required bool web}) async {
    try {
      await _c.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: web ? '${Uri.base.origin}${Uri.base.path}' : mobileRedirect,
        authScreenLaunchMode: web ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } on AuthException catch (e) {
      throw ApiError(e.message.contains('not enabled') ? 'Google sign-in is not switched on yet. Use phone or email for now.' : e.message);
    } catch (e) {
      throw const ApiError('No connection. Check your internet and try again.', isNetwork: true);
    }
  }

  Future<void> signUp(String email, String password) async {
    try {
      final r = await _c.auth.signUp(email: email, password: password);
      if (r.session == null) {
        throw const ApiError('Account made, but sign-in is off. Turn off "Confirm email" in Supabase (see README).');
      }
    } on AuthException catch (e) {
      throw ApiError(e.message);
    } on ApiError {
      rethrow;
    } catch (e) {
      throw const ApiError('No connection. Check your internet and try again.', isNetwork: true);
    }
  }

  /// [everywhere] also ends sessions on every other phone and browser.
  Future<void> signOut({bool everywhere = false}) => _c.auth.signOut(scope: everywhere ? SignOutScope.global : SignOutScope.local);

  /// Checks the current password first, so a borrowed unlocked phone cannot change it.
  Future<void> changePassword(String signInId, String current, String next) async {
    try {
      await _c.auth.signInWithPassword(email: signInId, password: current);
    } on AuthException {
      throw const ApiError('Current password is wrong.');
    } catch (e) {
      throw const ApiError('No connection. Check your internet and try again.', isNetwork: true);
    }
    try {
      await _c.auth.updateUser(UserAttributes(password: next));
    } on AuthException catch (e) {
      throw ApiError(e.message);
    } catch (e) {
      throw const ApiError('No connection. Check your internet and try again.', isNetwork: true);
    }
  }

  // ----- My account -----
  Future<Json> account() async => asJson(await _rpc('get_my_account'));
  Future<void> updateMyProfile(Json patch) => _rpc('update_my_profile', {'p': patch});
  Future<void> recordSignIn(String platform, String device) => _rpc('record_sign_in', {'p_platform': platform, 'p_device': device});
  Future<Json> exportMyData() async => asJson(await _rpc('export_my_data'));
  Future<void> requestDeletion(String reason) => _rpc('request_account_deletion', {'p_reason': reason});
  Future<void> cancelDeletion() => _rpc('cancel_account_deletion');
  Future<List<Json>> deletionRequests() async => asJsonList(await _rpc('list_deletion_requests'));
  Future<void> completeDeletion(String id, String note) => _rpc('complete_account_deletion', {'p_request': id, 'p_note': note});

  Future<bool> resetPassword(String email, String code, String password) async =>
      await _rpc('reset_password_with_code', {'p_email': email, 'p_code': code, 'p_new_password': password}) == true;

  // ----- Groups and people -----
  Future<List<Json>> myMemberships() async => asJsonList(await _rpc('my_memberships'));

  Future<String> createOrganization({
    required String name,
    required String edition,
    required String currency,
    required int sharePrice,
    required int multiplier,
    required int interest,
    required int quorum,
    required String myName,
    String? myPhone,
  }) async =>
      (await _rpc('create_organization', {
        'p_name': name,
        'p_edition': edition,
        'p_currency': currency,
        'p_share_price': sharePrice,
        'p_multiplier': multiplier,
        'p_interest': interest,
        'p_quorum': quorum,
        'p_my_name': myName,
        'p_my_phone': myPhone,
        'p_consent': true,
      }))
          .toString();

  Future<void> updateOrganization(String org, Json patch) => _rpc('update_organization', {'p_org': org, 'p': patch});
  Future<void> setOrgCountry(String org, String country) => _rpc('set_org_country', {'p_org': org, 'p_country': country});
  Future<void> updateMyPrefs(Json prefs) => _rpc('update_my_prefs', {'p': prefs});
  Future<String> seedDemo(String myName) async => (await _rpc('seed_demo', {'p_my_name': myName})).toString();
  Future<void> claimInvite(String code) => _rpc('claim_invite', {'p_code': code, 'p_consent': true});
  Future<List<Json>> members(String org) async => asJsonList(await _rpc('list_members', {'p_org': org}));

  Future<Json> addMember(
    String org, {
    required String name,
    String? phone,
    String? nationalId,
    required String role,
    String? kinName,
    String? kinPhone,
  }) async =>
      asJson(
        await _rpc('add_member', {
          'p_org': org,
          'p_name': name,
          'p_phone': phone,
          'p_national_id': nationalId,
          'p_role': role,
          'p_kin_name': kinName,
          'p_kin_phone': kinPhone,
        }),
      );

  Future<void> updateMember(String member, Json patch) => _rpc('update_member', {'p_member': member, 'p': patch});
  Future<String> newMemberCode(String member) async => (await _rpc('new_member_code', {'p_member': member})).toString();

  // ----- Money records -----
  Future<Json> recordPayment(Json params) async => asJson(await _rpc('record_payment', params));
  Future<void> reviewPayment(String id, bool approve, String note) => _rpc('review_payment', {'p_payment': id, 'p_approve': approve, 'p_note': note});
  Future<List<Json>> payments(String org, {String? status}) async =>
      asJsonList(await _rpc('list_payments', {'p_org': org, 'p_status': status, 'p_limit': 200}));
  Future<void> reverseJournal(String id, String reason) => _rpc('reverse_journal', {'p_journal': id, 'p_reason': reason});
  Future<List<Json>> journals(String org, {int limit = 200, int? cycle}) async =>
      asJsonList(await _rpc('list_journals', {'p_org': org, 'p_limit': limit, 'p_cycle': cycle}));

  // ----- Meetings -----
  Future<List<Json>> meetings(String org) async => asJsonList(await _rpc('list_meetings', {'p_org': org}));
  Future<void> openMeeting(String org, int cash, String c1, String c2) =>
      _rpc('open_meeting', {'p_org': org, 'p_date': DateTime.now().toIso8601String().substring(0, 10), 'p_cash': cash, 'p_c1': c1, 'p_c2': c2});
  Future<void> setAttendance(String meeting, String member, bool present) =>
      _rpc('set_attendance', {'p_meeting': meeting, 'p_member': member, 'p_present': present});
  Future<void> closeMeeting(String meeting, int cash, String c1, String c2, String minutes) =>
      _rpc('close_meeting', {'p_meeting': meeting, 'p_cash': cash, 'p_c1': c1, 'p_c2': c2, 'p_minutes': minutes});

  // ----- Loans -----
  Future<List<Json>> loans(String org) async => asJsonList(await _rpc('list_loans', {'p_org': org}));
  Future<void> applyLoan(String org, String member, int principal, int term, String type, String purpose) =>
      _rpc('apply_loan', {'p_org': org, 'p_member': member, 'p_principal': principal, 'p_term': term, 'p_type': type, 'p_purpose': purpose});
  Future<void> approveLoan(String loan, String resolution, String w1, String w2) =>
      _rpc('approve_loan', {'p_loan': loan, 'p_resolution': resolution, 'p_w1': w1, 'p_w2': w2});
  Future<void> rejectLoan(String loan, String reason) => _rpc('reject_loan', {'p_loan': loan, 'p_reason': reason});
  Future<void> disburseLoan(String loan, String channel, String? ref) => _rpc('disburse_loan', {'p_loan': loan, 'p_channel': channel, 'p_ref': ref});
  Future<List<Json>> loanSchedule(String loan) async => asJsonList(await _rpc('loan_schedule', {'p_loan': loan}));

  // ----- Emergency -----
  Future<List<Json>> emergency(String org) async => asJsonList(await _rpc('list_emergency', {'p_org': org}));
  Future<void> requestEmergency(String org, String member, int amount, String reason) =>
      _rpc('request_emergency', {'p_org': org, 'p_member': member, 'p_amount': amount, 'p_reason': reason});
  Future<void> decideEmergency(String claim, bool approve, String? channel, String? ref, String note) =>
      _rpc('decide_emergency', {'p_claim': claim, 'p_approve': approve, 'p_channel': channel, 'p_ref': ref, 'p_note': note});

  // ----- Savings goals -----
  Future<List<Json>> goals(String org) async => asJsonList(await _rpc('list_goals', {'p_org': org}));
  Future<Json> allocation(String org) async => asJson(await _rpc('savings_allocation', {'p_org': org}));
  Future<List<Json>> flows(String org) async => asJsonList(await _rpc('monthly_flows', {'p_org': org, 'p_months': 12}));
  Future<String> createGoal(String org,
          {required String name, required int target, required DateTime start, DateTime? end, required String frequency, int? perPerson}) async =>
      (await _rpc('create_goal', {
        'p_org': org,
        'p_name': name,
        'p_target': target,
        'p_start': _day(start),
        'p_end': end == null ? null : _day(end),
        'p_frequency': frequency,
        'p_per_person': perPerson,
      }))
          .toString();
  Future<void> closeGoal(String goal) => _rpc('close_goal', {'p_goal': goal});
  Future<void> setPaymentGoal(String payment, String? goal, String reason) =>
      _rpc('set_payment_goal', {'p_payment': payment, 'p_goal': goal, 'p_reason': reason});
  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ----- Reports -----
  Future<Json> dashboard(String org) async => asJson(await _rpc('dashboard', {'p_org': org}));
  Future<Json> trialBalance(String org) async => asJson(await _rpc('trial_balance', {'p_org': org}));
  Future<Json> statement(String org, String member, {int? cycle}) async =>
      asJson(await _rpc('member_statement', {'p_org': org, 'p_member': member, 'p_cycle': cycle}));
  Future<List<Json>> audit(String org) async => asJsonList(await _rpc('list_audit', {'p_org': org, 'p_limit': 300}));
  Future<Json> verifyAudit(String org) async => asJson(await _rpc('verify_audit_chain', {'p_org': org}));
  Future<Json> shareOutPreview(String org) async => asJson(await _rpc('shareout_preview', {'p_org': org}));
  Future<void> executeShareOut(String org) => _rpc('execute_shareout', {'p_org': org});
  Future<List<Json>> search(String org, String q) async => asJsonList(await _rpc('global_search', {'p_org': org, 'p_q': q}));
  Future<List<Json>> platformOverview() async => asJsonList(await _rpc('platform_overview'));

  // ----- Online payments (the group's own Flutterwave or Pesapal account) -----
  Future<Json> gatewayStatus(String org) async => asJson(await _rpc('gateway_status', {'p_org': org}));
  Future<void> disableGateway(String org) => _rpc('disable_gateway', {'p_org': org});
  Future<List<Json>> onlinePayments(String org) async => asJsonList(await _rpc('list_gateway_payments', {'p_org': org, 'p_limit': 50}));

  /// Keys go straight to the server function, which checks them with the gateway and locks them.
  Future<Json> saveGatewayKeys(String org, {required String gateway, required String mode, required Map<String, String> keys}) =>
      _fn('pay', {'action': 'save_keys', 'org_id': org, 'gateway': gateway, 'mode': mode, ...keys});

  /// Returns {id, tx_ref, checkout_url}. The app then opens checkout_url.
  Future<Json> startOnlinePayment(String org,
          {required String memberId, required String purpose, required int amount, String? loanId, String? goalId, String? note}) =>
      _fn('pay', {
        'action': 'start',
        'org_id': org,
        'member_id': memberId,
        'purpose': purpose,
        'amount': amount,
        'loan_id': loanId,
        'goal_id': goalId,
        'note': note,
      });

  /// Asks the gateway (through our server) whether it is paid. Returns {status, verify_note}.
  Future<Json> checkOnlinePayment(String id) => _fn('pay', {'action': 'check', 'id': id});

  // ----- Platform administrators -----
  Future<Json> platformAdmins() async => asJson(await _rpc('list_platform_admins'));
  Future<List<Json>> searchUsers(String q) async => asJsonList(await _rpc('search_users', {'p_q': q}));
  Future<Json> addPlatformAdmin(String email) async => asJson(await _rpc('add_platform_admin', {'p_email': email}));
  Future<void> removePlatformAdmin(String userId) => _rpc('remove_platform_admin', {'p_user': userId});
  Future<void> cancelAdminInvite(String email) => _rpc('cancel_admin_invite', {'p_email': email});
}
