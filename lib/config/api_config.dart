/// API keys: prefer `--dart-define=GROQ_API_KEY=...` for CI / release.
/// [flutter_dotenv] loads `assets/env/gemini.env` for local development.
abstract final class ApiConfig {
  static const String groqApiKeyFromDefine = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );
}
