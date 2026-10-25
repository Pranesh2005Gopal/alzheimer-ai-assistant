/// Public landing page shown before login or registration.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_widgets.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.onLogin,
    required this.onRegister,
    this.onGetStarted,
  });

  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback? onGetStarted;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scrollController = ScrollController();
  final _featuresKey = GlobalKey();
  final _aboutKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) {
      return;
    }
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = AppBreakpoints.isCompact(width);

    return Scaffold(
      body: Column(
        children: [
          _LandingNav(
            compact: compact,
            onLogoTap: () => _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
            ),
            onLogin: widget.onLogin,
            onRegister: widget.onRegister,
            onFeatures: () => _scrollTo(_featuresKey),
            onAbout: () => _scrollTo(_aboutKey),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  _HeroSection(
                    compact: compact,
                    onGetStarted: widget.onGetStarted ?? widget.onRegister,
                    onLearnMore: () => _scrollTo(_featuresKey),
                  ),
                  _AboutSection(key: _aboutKey, compact: compact),
                  _FeaturesSection(key: _featuresKey, compact: compact),
                  _LandingFooter(
                    compact: compact,
                    onLogin: widget.onLogin,
                    onRegister: widget.onRegister,
                    onAbout: () => _scrollTo(_aboutKey),
                    onFeatures: () => _scrollTo(_featuresKey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingNav extends StatelessWidget {
  const _LandingNav({
    required this.compact,
    required this.onLogoTap,
    required this.onLogin,
    required this.onRegister,
    required this.onFeatures,
    required this.onAbout,
  });

  final bool compact;
  final VoidCallback onLogoTap;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onFeatures;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      elevation: 0,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 32, vertical: 10),
        child: SafeArea(
          bottom: false,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            children: [
              InkWell(
                onTap: onLogoTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_hospital_rounded, size: 32, color: cs.primary),
                      const SizedBox(width: 10),
                      Text(
                        'AI Memory Care',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!compact) ...[
                    TextButton(onPressed: onAbout, child: const Text('About')),
                    TextButton(onPressed: onFeatures, child: const Text('Features')),
                  ],
                  OutlinedButton(
                    onPressed: onLogin,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: const Text('Login'),
                  ),
                  FilledButton(
                    onPressed: onRegister,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: const Text('Register'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.compact,
    required this.onGetStarted,
    required this.onLearnMore,
  });

  final bool compact;
  final VoidCallback onGetStarted;
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxWidth = compact ? 720.0 : 1120.0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.12),
              Theme.of(context).scaffoldBackgroundColor,
              cs.secondary.withValues(alpha: 0.10),
            ],
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 20 : 40,
          vertical: compact ? 40 : 72,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                const StatusBadge(
                  label: 'Personalized voice care',
                  tone: StatusTone.info,
                  icon: Icons.record_voice_over_outlined,
                ),
                const SizedBox(height: 20),
                Text(
                  'A Smarter, More Caring Voice Assistant',
                  textAlign: compact ? TextAlign.start : TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(
                    'AI Memory Care helps patients and caregivers through spoken conversation, '
                    'personalized answers, reminders, memory support, and familiar-face recognition — '
                    'all in one calm, private assistant.',
                    textAlign: compact ? TextAlign.start : TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.78),
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: compact ? WrapAlignment.start : WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onGetStarted,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Get Started'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onLearnMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('Learn More'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 20 : 40,
        vertical: compact ? 36 : 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: AppCard(
            padding: EdgeInsets.all(compact ? 22 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'About AI Memory Care',
                  icon: Icons.favorite_outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'AI Memory Care is a local voice assistant designed for people living with '
                  'memory challenges and the caregivers who support them. Patients can speak '
                  'naturally; the assistant replies out loud, keeps track of reminders and '
                  'appointments, and helps retrieve personal details when they are needed.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Caregivers can sign in with a caregiver account to review tasks, memories, '
                  'and daily support tools. The experience stays personal: profiles, private '
                  'information, and remembered people belong to the signed-in user.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureItem {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({super.key, required this.compact});

  final bool compact;

  static const features = [
    _FeatureItem(
      icon: Icons.mic_none_rounded,
      title: 'Voice-based interaction',
      description:
          'Talk with a large Talk button. Speech is transcribed, understood, and answered out loud so the conversation stays hands-free.',
    ),
    _FeatureItem(
      icon: Icons.person_search_outlined,
      title: 'Personalized information',
      description:
          'The assistant retrieves profile details, private notes, and daily context that belong to the signed-in patient or caregiver.',
    ),
    _FeatureItem(
      icon: Icons.alarm_outlined,
      title: 'Smart reminders and appointments',
      description:
          'Create, update, complete, and review medication times, appointments, and daily routines from the reminders screen or by voice.',
    ),
    _FeatureItem(
      icon: Icons.auto_stories_outlined,
      title: 'Memory assistance',
      description:
          'Store and recall people, stories, and important facts so the assistant can help when names or details are hard to remember.',
    ),
    _FeatureItem(
      icon: Icons.face_outlined,
      title: 'Face recognition',
      description:
          'Register familiar faces and use the camera to help identify people. Matches are assistance, not a medical diagnosis.',
    ),
    _FeatureItem(
      icon: Icons.family_restroom_outlined,
      title: 'Caregiver support',
      description:
          'Caregiver accounts open a dedicated home with tasks, the assistant, memories, and vision tools for supporting a patient.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final columns = compact ? 1 : (MediaQuery.sizeOf(context).width >= 1024 ? 3 : 2);

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 20 : 40,
        vertical: compact ? 36 : 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Features',
                icon: Icons.grid_view_rounded,
              ),
              const SizedBox(height: 8),
              Text(
                'Tools already available in the application after you sign in.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final spacing = 16.0;
                  final cardWidth = columns == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - spacing * (columns - 1)) / columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final feature in features)
                        SizedBox(
                          width: cardWidth,
                          child: _FeatureCard(feature: feature),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});

  final _FeatureItem feature;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(feature.icon, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(feature.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            feature.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _LandingFooter extends StatelessWidget {
  const _LandingFooter({
    required this.compact,
    required this.onLogin,
    required this.onRegister,
    required this.onAbout,
    required this.onFeatures,
  });

  final bool compact;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onAbout;
  final VoidCallback onFeatures;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: AppColors.ink,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 20 : 40,
        vertical: compact ? 28 : 36,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_hospital_rounded, color: cs.primary.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                  Text(
                    'AI Memory Care',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'A personalized voice assistant for memory support, reminders, and caregiver coordination.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: onAbout,
                    child: const Text('About', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton(
                    onPressed: onFeatures,
                    child: const Text('Features', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton(
                    onPressed: onLogin,
                    child: const Text('Login', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton(
                    onPressed: onRegister,
                    child: const Text('Register', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
