import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../api/assistant_api.dart';
import '../audio/patient_mic.dart';
import '../audio/platform_tts.dart';
import '../audio/speech_player.dart';
import '../models/care_models.dart';
import '../settings/app_settings.dart';
import '../vision/face_capture.dart';

class AssistantController extends ChangeNotifier {
  AssistantController({required AppSettings settings})
      : _settings = settings,
        _api = AssistantApi(baseUrl: settings.apiBase) {
    _initTts();
  }

  final AppSettings _settings;
  final AssistantApi _api;
  final PatientMic _mic = PatientMic();
  final SpeechPlayer _speaker = SpeechPlayer();
  final FaceCapture _capture = FaceCapture();
  final PlatformTts _tts = getPlatformTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final List<ChatLine> lines = <ChatLine>[];

  bool ttsMuted = false;
  String? currentlySpeakingText;
  bool _sttInitialized = false;
  String _currentTranscript = '';
  bool _turnSubmitted = false;
  String _selectedLocaleId = 'en_IN';
  List<stt.LocaleName> availableLocales = [];

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
  FaceRecognitionResult? lastRecognitionResult;
  VoicePhase voicePhase = VoicePhase.idle;
  String statusText = 'Connecting to the assistant…';
  String? lastHeard;
  String? lastReply;
  String? voiceError;
  String? loadError;
  bool busy = false;
  bool listening = false;
  int navIndex = 0;

