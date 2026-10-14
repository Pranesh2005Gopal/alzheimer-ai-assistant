import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/assistant_api.dart';
import '../audio/patient_mic.dart';
import '../audio/speech_player.dart';
import '../models/care_models.dart';
import '../settings/app_settings.dart';
import '../vision/face_capture.dart';

class AssistantController extends ChangeNotifier {
  AssistantController({required AppSettings settings})
      : _settings = settings,
        _api = AssistantApi(baseUrl: settings.apiBase);

  final AppSettings _settings;
  final AssistantApi _api;
  final PatientMic _mic = PatientMic();
  final SpeechPlayer _speaker = SpeechPlayer();
  final FaceCapture _capture = FaceCapture();
  final List<ChatLine> lines = <ChatLine>[];

  Timer? _overviewTimer;
  bool _alive = true;
  bool _sending = false;
  String? _recordingPath;
  String? _heardReminderKey;
  List<int>? blockedAudio;

  HealthStatus? health;
  OverviewData? overview;
  CameraSnapshot camera = CameraSnapshot(availability: CameraAvailability.unknown);
  FaceEvent? lastFace;
  VoicePhase voicePhase = VoicePhase.idle;
  String statusText = 'Connecting to the assistant…';
  String? lastHeard;
  String? lastReply;
  String? voiceError;
  String? loadError;
  bool busy = false;
  bool listening = false;
  int navIndex = 0;
  ThemeMode get themeMode => _settings.themeMode;
  String get apiBase => _api.baseUrl;
  AssistantApi get api => _api;

  Future<void> refresh() async {
    await refreshOverview();
  }

  AssistantLink get link {
    if (health == null && loadError == null) {
      return AssistantLink.initializing;
    }
    return health?.link ?? AssistantLink.offline;
  }

  String get patientName {
    final fromOverview = overview?.patientName.trim() ?? '';
    if (fromOverview.isNotEmpty) {
      return fromOverview;
    }
    return health?.patient.trim() ?? '';
  }

