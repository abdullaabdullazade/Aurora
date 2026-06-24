import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../state/player_controller.dart';

/// 5-band system equalizer backed by just_audio's AndroidEqualizer.
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});
  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    final eq = ref.read(playerControllerProvider.notifier).equalizer;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: Column(
        children: [
          SwitchListTile(
            value: _enabled,
            activeColor: AppColors.accentBright,
            title: const Text('Enable equalizer'),
            subtitle: const Text('Shape the sound to your taste'),
            onChanged: (v) async {
              await eq.setEnabled(v);
              setState(() => _enabled = v);
            },
          ),
          const Divider(height: 1, color: AppColors.glassStroke),
          Expanded(
            child: FutureBuilder<AndroidEqualizerParameters>(
              future: eq.parameters,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentBright));
                }
                final params = snap.data!;
                return Padding(
                  padding: const EdgeInsets.all(Sp.lg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final band in params.bands)
                        _BandSlider(
                          band: band,
                          min: params.minDecibels,
                          max: params.maxDecibels,
                          enabled: _enabled,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Sp.lg),
            child: Text(
              'Adjusts the actual audio output in real time.',
              style: text.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _BandSlider extends StatefulWidget {
  final AndroidEqualizerBand band;
  final double min;
  final double max;
  final bool enabled;
  const _BandSlider(
      {required this.band,
      required this.min,
      required this.max,
      required this.enabled});

  @override
  State<_BandSlider> createState() => _BandSliderState();
}

class _BandSliderState extends State<_BandSlider> {
  late double _gain = widget.band.gain;

  @override
  Widget build(BuildContext context) {
    final hz = widget.band.centerFrequency;
    final label = hz >= 1000
        ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k'
        : hz.toStringAsFixed(0);
    return Column(
      children: [
        Text('${_gain.toStringAsFixed(1)}dB',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: Sp.sm),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accentBright,
                inactiveTrackColor: AppColors.glassStroke,
                thumbColor: Colors.white,
              ),
              child: Slider(
                min: widget.min,
                max: widget.max,
                value: _gain.clamp(widget.min, widget.max),
                onChanged: widget.enabled
                    ? (v) {
                        setState(() => _gain = v);
                        widget.band.setGain(v);
                      }
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: Sp.sm),
        Text('$label Hz', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
