import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _media = MethodChannel('aurora/media');

/// Opens system Bluetooth settings (scan / pair). Media routing stays with the OS.
Future<void> openOutputPicker() async {
  try {
    await _media.invokeMethod('openOutputPicker');
  } catch (_) {}
}

enum OutputKind { speaker, headphones, bluetooth }

class OutputDevice {
  final OutputKind kind;
  final String label;
  final String? id;
  final bool isActive;

  const OutputDevice(
    this.kind,
    this.label, {
    this.id,
    this.isActive = false,
  });

  OutputDevice copyWith({
    OutputKind? kind,
    String? label,
    String? id,
    bool? isActive,
  }) =>
      OutputDevice(
        kind ?? this.kind,
        label ?? this.label,
        id: id ?? this.id,
        isActive: isActive ?? this.isActive,
      );
}

OutputKind _kindFromType(String type) => switch (type) {
      'bluetooth' => OutputKind.bluetooth,
      'headphones' => OutputKind.headphones,
      _ => OutputKind.speaker,
    };

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

OutputDevice _fallbackDevice(OutputKind k) => switch (k) {
      OutputKind.bluetooth =>
        const OutputDevice(OutputKind.bluetooth, 'Bluetooth'),
      OutputKind.headphones =>
        const OutputDevice(OutputKind.headphones, 'Headphones'),
      OutputKind.speaker =>
        const OutputDevice(OutputKind.speaker, 'Device Speakers'),
    };

/// Lists available audio outputs from the native AudioManager.
Future<List<OutputDevice>> listAudioOutputs() async {
  try {
    final raw = await _media.invokeMethod<List<dynamic>>('listAudioOutputs');
    if (raw == null) return const [];
    return raw.whereType<Map<Object?, Object?>>().map((m) {
      final type = '${m['type'] ?? 'speaker'}';
      return OutputDevice(
        _kindFromType(type),
        '${m['name'] ?? 'Output'}',
        id: m['id']?.toString(),
        isActive: m['isActive'] == true,
      );
    }).toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// Ask the OS to connect/disconnect A2DP for [id]. Routing stays system-owned.
Future<bool> selectAudioOutput(String id) async {
  try {
    final ok = await _media.invokeMethod<bool>(
      'setPreferredOutput',
      {'id': id},
    );
    return ok == true;
  } catch (_) {
    return false;
  }
}

/// Chip label: prefer native [isActive] (live A2DP/headphones/speaker).
final outputDeviceProvider = StreamProvider<OutputDevice>((ref) async* {
  OutputDevice resolve(List<OutputDevice> listed, OutputKind sessionKind) {
    final active = listed.where((d) => d.isActive).firstOrNull;
    if (active != null) return active;

    // Native had no flag — align with audio_session, prefer real list rows.
    final liveBt = listed.where(
      (d) =>
          d.kind == OutputKind.bluetooth && !(d.id?.startsWith('bt:') ?? false),
    ).firstOrNull;
    if (sessionKind == OutputKind.bluetooth && liveBt != null) return liveBt;

    final byKind = listed.where((d) => d.kind == sessionKind).firstOrNull;
    if (byKind != null && !(byKind.id?.startsWith('bt:') ?? false)) {
      return byKind;
    }
    return _fallbackDevice(sessionKind);
  }

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  Future<OutputDevice> current() async {
    final listed = await listAudioOutputs();
    final kind = _kindOf(await session.getDevices());
    return resolve(listed, kind);
  }

  yield await current();
  await for (final _ in session.devicesChangedEventStream) {
    yield await current();
  }
});

/// Snapshot list for the Output sheet (refresh on open / after select).
final audioOutputsProvider =
    FutureProvider.autoDispose<List<OutputDevice>>((ref) async {
  ref.watch(outputDeviceProvider);
  return listAudioOutputs();
});