  Future<void> start() async {
    await refreshAll();
    await probeCamera();
    _overviewTimer?.cancel();
    _overviewTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (listening || busy) {
        return;
      }
      refreshOverview();
      refreshHealth();
    });
  }

  Future<void> refreshAll() async {
    await Future.wait([refreshHealth(), refreshOverview(), probeCamera()]);
  }

  Future<void> refreshHealth() async {
    final next = await _api.health();
    if (!_alive) {
      return;
    }
    health = next;
    if (!next.reachable) {
      loadError = next.message;
      if (voicePhase == VoicePhase.idle) {
        statusText = 'Assistant is offline';
      }
    } else if (next.link == AssistantLink.degraded) {
      loadError = 'The assistant API is up, but Llama/Ollama is unavailable.';
      if (voicePhase == VoicePhase.idle) {
        statusText = 'Assistant is available with limited wording';
      }
    } else if (voicePhase == VoicePhase.idle) {
      loadError = null;
      statusText = 'Online and ready';
    }
    _emit();
  }

  Future<void> refreshOverview() async {
    try {
      final data = await _api.overview();
      if (!_alive) {
        return;
      }
      overview = data;
      if (health?.reachable == true) {
        loadError = null;
      }
      _emit();
      await _maybeSpeakDueReminder(data.activeReminder);
    } catch (error) {
      if (!_alive) {
        return;
      }
      loadError = 'Could not load dashboard data from $_api.baseUrl';
      _emit();
    }
  }

  Future<void> probeCamera() async {
    camera = await _capture.probe();
    if (_alive) {
      _emit();
    }
  }

  Future<void> _maybeSpeakDueReminder(ReminderItem? active) async {
    if (active == null) {
      return;
    }
    final message = active.message ?? '';
    final key = '${active.id}|${active.time}';
    if (message.isEmpty) {
      return;
    }
    if (_heardReminderKey != key) {
      _heardReminderKey = key;
      addLine(fromYou: false, text: message);
    }
    if (active.needsSpeech && active.audioBytes != null && !listening) {
      statusText = message;
      _emit();
      await speakBytes(active.audioBytes!);
    }
  }

  void addLine({required bool fromYou, required String text}) {
    lines.add(ChatLine(fromYou: fromYou, text: text));
    _emit();
  }

  Future<void> speakBytes(List<int> audioBytes) async {
    if (audioBytes.length < 45) {
      return;
    }
    voicePhase = VoicePhase.speaking;
    statusText = 'Speaking';
    _emit();
    try {
      await _speaker.playWav(audioBytes);
    } catch (error) {
      if (error.toString().contains('NotAllowedError') || error.toString().contains('play() failed')) {
        blockedAudio = audioBytes;
        statusText = 'Audio blocked by the browser. Tap Play to hear the reply.';
        voiceError = statusText;
      } else {
        voiceError = 'Speech playback failed. $error';
        statusText = voiceError!;
        voicePhase = VoicePhase.error;
      }
      _emit();
      return;
    }
    if (voicePhase == VoicePhase.speaking) {
      voicePhase = VoicePhase.idle;
      statusText = 'Online and ready';
      _emit();
    }
  }

  Future<void> playBlockedAudio() async {
    final audio = blockedAudio;
    if (audio == null) {
      return;
    }
    blockedAudio = null;
    await speakBytes(audio);
  }

  Future<void> sendTextTurn(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty || busy) {
      return;
    }
    addLine(fromYou: true, text: cleaned);
    busy = true;
    voicePhase = VoicePhase.processing;
    statusText = 'Thinking';
    _emit();
    try {
      final turn = await _api.sendText(cleaned);
      lastHeard = turn.transcript.isEmpty ? cleaned : turn.transcript;
      lastReply = turn.replyText;
      if (turn.replyText.trim().isNotEmpty) {
        addLine(fromYou: false, text: turn.replyText);
        await speakBytes(turn.audioBytes);
      }
      await refreshOverview();
      busy = false;
      if (voicePhase != VoicePhase.error) {
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
      }
      _emit();
    } catch (_) {
      busy = false;
      voicePhase = VoicePhase.error;
      voiceError = 'I could not send that message. Please try again.';
      statusText = voiceError!;
      addLine(fromYou: false, text: voiceError!);
    }
  }

  Future<void> onTalkPressed() async {
    if (listening) {
      await stopAndSend();
      return;
    }
    if (busy) {
      return;
    }
    voiceError = null;
    if (Platform.isAndroid || Platform.isIOS) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        voicePhase = VoicePhase.error;
        voiceError = 'Microphone permission is needed to talk.';
        statusText = voiceError!;
        _emit();
        return;
      }
    }
    final path = await recordingPath();
    try {
      await _mic.start(
        path: path,
        onLevel: (status) {
          if (!_alive || !listening) {
            return;
          }
          statusText = status;
          _emit();
        },
      );
      listening = true;
      busy = true;
      voicePhase = VoicePhase.listening;
      statusText = 'Listening — you can pause. Press Stop when you are finished.';
      _recordingPath = path;
      _emit();
    } catch (_) {
      busy = false;
      listening = false;
      voicePhase = VoicePhase.error;
      voiceError = 'The microphone is not ready. Check permissions and try again.';
      statusText = voiceError!;
      addLine(fromYou: false, text: 'I could not use the microphone. Please try again.');
    }
  }

  Future<void> stopAndSend() async {
    if (_sending) {
      return;
    }
    _sending = true;
    try {
      final recorded = await _mic.stop();
      final path = recorded ?? _recordingPath;
      listening = false;
      voicePhase = VoicePhase.processing;
      statusText = 'Thinking';
      _emit();
      if (path == null) {
        busy = false;
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
        _emit();
        return;
      }
      final file = File(path);
      if (!file.existsSync()) {
        busy = false;
        voicePhase = VoicePhase.error;
        voiceError = "I didn't quite hear that. Please try again.";
        statusText = voiceError!;
        addLine(fromYou: false, text: voiceError!);
        return;
      }
      final turn = await _api.sendAudio(file);
      lastHeard = turn.transcript;
      lastReply = turn.replyText;
      if (turn.transcript.isNotEmpty) {
        addLine(fromYou: true, text: turn.transcript);
      }
      if (turn.replyText.trim().isNotEmpty) {
        addLine(fromYou: false, text: turn.replyText);
        await speakBytes(turn.audioBytes);
      }
      await refreshOverview();
      busy = false;
      if (voicePhase != VoicePhase.error) {
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
      }
      _emit();
    } catch (_) {
      busy = false;
      listening = false;
      voicePhase = VoicePhase.error;
      voiceError = "I didn't quite hear that. Could you please say it again?";
      statusText = voiceError!;
      addLine(fromYou: false, text: voiceError!);
    } finally {
      _sending = false;
    }
  }

  Future<void> recognizeFace({bool offerRegister = true}) async {
    if (busy) {
      return;
    }
    busy = true;
    statusText = 'Looking at the camera...';
    _emit();
    try {
      File? photo;
      try {
        photo = await _capture.capturePhoto();
      } catch (error) {
        camera = CameraSnapshot(
          availability: CameraAvailability.error,
          detail: '$error',
          lastError: '$error',
        );
        if (!Platform.isAndroid && !Platform.isIOS) {
          statusText = 'Trying the computer camera through the assistant…';
          _emit();
          photo = null;
        } else {
          rethrow;
        }
      }
      statusText = 'Scanning face...';
      _emit();
      final result = photo == null
          ? await _api.recognizeFromCamera()
          : await _api.recognizeFace(await photo.readAsBytes());
      lastFace = FaceEvent(
        recognized: result.recognized,
        message: result.message,
        personName: result.recognized ? result.personName : '',
        at: DateTime.now(),
      );
      addLine(fromYou: false, text: result.message);
      await speakBytes(result.audioBytes);
      await refreshOverview();
      if (!result.recognized && photo != null && offerRegister) {
        pendingRegisterPhoto = photo;
      } else {
        pendingRegisterPhoto = null;
      }
    } catch (error) {
      voiceError = 'Camera error: $error';
      statusText = voiceError!;
      addLine(fromYou: false, text: voiceError!);
    } finally {
      busy = false;
      if (voicePhase != VoicePhase.speaking) {
        voicePhase = VoicePhase.idle;
      }
      if (_alive) {
        _emit();
      }
    }
  }

  File? pendingRegisterPhoto;

  Future<List<KnownPerson>> peopleForRegistration() {
    return _api.listPeople();
  }

  Future<void> registerPendingFace(KnownPerson person) async {
    final photo = pendingRegisterPhoto;
    if (photo == null) {
      return;
    }
    busy = true;
    statusText = 'Remembering this face...';
    _emit();
    try {
      final registered = await _api.registerFace(
        imageBytes: await photo.readAsBytes(),
        name: person.name,
        personId: person.id,
        relationship: person.relationship,
      );
      pendingRegisterPhoto = null;
      lastFace = FaceEvent(
        recognized: true,
        message: registered.message,
        personName: registered.personName,
        at: DateTime.now(),
      );
      addLine(fromYou: false, text: registered.message);
      await speakBytes(registered.audioBytes);
      await refreshOverview();
    } catch (_) {
      addLine(fromYou: false, text: 'I could not save that face. Please try again.');
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> createReminder({
    required String title,
    required TimeOfDay time,
    required String kind,
    String frequency = 'once',
    String notes = '',
  }) async {
    final now = DateTime.now();
    final when = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    await _api.createReminder(
      title: title,
      timeIso: when.toIso8601String().split('.').first,
      kind: kind,
      frequency: frequency,
      medicationName: kind == 'medication' ? title : null,
      notes: notes,
    );
    await refreshOverview();
  }

  Future<void> completeReminder(String id) async {
    await _api.completeReminder(id);
    await refreshOverview();
  }

  Future<Map<String, dynamic>> loadMemory() => _api.memory();

  Future<void> addMemoryNote(String text) async {
    await _api.addMemoryNote(text);
    await refreshOverview();
  }

  Future<List<ActivityItem>> loadActivity() => _api.activity();

  Future<List<ConversationTurnItem>> loadConversation() => _api.conversation();

  Future<List<AppointmentItem>> loadAppointments() => _api.listAppointments();

  Future<void> saveApiBase(String value) async {
    _settings.apiBase = value.trim();
    _api.updateBaseUrl(_settings.apiBase);
    await _settings.save();
    health = null;
    overview = null;
    loadError = null;
    statusText = 'Connecting to the assistant…';
    _emit();
    await refreshAll();
  }

  Future<void> saveTheme(ThemeMode mode) async {
    _settings.themeMode = mode;
    await _settings.save();
    _emit();
  }

  Future<void> savePreferredName(String name) async {
    await _api.setPreferredName(name);
    await refreshAll();
  }

  void selectNav(int index) {
    navIndex = index;
    _emit();
  }

  void _emit() {
    if (_alive) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _overviewTimer?.cancel();
    _mic.dispose();
    _speaker.dispose();
    super.dispose();
  }
}

class AssistantScope extends InheritedNotifier<AssistantController> {
  const AssistantScope({
    super.key,
    required AssistantController controller,
    required super.child,
  }) : super(notifier: controller);

  static AssistantController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AssistantScope>();
    assert(scope != null, 'AssistantScope not found');
    return scope!.notifier!;
  }
}
