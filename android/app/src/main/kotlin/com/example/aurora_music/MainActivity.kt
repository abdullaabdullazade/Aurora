package com.example.aurora_music

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (instead of FlutterActivity) so just_audio_background /
// audio_service can run a media-style foreground service for background playback.
class MainActivity : AudioServiceActivity()
