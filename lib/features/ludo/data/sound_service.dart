import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

enum Sfx { dice, move, enter, capture, finish, win }

/// Sound effects through flutter_soloud (a native game-audio engine).
///
/// Every effect is decoded into memory once ([warmUp]). [play] then just asks
/// the native mixer to start another voice: a synchronous FFI call with no
/// platform channel and no per-call work on the UI thread, and any number of
/// plays can overlap. That is what keeps the per-cell step tick from causing
/// frame drops on Android.
///
/// Every failure is swallowed: a missing audio backend must never stop a game.
class LudoSound {
  bool enabled = true;

  final Map<Sfx, AudioSource> _sources = {};
  Future<void>? _warm;

  SoLoud get _engine => SoLoud.instance;

  /// Starts the engine and decodes every effect, in the background.
  Future<void> warmUp() => _warm ??= _load();

  Future<void> _load() async {
    try {
      // init() is not idempotent: calling it again would unload everything.
      if (!_engine.isInitialized) await _engine.init();
      for (final sfx in Sfx.values) {
        _sources[sfx] = await _engine.loadAsset('assets/sounds/${sfx.name}.wav');
      }
    } catch (e) {
      debugPrint('Sound unavailable: $e');
      _warm = null; // try again on the next play
    }
  }

  Future<void> play(Sfx sfx) async {
    if (!enabled) return;
    try {
      // Normally already loaded, so this does not wait at all.
      if (_sources.length < Sfx.values.length) await warmUp();
      final source = _sources[sfx];
      if (source == null || !_engine.isInitialized) return;
      _engine.play(source);
    } catch (_) {}
  }

  void dispose() {
    _sources.clear();
    _warm = null;
    try {
      if (_engine.isInitialized) _engine.deinit();
    } catch (_) {}
  }
}
