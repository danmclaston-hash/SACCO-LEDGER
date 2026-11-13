/// Live project "SACCO LEDGER RIPE" is the default. To point at another project, pass keys at build time: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
/// This is the Supabase publishable (anon) key. It is safe in an app: the database rules decide what it can do.
/// Never put the secret / service_role key here.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://otisdtjijwdxkzjsmzvx.supabase.co');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: 'sb_publishable_EPslRjGgWM7KYMs1JzstuQ_Rywfl0ui');

  /// The public website. Invitation links point here, so they open on any phone or computer.
  static const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: 'https://sacco-ledger.pages.dev');
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
