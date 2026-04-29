enum AiProvider { openAi, gemini }

class Env {
  const Env._();

  static const String aiProviderRaw = String.fromEnvironment(
    'AI_PROVIDER',
    defaultValue: 'openai',
  );
  // NOTE: openAiApiKey / geminiApiKey were intentionally removed from the
  // client. AI calls go through the koala-api proxy (KOALA_API_URL) which
  // holds the real keys server-side. Re-introducing them here would leak
  // them into the web bundle and Android APK.
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

  // Evlumba DB (source of truth) — keys must be passed via --dart-define
  static const String evlumbaUrl = String.fromEnvironment(
    'EVLUMBA_SUPABASE_URL',
  );
  static const String evlumbaAnonKey = String.fromEnvironment(
    'EVLUMBA_SUPABASE_ANON_KEY',
  );

  // Koala API proxy (Next.js backend)
  static const String koalaApiUrl = String.fromEnvironment(
    'KOALA_API_URL',
    defaultValue: 'https://koala-api-olive.vercel.app',
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
