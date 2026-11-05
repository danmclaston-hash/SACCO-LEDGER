/// Keys are passed at build time: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
/// This is the Supabase publishable (anon) key. It is safe in an app: the database rules decide what it can do.
/// Never put the secret / service_role key here.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
