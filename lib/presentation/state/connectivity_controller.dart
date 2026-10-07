import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits true when any network transport is available.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);
  yield online(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(online);
});

/// Convenience: defaults to online until the first reading arrives.
final isOnlineProvider = Provider<bool>(
  (ref) => ref.watch(connectivityProvider).valueOrNull ?? true,
);

/// Emits true when Wi-Fi is among the active transports.
final wifiConnectivityProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool wifi(List<ConnectivityResult> r) => r.contains(ConnectivityResult.wifi);
  yield wifi(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(wifi);
});

/// Defaults to true until the first reading (allows downloads before probe).
final isWifiProvider = Provider<bool>(
  (ref) => ref.watch(wifiConnectivityProvider).valueOrNull ?? true,
);
