import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../api/assistant_api.dart';
import '../theme/app_colors.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final AssistantApi _api = AssistantApi();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  String _status = 'Ready';
  bool _busy = false;
  bool _listening = false;
  Map<String, dynamic>? _overview;
  final List<String> _lines = <String>[];
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    try {
      final data = await _api.overview();
      if (!mounted) {
        return;
      }
      setState(() => _overview = data);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = 'Cannot reach assistant');
    }
  }

  Future<void> _onTalkPressed() async {
    if (_listening) {
      await _stopAndSend();
      return;
    }
    if (_busy) {
      return;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        setState(() => _status = 'Microphone permission needed');
        return;
      }
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/patient_turn.wav';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, numChannels: 1, sampleRate: 16000),
        path: path,
      );
      setState(() {
        _listening = true;
        _busy = true;
        _status = 'Listening';
        _recordingPath = path;
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _listening = false;
        _status = 'Microphone not ready';
      });
    }
  }

  Future<void> _stopAndSend() async {
    try {
      final recorded = await _recorder.stop();
      final path = recorded ?? _recordingPath;
      setState(() {
        _listening = false;
        _status = 'Thinking';
      });
      if (path == null) {
        setState(() {
          _busy = false;
          _status = 'Ready';
        });
        return;
      }
      final turn = await _api.sendAudio(File(path));
      setState(() {
        _status = 'Speaking';
        if (turn.transcript.isNotEmpty) {
          _lines.add('You: ${turn.transcript}');
        }
        _lines.add('Assistant: ${turn.replyText}');
      });
      if (turn.audioBytes.isNotEmpty) {
        await _player.play(BytesSource(turn.audioBytes, mimeType: 'audio/wav'));
        await _player.onPlayerComplete.first;
      }
      await _loadOverview();
      setState(() {
        _busy = false;
        _status = 'Ready';
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _listening = false;
        _status = 'Please try again';
        _lines.add('Assistant: I had trouble. Please try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final greeting = overview?['greeting'] as String? ?? 'Hello';
    final dateLabel = overview?['date_label'] as String? ?? '';
    final prompt = overview?['prompt'] as String? ?? 'How can I help?';
    final reminder = overview?['next_reminder'] as Map<String, dynamic>?;
    final appointment = overview?['next_appointment'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                greeting,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.cream,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                dateLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.gold, fontSize: 22),
              ),
              const SizedBox(height: 18),
              Text(
                '🔊  $prompt',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.cream, fontSize: 22),
              ),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: ElevatedButton(
                    onPressed: (_busy && !_listening) ? null : _onTalkPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _listening ? AppColors.mute : AppColors.talk,
                      foregroundColor: AppColors.cream,
                      shape: const CircleBorder(),
                      elevation: 8,
                    ),
                    child: Text(
                      _listening ? 'STOP' : ((_busy) ? _status.toUpperCase() : 'TALK'),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.gold, fontSize: 20),
              ),
              const SizedBox(height: 16),
              _InfoCard(
                icon: '💊',
                title: 'Next medicine',
                body: reminder == null
                    ? 'None stored'
                    : '${reminder['title']} — ${reminder['time']}',
              ),
              const SizedBox(height: 10),
              _InfoCard(
                icon: '📅',
                title: 'Appointment',
                body: appointment == null
                    ? 'None stored'
                    : '${appointment['doctor']}\n${appointment['date']} — ${appointment['time']}',
              ),
              const SizedBox(height: 10),
              const _InfoCard(icon: '👤', title: 'Family', body: 'Arun · Priya · Dr. Kumar'),
              const SizedBox(height: 12),
              const Text(
                'Conversation',
                style: TextStyle(color: AppColors.cream, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListView.builder(
                    itemCount: _lines.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _lines[index],
                          style: const TextStyle(color: AppColors.cream, fontSize: 18, height: 1.3),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Text(
                  body,
                  style: const TextStyle(color: AppColors.cream, fontSize: 20, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
