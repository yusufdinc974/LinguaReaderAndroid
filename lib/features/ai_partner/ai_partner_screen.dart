import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/pixel_card.dart';
import '../../providers/auth_provider.dart';
import '../subscription/paywall_screen.dart';
import 'widgets/chat_tab.dart';
import 'widgets/history_tab.dart';

class AiPartnerScreen extends ConsumerWidget {
  const AiPartnerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremiumAsync = ref.watch(isPremiumProvider);

    return isPremiumAsync.when(
      loading: () => Scaffold(
        appBar: _buildAppBar(context),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (_, __) => Scaffold(
        appBar: _buildAppBar(context),
        body: const _PremiumGateView(),
      ),
      data: (isPremium) => isPremium
          ? const _AiPartnerContent()
          : Scaffold(
              appBar: _buildAppBar(context),
              body: const _PremiumGateView(),
            ),
    );
  }

  AppBar _buildAppBar(BuildContext context) => AppBar(
        title: Row(
          children: const [
            Icon(Icons.auto_awesome, size: 18, color: AppColors.secondary),
            SizedBox(width: 8),
            Text('AI Language Partner'),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Content (premium users)
// ─────────────────────────────────────────────────────────────────────────────

class _AiPartnerContent extends StatelessWidget {
  const _AiPartnerContent();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: const [
              Icon(Icons.auto_awesome, size: 18, color: AppColors.secondary),
              SizedBox(width: 8),
              Text('AI Language Partner'),
            ],
          ),
          bottom: TabBar(
            labelColor: AppColors.primaryLight,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(
                icon: Icon(Icons.chat_bubble_outline, size: 18),
                text: 'Chat',
                iconMargin: EdgeInsets.only(bottom: 4),
              ),
              Tab(
                icon: Icon(Icons.history_edu_outlined, size: 18),
                text: 'History',
                iconMargin: EdgeInsets.only(bottom: 4),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [
            ChatTab(),
            HistoryTab(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium gate (free users)
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumGateView extends StatelessWidget {
  const _PremiumGateView();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Fox animation
            const FoxSpriteAnimator(
              animation: FoxAnimation.yawnSouth,
              size: 100,
            ),
            const SizedBox(height: 24),

            // Title
            const Text(
              'AI Language Partner',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Practice conversations with an AI tutor that gently corrects your mistakes and builds your skills every day.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Feature highlights
            PixelCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: const [
                  _FeatureRow(
                    icon: Icons.chat_bubble_rounded,
                    color: AppColors.secondary,
                    title: 'Real-time Chat',
                    subtitle:
                        'Converse in any language — the AI adapts to you.',
                  ),
                  SizedBox(height: 16),
                  _FeatureRow(
                    icon: Icons.auto_fix_high_rounded,
                    color: AppColors.warning,
                    title: 'Instant Fixements',
                    subtitle:
                        'Corrections appear right after each message with clear explanations.',
                  ),
                  SizedBox(height: 16),
                  _FeatureRow(
                    icon: Icons.history_edu_rounded,
                    color: AppColors.primaryLight,
                    title: 'Mistake History',
                    subtitle:
                        'Every correction is saved, searchable, and annotatable.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // CTA button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PaywallScreen(),
                  ),
                ),
                icon: const Icon(Icons.star_rounded, size: 20),
                label: const Text('Unlock Premium'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Cancel anytime. Subscriptions auto-renew until cancelled.',
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
