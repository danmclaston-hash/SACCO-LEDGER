import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../core/json.dart';
import '../core/search_index.dart';
import '../data/api.dart';

String newKey() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// One place that holds what the screens show. Screens call [act], which runs a change
/// and then reloads, so what you see always comes from the database.
class AppState extends ChangeNotifier {
  final Api api;
  AppState(this.api);

  static const _officerRoles = {'org_admin', 'treasurer', 'secretary', 'loan_officer', 'auditor', 'platform_admin'};

  bool booting = true;
  bool loading = false;
  bool offline = false;
  String? loadError;
  bool get signedIn => api.user != null;
  List<Json> orgs = [];
  Json? org;
  Json dash = {};
  List<Json> members = [];
  List<Json> journals = [];
  List<Json> meetings = [];
  List<Json> loans = [];
  List<Json> payments = [];
  List<Json> claims = [];
  List<Json> outbox = [];
  List<String> outboxFailures = [];
  AppLanguage language = AppLanguage.en;
  AppPage page = AppPage.overview;
  int ledgerTab = 0;
  String? statementMemberId;
  StreamSubscription? _authSub;
  SharedPreferences? _prefs;

  String get orgId => org?.s('id') ?? '';
  String get currency => org?.s('currency_code') ?? 'UGX';
  String get role => org?.s('my_role') ?? 'member';
  String? get myMemberId => org?.n('my_member_id');
  String t(String key) => translate(key, language);

  bool get isOfficer => _officerRoles.contains(role);
  bool get isPlatformAdmin => role == 'platform_admin';
  bool get canReview => role == 'org_admin' || role == 'treasurer';
  bool get canManageMembers => role == 'org_admin' || role == 'secretary';
  bool get canRunMeetings => role == 'org_admin' || role == 'treasurer' || role == 'secretary';
  bool get canRecordForOthers => canRunMeetings;
  bool get canApproveLoans => role == 'org_admin' || role == 'loan_officer';
  bool get canDisburse => role == 'org_admin' || role == 'treasurer';
  bool get canApplyForOthers => canRunMeetings || role == 'loan_officer';
  bool get isOrgAdmin => role == 'org_admin';
  Json? get openMeeting {
    for (final m in meetings) {
      if (m.s('status') == 'open') return m;
    }
    return null;
  }

  List<Json> get activeMembers => members.where((m) => m.b('is_active')).toList();
  Json? get me {
    for (final m in members) {
      if (m.s('id') == myMemberId) return m;
    }
    return null;
  }

  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
    final lang = _prefs?.getString('lang');
    language = AppLanguage.values.firstWhere((l) => l.name == lang, orElse: () => AppLanguage.en);
    _loadOutbox();
    _authSub = api.authChanges.listen((e) async {
      final id = e.session?.user.id;
      if (id == null) {
        _clear();
        notifyListeners();
      } else if (orgs.isEmpty && !booting) {
        await loadOrgs();
      }
    });
    if (signedIn) await loadOrgs();
    booting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _clear() {
    orgs = [];
    org = null;
    dash = {};
    members = journals = meetings = loans = payments = claims = [];
    page = AppPage.overview;
  }

  void setLanguage(AppLanguage l) {
    language = l;
    _prefs?.setString('lang', l.name);
    notifyListeners();
  }

  void goTo(AppPage p, {int? tab, String? memberId}) {
    page = p;
    if (tab != null) ledgerTab = tab;
    if (memberId != null) statementMemberId = memberId;
    notifyListeners();
  }

  Future<void> loadOrgs({String? select}) async {
    try {
      orgs = await api.myMemberships();
      offline = false;
      await _prefs?.setString('orgs', jsonEncode(orgs));
    } on ApiError catch (e) {
      if (e.isNetwork) {
        offline = true;
        final c = _prefs?.getString('orgs');
        if (c != null) orgs = asJsonList(jsonDecode(c));
      } else {
        loadError = e.message;
      }
    }
    final want = select ?? _prefs?.getString('org') ?? org?.s('id');
    org = orgs.isEmpty ? null : orgs.firstWhere((o) => o.s('id') == want, orElse: () => orgs.first);
    if (org != null) await refresh();
    notifyListeners();
  }

