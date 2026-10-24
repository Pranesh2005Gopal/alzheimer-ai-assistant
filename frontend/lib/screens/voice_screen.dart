import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/care_models.dart';
import '../state/assistant_controller.dart';
import '../widgets/app_widgets.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final _scroll = ScrollController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText(AssistantController controller) async {
    if (controller.listening) {
      await controller.onTalkPressed();
    }
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    await controller.sendTextTurn(text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
    final hasTamil = controller.availableLocales.any(
      (l) => l.localeId.toLowerCase().startsWith('ta'),
    );
    final hasEnglish = controller.availableLocales.any(
      (l) => l.localeId.toLowerCase().startsWith('en'),
    );

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        _jump();
        return SafeArea(
          child: Column(
            children: [
              // Top mic + status card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AppCard(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.05),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 48),
                          Text(
                            'Voice Assistant',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (controller.voicePhase == VoicePhase.speaking)
                                IconButton(
                                  tooltip: 'Stop speaking',
                                  icon: const Icon(
                                    Icons.stop_circle_rounded,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: controller.stopSpeaking,
                                ),
                              IconButton(
                                tooltip: controller.ttsMuted
                                    ? 'Unmute voice'
                                    : 'Mute voice',
                                icon: Icon(
                                  controller.ttsMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: controller.ttsMuted
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                                onPressed: controller.toggleTtsMute,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      MicButton(
                        phase: controller.voicePhase,
                        enabled: !(controller.busy && !controller.listening),
                        onPressed: controller.onTalkPressed,
                      ),
                      const SizedBox(height: 12),
                      _PhaseBar(phase: controller.voicePhase),
                      const SizedBox(height: 6),
                      Text(
                        controller.statusText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (controller.voiceError != null) ...[
                        const SizedBox(height: 8),
                        ErrorState(
                          message: controller.voiceError!,
                          onRetry: controller.onTalkPressed,
                        ),
                      ],
                      if (controller.blockedAudio != null) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: controller.playBlockedAudio,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play reply'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Language selector if both Tamil and English are available
              if (hasTamil && hasEnglish)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Language: ',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      DropdownButton<String>(
                        value:
                            controller.selectedLocaleId
                                .toLowerCase()
                                .startsWith('ta')
                            ? 'ta'
                            : 'en',
                        isDense: true,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: 'en',
                            child: Text(
                              'English',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'ta',
                            child: Text(
                              'தமிழ்',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                        onChanged: (lang) {
                          if (lang == null) return;
                          stt.LocaleName? target;
                          if (lang == 'ta') {
                            target = controller.availableLocales.firstWhere(
                              (l) => l.localeId.toLowerCase().startsWith('ta'),
                              orElse: () => controller.availableLocales.first,
                            );
                          } else {
                            target = controller.availableLocales.firstWhere(
                              (l) =>
                                  l.localeId.toLowerCase().contains('en_in') ||
                                  l.localeId.toLowerCase().contains('en-in'),
                              orElse: () =>
                                  controller.availableLocales.firstWhere(
                                    (l) => l.localeId.toLowerCase().startsWith(
                                      'en',
                                    ),
                                    orElse: () =>
                                        controller.availableLocales.first,
                                  ),
                            );
                          }
                          controller.setSelectedLocale(target.localeId);
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 4),

              // Conversation history
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: controller.lines.isEmpty
                        ? const EmptyState(
                            title: 'No conversation yet',
                            message: 'Press Talk or the mic button and speak. Your words and the assistant\'s replies will appear here.',
                            icon: Icons.chat_bubble_outline,
                          )
                        : ListView.builder(
                            controller: _scroll,
                            itemCount: controller.lines.length,
                            itemBuilder: (context, index) {
                              final line = controller.lines[index];
                              return _ChatBubble(
                                line: line,
                                controller: controller,
                              );
                            },
                          ),
                  ),
                ),
              ),

              // Text input with speech-to-text mic button
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.viewInsetsOf(context).bottom + 12,
                ),
                child: Row(
                  children: [
                    // Speech-to-text mic button beside input field
                    IconButton.filledTonal(
                      tooltip: controller.listening
                          ? 'Stop listening'
                          : 'Speak message',
                      onPressed: controller.busy && !controller.listening
                          ? null
                          : controller.onTalkPressed,
                      icon: Icon(
                        controller.listening
                            ? Icons.stop_rounded
                            : Icons.mic_none_rounded,
                        color: controller.listening
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: controller.listening
                            ? Theme.of(context).colorScheme.errorContainer
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: controller.listening
                              ? 'Listening… speak now'
                              : 'Type or speak a message…',
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (_) => _sendText(controller),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: controller.busy
                          ? null
                          : () => _sendText(controller),
                      icon: const Icon(Icons.send_rounded),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(52, 52),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.phase});

  final VoicePhase phase;

  @override
  Widget build(BuildContext context) {
    if (phase == VoicePhase.processing || phase == VoicePhase.speaking) {
      return const SizedBox(height: 4, child: LinearProgressIndicator());
    }
    return const SizedBox(height: 4);
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.line, required this.controller});

  final ChatLine line;
  final AssistantController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAssistant = !line.fromYou;
    final isSpeakingThis =
        isAssistant &&
        controller.voicePhase == VoicePhase.speaking &&
        controller.currentlySpeakingLineId == line.id;

    return Align(
      alignment: line.fromYou ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: line.fromYou
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: line.fromYou
                  ? const Radius.circular(18)
                  : const Radius.circular(4),
              bottomRight: line.fromYou
                  ? const Radius.circular(4)
                  : const Radius.circular(18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line.fromYou ? 'You' : 'Assistant',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (isSpeakingThis) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(line.text, style: Theme.of(context).textTheme.bodyLarge),
              if (isAssistant) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSpeakingThis)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: controller.stopSpeaking,
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text(
                          'Stop',
                          style: TextStyle(fontSize: 12),
                        ),
                      )
                    else
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => controller.replayLine(line),
                        icon: const Icon(Icons.volume_up_outlined, size: 18),
                        label: const Text(
                          'Replay',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
