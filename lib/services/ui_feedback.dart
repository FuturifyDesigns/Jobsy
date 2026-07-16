import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// In-app feedback: short success tone + haptics for completions and toasts.
class UiSounds {
  UiSounds._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _assetFailed = false;
  static DateTime? _lastSuccessAt;

  static Future<void> success() async {
    final now = DateTime.now();
    if (_lastSuccessAt != null &&
        now.difference(_lastSuccessAt!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastSuccessAt = now;
    await HapticFeedback.mediumImpact();
    if (_assetFailed) {
      SystemSound.play(SystemSoundType.alert);
      return;
    }
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/ui_success.wav'));
    } catch (_) {
      _assetFailed = true;
      SystemSound.play(SystemSoundType.alert);
    }
  }

  static Future<void> soft() async {
    await HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
  }

  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }
}