  Future<void> selectOrg(Json o) async {
    org = o;
    page = AppPage.overview;
    await _prefs?.setString('org', o.s('id'));
    await refresh();
  }

  Future<void> refresh() async {
    if (org == null) return;
    loading = true;
    notifyListeners();
    final id = orgId;
    try {
      await flushOutbox();
      final r = await Future.wait<dynamic>([
        api.dashboard(id),
        api.members(id),
        api.journals(id),
        api.meetings(id),
        api.loans(id),
        api.payments(id),
        api.emergency(id),
      ]);
      dash = r[0] as Json;
      members = r[1] as List<Json>;
      journals = r[2] as List<Json>;
      meetings = r[3] as List<Json>;
      loans = r[4] as List<Json>;
      payments = r[5] as List<Json>;
      claims = r[6] as List<Json>;
      offline = false;
      loadError = null;
      await _prefs?.setString('cache_$id',
          jsonEncode({'dash': dash, 'members': members, 'journals': journals, 'meetings': meetings, 'loans': loans, 'payments': payments, 'claims': claims}));
    } on ApiError catch (e) {
      if (e.isNetwork) {
        offline = true;
        _loadCache(id);
      } else {
        loadError = e.message;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _loadCache(String id) {
    final c = _prefs?.getString('cache_$id');
    if (c == null) return;
    final j = asJson(jsonDecode(c));
    dash = j.m('dash');
    members = j.l('members');
    journals = j.l('journals');
    meetings = j.l('meetings');
    loans = j.l('loans');
    payments = j.l('payments');
    claims = j.l('claims');
  }

  /// Runs one change, reloads, returns null if fine or the error text to show.
  Future<String?> act(Future<void> Function() fn) async {
    try {
      await fn();
      await refresh();
      return null;
    } on ApiError catch (e) {
      return e.message;
    }
  }

  // ----- Payments can be queued when there is no signal -----
  void _loadOutbox() {
    final c = _prefs?.getString('outbox');
    outbox = c == null ? [] : asJsonList(jsonDecode(c));
  }

  Future<void> _saveOutbox() async => _prefs?.setString('outbox', jsonEncode(outbox));

  /// Returns null if recorded, 'queued' if saved for later, or an error message.
  Future<String?> recordPayment({
    String? memberId,
    required String purpose,
    required int amount,
    required String channel,
    String? ref,
    String? payerPhone,
    String? loanId,
    String? note,
  }) async {
    final params = <String, dynamic>{
      'p_org': orgId,
      'p_member': memberId,
      'p_purpose': purpose,
      'p_amount': amount,
      'p_channel': channel,
      'p_ref': ref,
      'p_payer_phone': payerPhone,
      'p_loan': loanId,
      'p_note': note,
      'p_idem': newKey(), // same key on retry means it can never be recorded twice
    };
    try {
      await api.recordPayment(params);
      await refresh();
      return null;
    } on ApiError catch (e) {
      if (!e.isNetwork) return e.message;
      outbox = [...outbox, params];
      await _saveOutbox();
      notifyListeners();
      return 'queued';
    }
  }

  Future<void> flushOutbox() async {
    if (outbox.isEmpty) return;
    final left = <Json>[];
    for (final p in outbox) {
      try {
        await api.recordPayment(p);
      } on ApiError catch (e) {
        if (e.isNetwork) {
          left.add(p);
        } else {
          outboxFailures = [...outboxFailures, '${p.s('p_purpose')} ${p.i('p_amount')}: ${e.message}'];
        }
      }
    }
    outbox = left;
    await _saveOutbox();
  }

  Future<void> signOut() async {
    await api.signOut();
    await _prefs?.remove('org');
    // A shared phone must not keep the last person's records.
    for (final k in _prefs?.getKeys().where((k) => k.startsWith('cache_') || k == 'orgs').toList() ?? <String>[]) {
      await _prefs?.remove(k);
    }
    _clear();
    notifyListeners();
  }
}
