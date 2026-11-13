import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_lock.dart';
import '../core/catalog.dart';
import '../core/countries.dart';
import '../core/i18n.dart';
import '../core/json.dart';
import '../core/pages.dart';
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

  /// Everything one group's screens show. Add a dataset here and it is loaded, cached for offline and cleared on sign-out.
  static final Map<String, Future<Object> Function(Api, String)> _groupData = {
    'dash': (a, id) => a.dashboard(id),
    'members': (a, id) => a.members(id),
    'journals': (a, id) => a.journals(id),
    'meetings': (a, id) => a.meetings(id),
    'loans': (a, id) => a.loans(id),
    'payments': (a, id) => a.payments(id),
    'claims': (a, id) => a.emergency(id),
    'goals': (a, id) => a.goals(id),
    'allocation': (a, id) => a.allocation(id),
    'flows': (a, id) => a.flows(id),
  };

  bool booting = true;
  bool loading = false;
  bool offline = false;
  String? loadError;

  /// Goes up after every reload, so screens that fetch their own extra data fetch again.
  int version = 0;
  bool get signedIn => api.user != null;
  List<Json> orgs = [];
  Json? org;

  /// Circles that invited me and are waiting for my yes or no.
  List<Json> invites = [];

  /// An invitation code from a link (?join=CODE). Kept until the person is signed in and has seen it.
  String? pendingJoin;
  Json _data = {};
  List<Json> outbox = [];
  List<String> outboxFailures = [];
  AppLanguage language = AppLanguage.en;
  AppPage page = AppPage.overview;
  int ledgerTab = 0;

  /// Whose statement the Statements page shows. Null means my own.
  String? statementMemberId;
  StreamSubscription? _authSub;
  Json account = {};
  ThemeMode themeMode = ThemeMode.system;
  AppLook look = AppLook.emerald;

  /// True in a browser. Tests set it to try both sides.
  bool onWeb = kIsWeb;

  /// Phone code at sign-in (UG, KE, TZ, RW). Groups have their own country.
  String country = 'UG';

  /// Show the small (i) buttons that explain words like "share-out".
  bool showTips = true;

  /// Welcome tour finished or skipped. "Later" only hides it until the app restarts.
  bool tourDone = false;
  bool tourLater = false;
  double textScale = 1.0;
  bool locked = false;
  int pinTries = 0;
  DateTime? _hiddenAt;
  SharedPreferences? _prefs;

  Json get dash => _data['dash'] as Json? ?? const {};
  List<Json> get members => _list('members');
  List<Json> get journals => _list('journals');
  List<Json> get meetings => _list('meetings');
  List<Json> get loans => _list('loans');
  List<Json> get payments => _list('payments');
  List<Json> get claims => _list('claims');
  List<Json> get goals => _list('goals');
  Json get allocation => _data['allocation'] as Json? ?? const {};
  List<Json> get flows => _list('flows');
  List<Json> _list(String k) => _data[k] as List<Json>? ?? const [];

  String get orgId => org?.s('id') ?? '';
  String get currency => org?.s('currency_code') ?? 'UGX';
  Role get role => Role.parse(org?.s('my_role'));
  String? get myMemberId => org?.n('my_member_id');
  String t(String text) => translate(text, language);

  /// The platform owner's view of every group: given by the account, or by the platform role in this group.
  bool get canSeeAllGroups => account.b('is_platform_admin') || role == Role.platformAdmin;

  bool canSee(AppPage p) => switch (p.audience) {
        Audience.everyone => true,
        Audience.officers => role.isOfficer,
        // Owner and developer tools live on the website only. The database checks the owner again on every call.
        Audience.platform => canSeeAllGroups && onWeb,
      };

  List<Json> get activeGoals => goals.where((g) => g.s('status') == 'active').toList();
  String? goalName(String? id) => goals.where((g) => g.s('id') == id).firstOrNull?.s('name');
  Json? get openMeeting => meetings.where((m) => m.s('status') == 'open').firstOrNull;
  List<Json> get activeMembers => members.where((m) => m.b('is_active')).toList();
  Json? get me => members.where((m) => m.s('id') == myMemberId).firstOrNull;

  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
    _applySettings(asJson(jsonDecode(_prefs?.getString('look') ?? '{}')));
    // A link like https://site/?join=ABCD2345. Kept on the phone, so it survives signing in and Google's round trip.
    final link = kIsWeb ? Uri.base.queryParameters['join'] : null;
    if (link != null && link.trim().isNotEmpty) await _prefs?.setString('pending_join', link.trim().toUpperCase());
    pendingJoin = _prefs?.getString('pending_join');
    _authSub = api.authChanges.listen((e) async {
      final id = e.session?.user.id;
      if (id == null) {
        _clear();
        notifyListeners();
      } else {
        if (e.event == AuthChangeEvent.signedIn && !booting) unawaited(noteSignIn());
        if (orgs.isEmpty && !booting) await refresh();
      }
    });
    if (signedIn) {
      locked = hasPin;
      await refresh();
    }
    booting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// The link's invitation was shown (joined, declined or closed). Forget it so it does not open again.
  Future<void> clearPendingJoin() async {
    pendingJoin = null;
    await _prefs?.remove('pending_join');
    notifyListeners();
  }

  void _clear() {
    invites = [];
    outbox = [];
    outboxFailures = [];
    orgs = [];
    org = null;
    _data = {};
    statementMemberId = null;
    page = AppPage.overview;
  }

  void _applySettings(Json j) {
    themeMode = switch (j.s('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final ts = double.tryParse(j.s('text_scale'));
    textScale = ts == null ? 1.0 : ts.clamp(0.85, 1.6);
    language = AppLanguage.values.firstWhere((l) => l.name == j.s('language'), orElse: () => AppLanguage.en);
    // The phone keeps these at the top level; the account keeps them under "prefs".
    final p = j['prefs'] is Map ? j.m('prefs') : j;
    if (p['country'] != null) country = countryByCode(p.s('country')).code;
    if (p['show_tips'] != null) showTips = p['show_tips'] == true;
    if (p['tour_done'] != null) tourDone = p['tour_done'] == true;
    if (p['look'] != null) look = AppLook.parse(p.s('look'));
  }

  Json get _look => {'theme': themeMode.name, 'text_scale': textScale, 'language': language.name};
  Json get _prefsJson => {'country': country, 'show_tips': showTips, 'tour_done': tourDone, 'look': look.code};

  /// The group's phone code (+256...), or the person's own country before they join a group.
  String get dial => countryByCode(org?.n('country_code') ?? country).dial;

  /// Changes how the app looks and behaves for this person. Offline, it is kept on the phone and sent next time.
  Future<String?> updateSettings(
      {ThemeMode? theme, AppLook? look, double? scale, AppLanguage? language, String? country, bool? showTips, bool? tourDone}) async {
    if (theme != null) themeMode = theme;
    if (look != null) this.look = look;
    if (scale != null) textScale = scale;
    if (language != null) this.language = language;
    if (country != null) this.country = country;
    if (showTips != null) this.showTips = showTips;
    if (tourDone != null) this.tourDone = tourDone;
    notifyListeners();
    await _prefs?.setString('look', jsonEncode({..._look, ..._prefsJson}));
    if (!signedIn) return null;
    try {
      if (theme != null || scale != null || language != null) await api.updateMyProfile(_look);
      if (country != null || showTips != null || tourDone != null || look != null) await api.updateMyPrefs(_prefsJson);
      return null;
    } on ApiError catch (e) {
      return e.isNetwork ? null : e.message;
    }
  }

  void tourLaterThisTime() {
    tourLater = true;
    notifyListeners();
  }

  Future<void> loadAccount() async {
    try {
      account = await api.account();
      _applySettings(account);
      await _prefs?.setString('look', jsonEncode({..._look, ..._prefsJson}));
    } on ApiError {
      // Offline: the phone's copy stays.
    }
    notifyListeners();
  }

  /// Called once after each successful sign-in, so the person can see where their account was used.
  Future<void> noteSignIn() async {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    try {
      await api.recordSignIn(platform, kIsWeb ? 'Browser' : 'Phone app');
    } on ApiError {
      // The sign-in itself already worked.
    }
  }

  String get _lockKey => 'lock_${api.user?.id}';
  Json get _lock => asJson(jsonDecode(_prefs?.getString(_lockKey) ?? '{}'));
  bool get hasPin => _lock.s('hash').isNotEmpty;
  bool get useBiometrics => _lock.b('bio');

  Future<void> setPin(String pin) async {
    final salt = PinLock.newSalt();
    await _prefs?.setString(_lockKey, jsonEncode({'salt': salt, 'hash': PinLock.hash(pin, salt), 'bio': useBiometrics}));
    notifyListeners();
  }

  Future<void> removePin() async {
    await _prefs?.remove(_lockKey);
    notifyListeners();
  }

  Future<void> setBiometrics(bool on) async {
    final l = _lock;
    l['bio'] = on;
    await _prefs?.setString(_lockKey, jsonEncode(l));
    notifyListeners();
  }

  void _unlock() {
    locked = false;
    pinTries = 0;
    notifyListeners();
  }

  /// true = unlocked. After [maxPinTries] wrong PINs the person is signed out and must use their password.
  Future<bool> unlockWithPin(String pin) async {
    final l = _lock;
    if (PinLock.check(pin, l.s('salt'), l.s('hash'))) {
      _unlock();
      return true;
    }
    pinTries++;
    if (pinTries >= maxPinTries) {
      pinTries = 0;
      await signOut();
    }
    notifyListeners();
    return false;
  }

  Future<bool> biometricsAvailable() async {
    if (kIsWeb) return false;
    try {
      final a = LocalAuthentication();
      return await a.isDeviceSupported() && await a.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    try {
      final ok = await LocalAuthentication().authenticate(localizedReason: 'Unlock SACCO Ledger', biometricOnly: true);
      if (ok) _unlock();
      return ok;
    } catch (_) {
      return false;
    }
  }

  void appHidden() => _hiddenAt ??= DateTime.now();

  void appShown() {
    final t = _hiddenAt;
    _hiddenAt = null;
    if (signedIn && hasPin && t != null && DateTime.now().difference(t) >= lockAfter) {
      locked = true;
      notifyListeners();
    }
  }

  void goTo(AppPage p, {int? tab, String? memberId}) {
    page = p;
    ledgerTab = tab ?? 0;
    if (memberId != null) statementMemberId = memberId;
    notifyListeners();
  }

  Future<void> selectOrg(Json o) async {
    page = AppPage.overview;
    statementMemberId = null;
    await refresh(select: o.s('id'));
  }

  /// Reloads my groups, the chosen group's records and my account. With no signal, shows the last saved copy.
  Future<void> refresh({String? select}) async {
    loading = true;
    notifyListeners();
    final accountLoad = loadAccount();
    try {
      await _loadOutbox();
      await flushOutbox();
      orgs = await api.myMemberships();
      await _prefs?.setString('orgs', jsonEncode(orgs));
      invites = await _loadInvites();
      await _pickOrg(select);
      if (org != null) {
        final id = orgId;
        final loaded = await Future.wait([for (final load in _groupData.values) load(api, id)]);
        _data = Map.fromIterables(_groupData.keys, loaded);
        await _prefs?.setString('cache_$id', jsonEncode(_data));
      }
      offline = false;
      loadError = null;
    } on ApiError catch (e) {
      if (e.isNetwork) {
        offline = true;
        final c = _prefs?.getString('orgs');
        if (c != null) orgs = asJsonList(jsonDecode(c));
        await _pickOrg(select);
        final cached = asJson(jsonDecode(_prefs?.getString('cache_$orgId') ?? '{}'));
        _data = {for (final e in cached.entries) e.key: e.value is List ? asJsonList(e.value) : asJson(e.value)};
      } else {
        loadError = e.message;
      }
    } finally {
      await accountLoad;
      version++;
      loading = false;
      notifyListeners();
    }
  }

  /// Invitations never stop the rest of the app from loading.
  Future<List<Json>> _loadInvites() async {
    try {
      return await api.myInvites();
    } on ApiError catch (e) {
      if (e.isNetwork) rethrow;
      return invites;
    }
  }

  /// My circles where I am an active member, best role first. The platform's look-only view of other circles is left out.
  List<Json> get myCircles {
    final mine = orgs.where((o) => o.s('my_role') != Role.platformAdmin.code).toList();
    mine.sort((a, b) {
      final r = Role.parse(a.s('my_role')).index.compareTo(Role.parse(b.s('my_role')).index);
      return r != 0 ? r : a.s('name').toLowerCase().compareTo(b.s('name').toLowerCase());
    });
    return mine;
  }

  /// Circles the platform team can look at but is not a member of.
  List<Json> get lookOnlyCircles => orgs.where((o) => o.s('my_role') == Role.platformAdmin.code).toList();

  Future<void> _pickOrg(String? select) async {
    final want = select ?? org?.s('id') ?? _prefs?.getString('org');
    // With nothing chosen yet, open one of my own circles, never a circle the platform team can only look at.
    org = orgs.where((o) => o.s('id') == want).firstOrNull ?? myCircles.firstOrNull ?? orgs.firstOrNull;
    if (org != null) await _prefs?.setString('org', orgId);
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

  /// Each person's unsent payments wait under their own name, so another person signing in on a shared phone never sends them.
  String get _outboxKey => 'outbox_${api.user?.id}';

  Future<void> _loadOutbox() async {
    // Phones from before this change kept one shared list; it belongs to whoever signs in first.
    final old = _prefs?.getString('outbox');
    if (old != null && signedIn) {
      await _prefs?.setString(_outboxKey, old);
      await _prefs?.remove('outbox');
    }
    final c = _prefs?.getString(_outboxKey);
    outbox = c == null ? [] : asJsonList(jsonDecode(c));
  }

  Future<void> _saveOutbox() async => _prefs?.setString(_outboxKey, jsonEncode(outbox));

  /// With no signal the payment is kept on the phone and sent later: [queued] is true and there is no [error].
  Future<({String? error, bool queued})> recordPayment({
    String? memberId,
    required String purpose,
    required int amount,
    required String channel,
    String? ref,
    String? loanId,
    String? note,
    String? goalId,
  }) async {
    final params = <String, dynamic>{
      'p_org': orgId,
      'p_member': memberId,
      'p_purpose': purpose,
      'p_amount': amount,
      'p_channel': channel,
      'p_ref': ref,
      'p_payer_phone': null,
      'p_loan': loanId,
      'p_note': note,
      'p_idem': newKey(), // same key on retry means it can never be recorded twice
      'p_goal': goalId,
    };
    try {
      await api.recordPayment(params);
      await refresh();
      return (error: null, queued: false);
    } on ApiError catch (e) {
      if (!e.isNetwork) return (error: e.message, queued: false);
      outbox = [...outbox, params];
      await _saveOutbox();
      notifyListeners();
      return (error: null, queued: true);
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
          outboxFailures = [...outboxFailures, '${Purpose.labelOf(p.s('p_purpose'))} ${p.i('p_amount')}: ${e.message}'];
        }
      }
    }
    outbox = left;
    await _saveOutbox();
  }

  Future<void> signOut({bool everywhere = false}) async {
    try {
      await api.signOut(everywhere: everywhere);
    } catch (_) {
      // signing out on this phone must work even with no signal
    }
    locked = false;
    account = {};
    await _prefs?.remove('org');
    // A shared phone must not keep the last person's records.
    for (final k in _prefs?.getKeys().where((k) => k.startsWith('cache_') || k == 'orgs').toList() ?? <String>[]) {
      await _prefs?.remove(k);
    }
    _clear();
    notifyListeners();
  }
}
