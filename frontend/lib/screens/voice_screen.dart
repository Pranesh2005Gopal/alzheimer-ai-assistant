import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final controller = AssistantScope.of(context);
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
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                  child: Column(
                    children: [
                      Text('Voice Assistant', style: Theme.of(context).textTheme.headlineSmall),
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
                        ErrorState(message: controller.voiceError!, onRetry: controller.onTalkPressed),
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
              const SizedBox(height: 12),

              // Conversation history
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: controller.lines.isEmpty
                        ? const EmptyState(
                            title: 'No conversation yet',
                            message: 'Press Talk and speak. Your words and the assistant\'s replies will appear here.',
                            icon: Icons.chat_bubble_outline,
                          )
                        : ListView.builder(
                            controller: _scroll,
                            itemCount: controller.lines.length,
                            itemBuilder: (context, index) {
                              final line = controller.lines[index];
                              return _ChatBubble(line: line);
                            },
                          ),
                  ),
                ),
              ),

              // Text input
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.viewInsetsOf(context).bottom + 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: 'Or type a message…',
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        ),
                        onSubmitted: (_) => _sendText(controller),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: controller.busy ? null : () => _sendText(controller),
                      icon: const Icon(Icons.send_rounded),
                      style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
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

  Future<void> _sendText(AssistantController controller) async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    await controller.sendTextTurn(text);
  }
}

class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.phase});

  final VoicePhase phase;

  @override
  Widget build(BuildContext context) {
    if (phase == VoicePhase.processing || phase == VoicePhase.speaking) {
      return const SizedBox(
        height: 4,
        child: LinearProgressIndicator(),
      );
    }
    return const SizedBox(height: 4);
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.line});

  final ChatLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: line.fromYou ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: line.fromYou ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: line.fromYou ? const Radius.circular(18) : const Radius.circular(4),
              bottomRight: line.fromYou ? const Radius.circular(4) : const Radius.circular(18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.fromYou ? 'You' : 'Assistant',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(line.text, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
