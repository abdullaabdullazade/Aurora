/// Runtime configuration.
abstract final class AppConfig {
  /// Vercel registry that always returns the PC resolver's current URL.
  /// Set this to your deployed registry, e.g. https://aurora-registry.vercel.app
  static const String registryUrl = String.fromEnvironment('AURORA_REGISTRY',
      defaultValue: 'https://vercel-registry-five.vercel.app');

  /// Local-development mode: talk to a resolver running on this machine and
  /// skip the registry lookup entirely.
  ///
  ///   flutter run --dart-define=AURORA_LOCAL=true
  ///   flutter run --dart-define-from-file=.env
  static const bool useLocalServer = bool.fromEnvironment('AURORA_LOCAL');

  /// 10.0.2.2 is the Android emulator's alias for the host machine's loopback,
  /// so this reaches `uvicorn main:app --host 0.0.0.0 --port 8000` on the PC.
  static const String localApiBase =
      String.fromEnvironment('AURORA_API', defaultValue: 'http://10.0.2.2:8000');
      
  /// Physical phone LAN fallback if the registry fails.
  static const String fallbackLanApi = 
      String.fromEnvironment('AURORA_FALLBACK_LAN', defaultValue: 'http://192.168.0.193:8000');

  /// Resolver server base URL. Overridden at launch from [registryUrl] when
  /// reachable; otherwise this LAN fallback is used.
  ///
  /// Android emulator → http://10.0.2.2:8000 · physical phone → PC LAN IP.
  static String apiBase =
      useLocalServer ? localApiBase : fallbackLanApi;
}
