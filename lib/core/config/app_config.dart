/// Runtime configuration.
abstract final class AppConfig {
  /// Resolver server base URL.
  ///
  /// Android emulator reaches the host machine at 10.0.2.2 (NOT localhost).
  /// For a physical phone on the same Wi-Fi, replace with the PC's LAN IP,
  /// e.g. http://192.168.1.20:8000
  static const String apiBase = 'http://10.0.2.2:8000';
}
