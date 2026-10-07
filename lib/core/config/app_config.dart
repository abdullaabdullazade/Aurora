/// Runtime configuration.
abstract final class AppConfig {
  /// Public project links used by the About section.
  static const String websiteUrl =
      'https://abdullaabdullazade.github.io/Aurora/';
  static const String repositoryUrl =
      'https://github.com/abdullaabdullazade/Aurora';

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
      
  /// Public server fallback if the registry fails. Override at build time:
  ///   flutter run --dart-define=AURORA_FALLBACK_LAN=http://YOUR_IP:8000
  static const String fallbackLanApi = 
      String.fromEnvironment('AURORA_FALLBACK_LAN', defaultValue: 'http://10.0.2.2:8000');

  /// Secret key for authenticating with the resolver server.
  static const String apiSecretKey =
      String.fromEnvironment('AURORA_SECRET_KEY', defaultValue: '');

  /// Firebase Google Sign-In Web client ID (OAuth client_type 3).
  /// Firebase Console → Authentication → Sign-in method → Google → Web client ID.
  static const String googleWebClientId = String.fromEnvironment(
    'AURORA_GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  /// YouTube playlist ID for the Top Charts carousel (Global Top Songs).
  static const String topChartsPlaylistId = String.fromEnvironment(
    'AURORA_TOP_CHARTS_PLAYLIST',
    defaultValue: 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI',
  );

  static const String youtubeReadonlyScope =
      'https://www.googleapis.com/auth/youtube.readonly';

  /// Resolver server base URL. Overridden at launch from [registryUrl] when
  /// reachable; otherwise this LAN fallback is used.
  ///
  /// Android emulator → http://10.0.2.2:8000 · physical phone → PC LAN IP.
  static String apiBase =
      useLocalServer ? localApiBase : fallbackLanApi;
}
