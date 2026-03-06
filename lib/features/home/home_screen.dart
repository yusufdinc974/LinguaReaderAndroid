import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/database_service.dart';
import '../../services/subscription_service.dart';
import '../reader/reader_screen.dart';
import '../settings/settings_screen.dart';
import '../quiz/quiz_screen.dart';
import '../subscription/paywall_screen.dart';
import '../onboarding/profile_onboarding_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _databaseService = DatabaseService();
  int _wordsToReview = 0;
  List<Map<String, dynamic>> _recentPdfs = [];
  Map<String, dynamic>? _profile;
  Map<String, dynamic> _retention = {};
  bool _isLoading = true;
  bool _isPremium = false;
  bool _isInitialFlowRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_isInitialFlowRunning) return;
    _isInitialFlowRunning = true;

    final profileComplete = await _databaseService.isUserProfileComplete();
    if (!profileComplete && mounted) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => const ProfileOnboardingScreen.force()),
      );
    }

    await _loadData();
    _isInitialFlowRunning = false;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait<dynamic>([
      _databaseService.getWordsToReviewCount(),
      _databaseService.getRecentPdfs(),
      SubscriptionService.isPremium(),
      _databaseService.getUserProfile(),
      _databaseService.getRetentionOverview(),
    ]);

    final count = results[0] as int;
    final recent = results[1] as List<Map<String, dynamic>>;
    final isPremium = results[2] as bool;
    final profile = results[3] as Map<String, dynamic>?;
    final retention = results[4] as Map<String, dynamic>;

    if (mounted) {
      setState(() {
        _wordsToReview = count;
        _recentPdfs = recent;
        _isPremium = isPremium;
        _profile = profile;
        _retention = retention;
        _isLoading = false;
      });
    }
  }

  String get _name {
    final raw = (_profile?['display_name'] as String?)?.trim();
    return (raw == null || raw.isEmpty) ? 'Learner' : raw;
  }

  int get _todayWordsLearned =>
      (_retention['today_words_learned'] as int?) ?? 0;
  int get _todayReviews => (_retention['today_reviews_completed'] as int?) ?? 0;
  int get _todayReadingMins =>
      (_retention['today_reading_minutes'] as int?) ?? 0;
  int get _dailyGoal => (_retention['daily_goal_words'] as int?) ?? 10;
  int get _currentStreak => (_retention['streak_current'] as int?) ?? 0;
  int get _longestStreak => (_retention['streak_longest'] as int?) ?? 0;
  double get _goalProgress =>
      ((_retention['goal_progress'] as num?) ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: Icon(
              _isPremium
                  ? Icons.workspace_premium
                  : Icons.workspace_premium_outlined,
              color: _isPremium ? Colors.amber : null,
            ),
            onPressed: _openPremiumPage,
            tooltip: _isPremium ? 'Manage Premium' : 'Upgrade to Premium',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroCard(),
              const SizedBox(height: 14),
              _buildTodayPlanCard(),
              const SizedBox(height: 14),
              _buildQuickActions(),
              const SizedBox(height: 18),
              if (!_isPremium) ...[
                _buildPremiumBanner(),
                const SizedBox(height: 20),
              ],
              _buildSectionHeader('Continue Reading'),
              const SizedBox(height: 12),
              _buildRecentFiles(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final target = (_profile?['target_language'] as String?) ?? '-';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Welcome back, $_name',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '$_currentStreak day streak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Target language: $target',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child:
                    _heroStat('Daily goal', '$_todayWordsLearned/$_dailyGoal'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _heroStat('Reviews', '$_todayReviews'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _heroStat('Best streak', '$_longestStreak'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _goalProgress.clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayPlanCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today Plan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Stay consistent with short daily sessions.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _planStat(Icons.school, 'Due now', '$_wordsToReview'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _planStat(Icons.menu_book_rounded, 'Reading',
                    '${_todayReadingMins}m'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _planStat(Icons.flag, 'Learned', '$_todayWordsLearned'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QuizScreen()),
                ).then((_) => _loadData());
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start Today Session'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return _quickAction(
      icon: Icons.settings_outlined,
      title: 'Settings',
      subtitle: 'Customize app',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ).then((_) => _loadData());
      },
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4C1D95), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.amber),
              SizedBox(width: 8),
              Text(
                'Premium',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Unlock Gemini explanations, advanced stats, and unlimited learning tools.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openPremiumPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF312E81),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.workspace_premium),
              label: const Text('View Premium Plans'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
    );
  }

  Widget _buildRecentFiles() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_recentPdfs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(Icons.library_books_outlined,
                size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            Text(
              'No recent books found',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Import a PDF to get started',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recentPdfs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final pdf = _recentPdfs[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ReaderScreen(filePath: pdf['path']),
                ),
              ).then((_) => _loadData());
            },
            child: Container(
              width: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        image: const DecorationImage(
                          image: AssetImage(
                              'assets/pdf_cover_placeholder.png'), // Placeholder
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 40,
                          color: AppColors.primary.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            pdf['name'],
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPremiumPage() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    if (!mounted) return;
    if (result == true) {
      await _loadData();
    }
  }
}
