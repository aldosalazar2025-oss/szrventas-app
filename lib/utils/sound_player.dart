import 'package:audioplayers/audioplayers.dart';

/// Reproduce sonidos POS sin que el player se destruya antes de sonar.
class SoundPlayer {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> ping() => _play('sounds/ping.mp3');

  static Future<void> caja() => _play('sounds/caja.mp3');

  static Future<void> _play(String asset) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }
}
