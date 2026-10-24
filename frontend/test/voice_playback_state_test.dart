import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:patient_assistant/audio/platform_tts.dart';
import 'package:patient_assistant/models/care_models.dart';
import 'package:patient_assistant/settings/app_settings.dart';
import 'package:patient_assistant/state/assistant_controller.dart';

class _FakeTts implements PlatformTts {
  void Function(int playbackId)? onStart;
  void Function(int playbackId)? onComplete;
  void Function(int playbackId)? onCancel;
  void Function(int playbackId, String error)? onError;
  Completer<void>? _playback;
  int _playbackId = 0;
  int speakCount = 0;

  @override
  Future<void> init({
    required void Function(int playbackId) onStart,
    required void Function(int playbackId) onComplete,
    required void Function(int playbackId) onCancel,
    required void Function(int playbackId, String error) onError,
  }) async {
    this.onStart = onStart;
    this.onComplete = onComplete;
    this.onCancel = onCancel;
    this.onError = onError;
  }

  @override
  Future<void> speak(String text, {String? locale, required int playbackId}) {
    speakCount++;
    _playbackId = playbackId;
    onStart!(playbackId);
    _playback = Completer<void>();
    return _playback!.future;
  }

  void finish() {
    onComplete!(_playbackId);
    _playback?.complete();
  }

  void fail() {
    onError!(_playbackId, 'synthetic failure');
    _playback?.complete();
  }

  void completePlayback(int playbackId) => onComplete!(playbackId);

  @override
  Future<void> stop() async {
    onCancel!(_playbackId);
    _playback?.complete();
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AssistantController> controllerFor(_FakeTts tts) async {
    final controller = AssistantController(
      settings: AppSettings(apiBase: 'http://127.0.0.1:19999'),
      tts: tts,
    );
    await Future<void>.delayed(Duration.zero);
    return controller;
  }

  test(
    'identical replies are played as distinct message turns and return idle',
    () async {
      final tts = _FakeTts();
      final controller = await controllerFor(tts);
      final first = controller.addLine(fromYou: false, text: 'Same reply');
      final firstPlay = controller.speakText(first.text, lineId: first.id);
      expect(controller.voicePhase, VoicePhase.speaking);
      expect(controller.currentlySpeakingLineId, first.id);
      tts.finish();
      await firstPlay;

      final second = controller.addLine(fromYou: false, text: 'Same reply');
      final secondPlay = controller.speakText(second.text, lineId: second.id);
      expect(tts.speakCount, 2);
      expect(controller.currentlySpeakingLineId, second.id);
      tts.finish();
      await secondPlay;
      expect(controller.voicePhase, VoicePhase.idle);
      expect(controller.currentlySpeakingLineId, isNull);
    },
  );

  test(
    'controller notifications cannot replay an automatic response',
    () async {
      final tts = _FakeTts();
      final controller = await controllerFor(tts);
      final line = controller.addLine(fromYou: false, text: 'One reply');
      final playback = controller.speakAssistantLine(line, automatic: true);
      controller.addLine(fromYou: true, text: 'A state-only update');
      await controller.speakAssistantLine(line, automatic: true);
      expect(tts.speakCount, 1);
      tts.finish();
      await playback;
      expect(controller.voicePhase, VoicePhase.idle);
    },
  );

  test(
    'stop and speech errors clear the speaking state for later playback',
    () async {
      final tts = _FakeTts();
      final controller = await controllerFor(tts);
      final line = controller.addLine(fromYou: false, text: 'Reply');
      final play = controller.speakText(line.text, lineId: line.id);
      await controller.stopSpeaking();
      await play;
      expect(controller.voicePhase, VoicePhase.idle);

      final failed = controller.speakText(line.text, lineId: line.id);
      tts.fail();
      await failed;
      expect(controller.voicePhase, VoicePhase.idle);
      expect(controller.currentlySpeakingLineId, isNull);
    },
  );

  test(
    'replay and a newer response keep the active message state correct',
    () async {
      final tts = _FakeTts();
      final controller = await controllerFor(tts);
      final first = controller.addLine(
        fromYou: false,
        text: 'A long reply ' * 40,
      );
      final firstPlay = controller.replayLine(first);
      expect(controller.currentlySpeakingLineId, first.id);

      final second = controller.addLine(fromYou: false, text: 'New reply');
      final secondPlay = controller.speakText(second.text, lineId: second.id);
      await firstPlay;
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(controller.currentlySpeakingLineId, second.id);
      tts.completePlayback(1);
      expect(controller.currentlySpeakingLineId, second.id);
      tts.finish();
      await secondPlay;
      expect(controller.voicePhase, VoicePhase.idle);
      expect(tts.speakCount, 2);
    },
  );
}
