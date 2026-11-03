import 'package:flutter/material.dart';

import 'health_status_pill.dart';

/// Full-width header card: connection-health pill + settings button on top
/// (right-aligned), avatar + greeting + subtitle underneath.
///
/// The top actions sit in a Wrap, so on very narrow screens or large font
/// scales they wrap instead of overflowing.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({
    super.key,
    required this.profileName,
    required this.onPillTap,
    required this.onSettingsTap,
  });

  final String profileName;
  final VoidCallback onPillTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Softer tint: blend primaryContainer toward the page surface so the
    // activity cards stay the main focus.
    final cardColor =
        Color.lerp(scheme.surface, scheme.primaryContainer, 0.6)!;

    final name = profileName.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 0,
        // Same default horizontal inset as the activity cards, so edges align.
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: health pill + settings
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    HealthStatusPill(onTap: onPillTap),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      tooltip: 'Settings',
                      color: scheme.onPrimaryContainer,
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surface,
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: onSettingsTap,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Avatar + greeting
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: scheme.surface,
                    child: Text(
                      initial,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, $profileName!',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Bachelor of Science in Computer Science 4A",
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
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