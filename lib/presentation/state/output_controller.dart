import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the system audio-output picker (route to speaker / Bluetooth /
/// headphones — works even while Bluetooth is connected).
Future<void> openOutputPicker() async {
  try {
    await const MethodChannel('aurora/media').invokeMethod('openOutputPicker');
  } catch (_) {}
}

enum OutputKind { speaker, headphones, bluetooth }

class OutputDevice {
  final OutputKind kind;
  final String label;
  const OutputDevice(this.kind, this.label);
}

OutputKind _kindOf(Set<AudioDevice> devices) {
  bool any(bool Function(String n) f) =>
      devices.where((d) => d.isOutput).any((d) => f(d.type.name.toLowerCase()));
  if (any((n) => n.contains('bluetooth'))) return OutputKind.bluetooth;
  if (any((n) => n.contains('headset') ||
      n.contains('headphone') ||
      n.contains('usb'))) {
    return OutputKind.headphones;
  }
  return OutputKind.speaker;
}

OutputDevice _device(OutputKind k) => switch (k) {
      OutputKind.bluetooth => const OutputDevice(OutputKind.bluetooth, 'Bluetooth'),
      OutputKind.headphones =>
        const OutputDevice(OutputKind.headphones, 'Headphones'),
      OutputKind.speaker =>
        const OutputDevice(OutputKind.speaker, 'Device Speakers'),
    };

/// Reactive current audio output. Android auto-routes to headphones/bluetooth
/// when connected; this surfaces what's active so the UI can show it.
final outputDeviceProvider = StreamProvider<OutputDevice>((ref) async* {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  yield _device(_kindOf(await session.getDevices()));
  await for (final _ in session.devicesChangedEventStream) {
    yield _device(_kindOf(await session.getDevices()));
  }
});