  // Unknown-face notification cooldown (60 s between alerts)
  DateTime? _lastUnknownFaceTime;
  final Set<String> _ignoredUnknownSessions = {};
  ThemeMode get themeMode => _settings.themeMode;
  String get apiBase => _api.baseUrl;
  AssistantApi get api => _api;
  String get selectedLocaleId => _selectedLocaleId;
  void setSelectedLocale(String localeId) {
    _selectedLocaleId = localeId;
    _emit();
  }

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
    if (message.isEmpty || active.id.isEmpty) {
      return;
    }
    if (_heardReminderKey != key) {
      _heardReminderKey = key;
      addLine(fromYou: false, text: message);
      if (active.needsSpeech && active.audioBytes != null && !listening && !ttsMuted) {
        statusText = message;
        _emit();
        await speakBytes(active.audioBytes!, text: message);
      }
    }
  }

  void addLine({required bool fromYou, required String text, List<int>? audioBytes}) {
    lines.add(ChatLine(fromYou: fromYou, text: text, audioBytes: audioBytes));
    _emit();
  }

  Future<void> speakBytes(List<int> audioBytes, {String? text}) async {
    if (audioBytes.length < 45) {
      return;
    }
    if (voicePhase == VoicePhase.speaking) {
      await stopSpeaking();
    }
    currentlySpeakingText = text;
    voicePhase = VoicePhase.speaking;
    statusText = 'Speaking';
    _emit();
    try {
      debugPrint('[Assistant] Speaking audio bytes (${audioBytes.length} bytes)');
      await _speaker.playWav(audioBytes);
    } catch (error) {
      currentlySpeakingText = null;
      debugPrint('[Assistant] speakBytes error: $error');
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
    currentlySpeakingText = null;
    if (voicePhase == VoicePhase.speaking) {
      voicePhase = VoicePhase.idle;
      statusText = 'Online and ready';
      _emit();
    }
  }

  Future<void> replayLine(ChatLine line) async {
    if (line.audioBytes != null && line.audioBytes!.length >= 45) {
      await speakBytes(line.audioBytes!, text: line.text);
    } else {
      await speakText(line.text);
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

  Future<void> _initTts() async {
    try {
      await _tts.init(
        onStart: () {
          debugPrint('[TTS] Started speech');
          if (!_alive) return;
          voicePhase = VoicePhase.speaking;
          statusText = 'Speaking';
          _emit();
        },
        onComplete: () {
          debugPrint('[TTS] Completed speech');
          if (!_alive) return;
          currentlySpeakingText = null;
          if (voicePhase == VoicePhase.speaking) {
            voicePhase = VoicePhase.idle;
            statusText = 'Online and ready';
          }
          _emit();
        },
        onCancel: () {
          debugPrint('[TTS] Canceled speech');
          if (!_alive) return;
          currentlySpeakingText = null;
          if (voicePhase == VoicePhase.speaking) {
            voicePhase = VoicePhase.idle;
            statusText = 'Online and ready';
          }
          _emit();
        },
        onError: (msg) {
          debugPrint('[TTS] Error reported from engine: $msg');
          if (!_alive) return;
          currentlySpeakingText = null;
          if (voicePhase == VoicePhase.speaking) {
            voicePhase = VoicePhase.idle;
            statusText = 'Online and ready';
          }
          _emit();
        },
      );
    } catch (e) {
      debugPrint('[TTS] _initTts failed: $e');
    }
  }

  Future<bool> initStt() async {
    if (_sttInitialized) return true;
    try {
      debugPrint('[STT] Initializing speech recognition engine...');
      final available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('[STT] Status update: $status');
          if (!_alive) return;
          if (status == 'listening') {
            listening = true;
            voicePhase = VoicePhase.listening;
            statusText = 'Listening — speak now. Tap Stop when finished.';
            _emit();
          } else if (status == 'notListening' || status == 'done' || status == 'doneNoResult') {
            listening = false;
            if (voicePhase == VoicePhase.listening) {
              _finishListeningSession();
            }
          }
        },
        onError: (errorNotification) {
          final errorMsg = errorNotification.errorMsg.toLowerCase();
          debugPrint('[STT] Error notification: $errorMsg (permanent: ${errorNotification.permanent})');
          if (!_alive) return;
          listening = false;
          busy = false;

          if (errorMsg.contains('not-allowed') ||
              errorMsg.contains('permission') ||
              errorMsg.contains('service-not-allowed')) {
            voiceError = 'Microphone permission was denied. Please allow microphone access in your browser.';
          } else if (errorMsg.contains('not supported') ||
              errorMsg.contains('speech_not_supported')) {
            voiceError = 'Speech recognition is not supported in this browser. Please use Google Chrome.';
          } else if (errorMsg.contains('timeout') || errorMsg == 'error_speech_timeout') {
            voiceError = 'Listening timed out. Please tap Talk and speak again.';
          } else if (errorMsg.contains('no-speech') || errorMsg == 'error_no_match') {
            voiceError = 'No speech was detected. Please tap Talk and speak clearly.';
          } else if (errorMsg.contains('audio-capture')) {
            voiceError = 'No microphone was found. Please check your microphone connection.';
          } else if (errorMsg.contains('network')) {
            voiceError = 'Speech recognition network error. Please check your connection.';
          } else if (errorMsg == 'aborted') {
            if (voicePhase == VoicePhase.listening) {
              voicePhase = VoicePhase.idle;
              statusText = 'Online and ready';
              _emit();
            }
            return;
          } else {
            voiceError = 'Could not recognize speech. Please try again.';
          }

          voicePhase = VoicePhase.error;
          statusText = voiceError!;
          _emit();
        },
      );

      _sttInitialized = available;
      debugPrint('[STT] Initialization result: available=$available');
      if (available) {
        try {
          final locales = await _speech.locales();
          availableLocales = locales;
          debugPrint('[STT] Found ${locales.length} speech locales');
          for (final loc in locales) {
            final id = loc.localeId.toLowerCase().replaceAll('_', '-');
            if (id == 'en-in') {
              _selectedLocaleId = loc.localeId;
              break;
            } else if (id.startsWith('en')) {
              _selectedLocaleId = loc.localeId;
            }
          }
        } catch (_) {}
      }
      return available;
    } catch (e) {
      debugPrint('[STT] Initialization exception: $e');
      _sttInitialized = false;
      return false;
    }
  }

  void toggleTtsMute() {
    ttsMuted = !ttsMuted;
    if (ttsMuted) {
      stopSpeaking();
    }
    _emit();
  }

  Future<void> speakText(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    if (currentlySpeakingText == clean && voicePhase == VoicePhase.speaking) {
      debugPrint('[TTS] Already speaking this text, skipping duplicate call');
      return;
    }

    if (voicePhase == VoicePhase.speaking || currentlySpeakingText != null) {
      debugPrint('[TTS] Stopping active speech before starting new speech');
      await stopSpeaking();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    currentlySpeakingText = clean;
    voicePhase = VoicePhase.speaking;
    statusText = 'Speaking';
    _emit();

    try {
      debugPrint('[TTS] Speaking text turn (${clean.length} chars)');
      await _tts.speak(clean);
    } catch (e) {
      debugPrint('[TTS] speakText exception: $e');
      currentlySpeakingText = null;
      if (voicePhase == VoicePhase.speaking) {
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
      }
      _emit();
    }
  }

  Future<void> stopSpeaking() async {
    final wasSpeaking = voicePhase == VoicePhase.speaking || currentlySpeakingText != null;
    currentlySpeakingText = null;
    if (wasSpeaking) {
      debugPrint('[TTS] Stopping active speech');
      try {
        await _tts.stop();
      } catch (_) {}
      try {
        await _speaker.stop();
      } catch (_) {}
      if (voicePhase == VoicePhase.speaking) {
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
        _emit();
      }
    }
  }

  Future<void> sendTextTurn(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty || busy) {
      return;
    }
    if (voicePhase == VoicePhase.speaking) {
      await stopSpeaking();
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
        addLine(fromYou: false, text: turn.replyText, audioBytes: turn.audioBytes);
        if (!ttsMuted) {
          if (turn.audioBytes.isNotEmpty) {
            await speakBytes(turn.audioBytes, text: turn.replyText);
          } else {
            await speakText(turn.replyText);
          }
        }
      }
      await refreshOverview();
      busy = false;
      if (voicePhase != VoicePhase.error && voicePhase != VoicePhase.speaking) {
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
      }
      _emit();
    } catch (e) {
      debugPrint('[TextTurn] Error sending text: $e');
      busy = false;
      voicePhase = VoicePhase.error;
      voiceError = 'I could not send that message. Please try again.';
      statusText = voiceError!;
      _emit();
    }
  }

  Future<void> onTalkPressed() async {
    if (voicePhase == VoicePhase.speaking) {
      await stopSpeaking();
      return;
    }

    if (listening) {
      debugPrint('[STT] User tapped Stop during listening');
      listening = false;
      try {
        await _speech.stop();
      } catch (_) {}
      await _finishListeningSession();
      return;
    }

    if (busy) {
      return;
    }

    voiceError = null;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        voicePhase = VoicePhase.error;
        voiceError = 'Microphone permission is needed to talk.';
        statusText = voiceError!;
        _emit();
        return;
      }
    }

    if (!_sttInitialized) {
      statusText = 'Initializing microphone...';
      _emit();
      final available = await initStt();
      if (!available) {
        voicePhase = VoicePhase.error;
        voiceError = 'Speech recognition is not available in this browser. Please use Chrome.';
        statusText = voiceError!;
        _emit();
        return;
      }
    }

    _currentTranscript = '';
    _turnSubmitted = false;
    listening = true;
    voicePhase = VoicePhase.listening;
    statusText = 'Listening — speak now. Tap Stop when finished.';
    _emit();

    try {
      debugPrint('[STT] Starting listen (locale: $_selectedLocaleId)');
      await _speech.listen(
        onResult: (result) {
          if (!_alive) return;
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _currentTranscript = words;
            lastHeard = words;
            statusText = 'Hearing: "$words"';
            _emit();
          }
          if (result.finalResult && words.isNotEmpty) {
            debugPrint('[STT] Final result recognized (${words.split(" ").length} words)');
            _finishListeningSession();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _selectedLocaleId,
          cancelOnError: false,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
    } catch (e) {
      debugPrint('[STT] Listen exception: $e');
      listening = false;
      voicePhase = VoicePhase.error;
      voiceError = 'Failed to start listening: $e';
      statusText = voiceError!;
      _emit();
    }
  }

  Future<void> _finishListeningSession() async {
    if (_turnSubmitted) return;
    final transcript = _currentTranscript.trim();
    listening = false;

    if (transcript.isEmpty) {
      debugPrint('[STT] Listening finished with empty transcript');
      voicePhase = VoicePhase.idle;
      voiceError = 'I couldn\'t hear any words. Please try again.';
      statusText = voiceError!;
      _emit();
      return;
    }

    _turnSubmitted = true;
    debugPrint('[STT] Submitting recognized voice turn (${transcript.split(" ").length} words)');
    await sendTextTurn(transcript);
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
      List<int>? audioBytes;
      if (kIsWeb) {
        try {
          if (path.startsWith('blob:') || path.startsWith('http')) {
            final res = await http.get(Uri.parse(path));
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              audioBytes = res.bodyBytes;
            }
          }
        } catch (e) {
          debugPrint('[Voice] Failed to fetch recorded web blob: $e');
        }
      } else {
        final file = File(path);
        if (file.existsSync()) {
          audioBytes = await file.readAsBytes();
        }
      }
      if (audioBytes == null || audioBytes.isEmpty) {
        debugPrint('[Voice] No audio captured or empty bytes');
        busy = false;
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
        _emit();
        return;
      }
      final turn = await _api.sendAudioBytes(audioBytes);
      lastHeard = turn.transcript;
      lastReply = turn.replyText;
      if (turn.transcript.trim().isNotEmpty) {
        addLine(fromYou: true, text: turn.transcript);
      }
      if (turn.replyText.trim().isNotEmpty) {
        addLine(fromYou: false, text: turn.replyText, audioBytes: turn.audioBytes);
        if (!ttsMuted) {
          if (turn.audioBytes.isNotEmpty) {
            await speakBytes(turn.audioBytes, text: turn.replyText);
          } else {
            await speakText(turn.replyText);
          }
        }
      }
      await refreshOverview();
      busy = false;
      if (voicePhase != VoicePhase.error && voicePhase != VoicePhase.speaking) {
        voicePhase = VoicePhase.idle;
        statusText = 'Online and ready';
      }
      _emit();
    } catch (e) {
      debugPrint('[Voice] stopAndSend error: $e');
      busy = false;
      listening = false;
      voicePhase = VoicePhase.error;
      voiceError = "I didn't quite hear that. Could you please say it again?";
      statusText = voiceError!;
      _emit();
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
        if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
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
      lastRecognitionResult = result;
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

  // ---------------------------------------------------------------------------
  // Unknown-face notification cooldown
  // ---------------------------------------------------------------------------

  bool get shouldNotifyUnknownFace {
    if (lastFace == null || lastFace!.recognized) return false;
    if (_ignoredUnknownSessions.contains('session')) return false;
    final last = _lastUnknownFaceTime;
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >= 60;
  }

  void acknowledgeUnknownFace() {
    _lastUnknownFaceTime = DateTime.now();
    _emit();
  }

  void ignoreUnknownFace() {
    _ignoredUnknownSessions.add('session');
    _lastUnknownFaceTime = DateTime.now();
    _emit();
  }

  // ---------------------------------------------------------------------------
  // People CRUD
  // ---------------------------------------------------------------------------

  Future<void> createPerson({
    required String name,
    required String relationship,
    String notes = '',
  }) async {
    await _api.createPerson(name: name, relationship: relationship, notes: notes);
    _emit();
  }

  Future<void> updatePerson({
    required String id,
    required String name,
    required String relationship,
    String notes = '',
  }) async {
    await _api.updatePerson(id: id, name: name, relationship: relationship, notes: notes);
    _emit();
  }

  Future<void> deletePerson(String id) async {
    await _api.deletePerson(id);
    _emit();
  }

  Future<void> deletePersonFace(String id) async {
    await _api.deletePersonFace(id);
    _emit();
  }

  Future<FaceRecognitionResult> registerFaceMultiSample({
    required List<List<int>> imagesBytesList,
    required String name,
    String personId = '',
    String relationship = '',
    String notes = '',
  }) async {
    final result = await _api.registerFaceMultiSample(
      imagesBytesList: imagesBytesList,
      name: name,
      personId: personId,
      relationship: relationship,
      notes: notes,
    );
    lastRecognitionResult = result;
    _emit();
    return result;
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
    _speech.stop();
    _tts.dispose();
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
