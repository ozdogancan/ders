enum AiProvider { openAi, gemini }

class Env {
  const Env._();

  static const String aiProviderRaw = String.fromEnvironment(
    'AI_PROVIDER',
    defaultValue: 'openai',
  );
  static const String openAiApiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String openAiModel = String.fromEnvironment(
    'OPENAI_MODEL',
    defaultValue: 'gpt-4o',
  );
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String supabaseBucket = String.fromEnvironment(
    'SUPABASE_BUCKET',
    defaultValue: 'question-images',
  );

  // Evlumba DB (source of truth)
  static const String evlumbaUrl = String.fromEnvironment(
    'EVLUMBA_SUPABASE_URL',
    defaultValue: 'https://vgtgcjnrsladdharzkwn.supabase.co',
  );
  static const String evlumbaAnonKey = String.fromEnvironment(
    'EVLUMBA_SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZndGdjam5yc2xhZGRoYXJ6a3duIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM0MjU1NzEsImV4cCI6MjA4OTAwMTU3MX0.7P5QagZdPntMliL1m5Zte7DSDR0CYkgwoHR7js4wqPg',
  );

  static const bool requireLogin = bool.fromEnvironment(
    'REQUIRE_LOGIN',
    defaultValue: false,
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasEvlumbaConfig =>
      evlumbaUrl.isNotEmpty && evlumbaAnonKey.isNotEmpty;

  static AiProvider get aiProvider {
    if (aiProviderRaw.toLowerCase() == 'gemini') {
      return AiProvider.gemini;
    }
    return AiProvider.openAi;
  }
}
