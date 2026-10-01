package com.example.sonora_flutter

import com.ryanheise.audioservice.AudioServiceActivity

/**
 * Shares a single Flutter engine with the audio_service background service so
 * the media notification and the UI observe the same [SonoraAudioHandler].
 */
class MainActivity : AudioServiceActivity()
