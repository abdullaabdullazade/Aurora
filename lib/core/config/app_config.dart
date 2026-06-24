/// Runtime configuration.
abstract final class AppConfig {
  /// Vercel registry that always returns the PC resolver's current URL.
  /// Set this to your deployed registry, e.g. https://aurora-registry.vercel.app
  static const String registryUrl = 'https://aurora-registry.vercel.app';

  /// Resolver server base URL. Overridden at launch from [registryUrl] when
  /// reachable; otherwise this LAN fallback is used.
  ///
  /// Android emulator → http://10.0.2.2:8000 · physical phone → PC LAN IP.
  static String apiBase = 'http://192.168.0.193:8000';
}
