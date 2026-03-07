import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/pixel_card.dart';
import '../../services/database_service.dart';
import '../settings/data_management_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _databaseService = DatabaseService();
  bool _isLoading = true;

  Map<String, int> _familiarityStats = {};
  List<Map<String, dynamic>> _upcomingReviews = [];
  List<Map<String, dynamic>> _dailyQuizActivity = [];
  Map<String, dynamic> _quizStats = {};

  int _wordsToReview = 0;
  int _overdueCount = 0;
  int _dueTodayCount = 0;
  int _dueSoonCount = 0;
  int _dueLaterCount = 0;
  int _masteredScheduledCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait<dynamic>([
        _databaseService.getFamiliarityStats(),
        _databaseService.getUpcomingReviews(),
        _databaseService.getWordsToReviewCount(),
        _databaseService.getQuizPerformanceStats(),
        _databaseService.getDailyQuizActivity(days: 7),
      ]);

      final stats = results[0] as Map<String, int>;
      final upcoming = results[1] as List<Map<String, dynamic>>;
      final toReviewCount = results[2] as int;
      final quizStats = results[3] as Map<String, dynamic>;
      final dailyActivity = results[4] as List<Map<String, dynamic>>;

      int overdue = 0;
      int today = 0;
      int soon = 0;
      int later = 0;
      int mastered = 0;

      for (final item in upcoming) {
        final label = (item['review_day'] as String?) ?? '';
        final count = (item['count'] as int?) ?? 0;
        if (label.startsWith('Overdue')) {
          overdue = count;
        } else if (label.startsWith('Today')) {
          today = count;
        } else if (label.startsWith('Soon')) {
          soon = count;
        } else if (label.startsWith('Later')) {
          later = count;
        } else if (label.startsWith('Mastered')) {
          mastered = count;
        }
      }

      if (!mounted) return;
      setState(() {
        _familiarityStats = stats;
        _upcomingReviews = upcoming;
        _wordsToReview = toReviewCount;
        _quizStats = quizStats;
        _dailyQuizActivity = dailyActivity;
        _overdueCount = overdue;
        _dueTodayCount = today;
        _dueSoonCount = soon;
        _dueLaterCount = later;
        _masteredScheduledCount = mastered;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  int get _unknownCount => _familiarityStats['Unknown'] ?? 0;
  int get _seenCount => _familiarityStats['Seen'] ?? 0;
  int get _learningCount => _familiarityStats['Learning'] ?? 0;
  int get _masteredCount => _familiarityStats['Mastered'] ?? 0;
  int get _totalWords =>
      _unknownCount + _seenCount + _learningCount + _masteredCount;

  double get _masteryPercent {
    if (_totalWords == 0) return 0;
    return (_masteredCount / _totalWords) * 100;
  }

  double get _avgQuizAccuracy =>
      ((_quizStats['avg_accuracy'] as num?) ?? 0).toDouble();
  double get _bestQuizAccuracy =>
      ((_quizStats['best_accuracy'] as num?) ?? 0).toDouble();
  int get _totalQuizSessions => (_quizStats['total_sessions'] as int?) ?? 0;

  int get _urgentCount => _overdueCount + _dueTodayCount;
  int get _weeklyQuizSessions => _dailyQuizActivity.fold<int>(
        0,
        (sum, item) => sum + ((item['sessions'] as int?) ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const DataManagementScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildHeroCard(),
                  if (_urgentCount > 0) ...[
                    const SizedBox(height: 14),
                    _buildUrgentAlert(),
                  ],
                  const SizedBox(height: 16),
                  _buildKpiGrid(),
                  const SizedBox(height: 18),
                  _buildSectionCard(
                    title: 'Mastery Distribution',
                    subtitle:
                        'How your vocabulary is spread across learning stages.',
                    child: _buildMasteryChartWithLegend(),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: 'Review Schedule',
                    subtitle: 'Cards grouped by urgency and upcoming timing.',
                    child: _buildScheduleSection(),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: '7-Day Quiz Activity',
                    subtitle: 'Daily quiz sessions this week.',
                    child: _buildWeeklyActivitySection(),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: 'Quiz Performance',
                    subtitle: 'Your all-time and latest quiz performance.',
                    child: _buildQuizPerformanceSection(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroCard() {
    return PixelCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Learning Health',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const FoxSpriteAnimator(
                animation: FoxAnimation.yawnWest,
                size: 56,
              ),
              const Spacer(),
              Text(
                '${_masteryPercent.round()}% mastered',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _heroMetric(
                  label: 'Total Words',
                  value: '$_totalWords',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _heroMetric(
                  label: 'Due Now',
                  value: '$_wordsToReview',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _heroMetric(
                  label: 'Mastered',
                  value: '$_masteredCount',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_masteryPercent / 100).clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: AppColors.surfaceHighlight,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.success),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMetric({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgentAlert() {
    final hasOverdue = _overdueCount > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasOverdue
            ? AppColors.error.withOpacity(0.15)
            : AppColors.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasOverdue ? AppColors.error : AppColors.warning,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasOverdue ? Icons.warning_amber_rounded : Icons.schedule,
            color: hasOverdue ? AppColors.error : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasOverdue
                  ? '$_overdueCount overdue and $_dueTodayCount due today. Prioritize a review session.'
                  : '$_dueTodayCount cards are due today.',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid() {
    final cards = [
      _KpiCardData(
        title: 'Overdue',
        value: '$_overdueCount',
        color: AppColors.error,
        icon: Icons.error_outline,
      ),
      _KpiCardData(
        title: 'Due Today',
        value: '$_dueTodayCount',
        color: AppColors.warning,
        icon: Icons.today,
      ),
      _KpiCardData(
        title: 'Due Soon',
        value: '$_dueSoonCount',
        color: AppColors.primaryLight,
        icon: Icons.upcoming,
      ),
      _KpiCardData(
        title: 'Avg Quiz',
        value: '${_avgQuizAccuracy.round()}%',
        color: AppColors.success,
        icon: Icons.emoji_events_outlined,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.4,
      ),
      itemBuilder: (context, index) => _buildKpiCard(cards[index]),
    );
  }

  Widget _buildKpiCard(_KpiCardData data) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: data.color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: data.color, size: 20),
          const Spacer(),
          Text(
            data.value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: data.color,
            ),
          ),
          Text(
            data.title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return PixelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildMasteryChartWithLegend() {
    final chartData = [
      _ChartSlice('Unknown', _unknownCount, Colors.grey),
      _ChartSlice('Seen', _seenCount, AppColors.warning),
      _ChartSlice('Learning', _learningCount, AppColors.primaryLight),
      _ChartSlice('Mastered', _masteredCount, AppColors.success),
    ];

    final total = chartData.fold<int>(0, (sum, item) => sum + item.value);
    if (total == 0) {
      return const SizedBox(
        height: 130,
        child: Center(
          child: Text(
            'No familiarity data yet.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 38,
                sections: chartData.map((item) {
                  final percent = total == 0 ? 0 : (item.value / total) * 100;
                  return PieChartSectionData(
                    color: item.color,
                    value: item.value.toDouble(),
                    title: percent >= 8 ? '${percent.round()}%' : '',
                    radius: 48,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: chartData.map((item) {
              final percent = total == 0 ? 0 : (item.value / total) * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.label}  ${item.value} (${percent.round()}%)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleSection() {
    final totalScheduled = _upcomingReviews.fold<int>(
      0,
      (sum, item) => sum + ((item['count'] as int?) ?? 0),
    );
    if (_upcomingReviews.isEmpty || totalScheduled == 0) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No upcoming reviews scheduled.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 210,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: _upcomingReviews
                      .map((e) => (e['count'] as int?) ?? 0)
                      .fold<int>(0, max)
                      .toDouble() +
                  1,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.surfaceHighlight, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= _upcomingReviews.length) {
                        return const SizedBox.shrink();
                      }
                      final label =
                          (_upcomingReviews[idx]['review_day'] as String?) ??
                              '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _scheduleLabelShort(label),
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: _upcomingReviews.asMap().entries.map((entry) {
                final label = (entry.value['review_day'] as String?) ?? '';
                final count = ((entry.value['count'] as int?) ?? 0).toDouble();
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: count,
                      width: 16,
                      color: _scheduleColor(label),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildMiniPill('Overdue $_overdueCount', AppColors.error),
            _buildMiniPill('Today $_dueTodayCount', AppColors.warning),
            _buildMiniPill('Soon $_dueSoonCount', AppColors.primaryLight),
            _buildMiniPill('Later $_dueLaterCount', AppColors.secondary),
            _buildMiniPill('7+d $_masteredScheduledCount', AppColors.success),
          ],
        ),
      ],
    );
  }

  Widget _buildWeeklyActivitySection() {
    if (_dailyQuizActivity.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No activity data available.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final maxSessions = _dailyQuizActivity
        .map((item) => (item['sessions'] as int?) ?? 0)
        .fold<int>(0, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 190,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (maxSessions + 1).toDouble(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.surfaceHighlight, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= _dailyQuizActivity.length) {
                        return const SizedBox.shrink();
                      }
                      final day =
                          (_dailyQuizActivity[idx]['day'] as String?) ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _weekdayLabel(day),
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, __) {
                    final idx = group.x;
                    if (idx < 0 || idx >= _dailyQuizActivity.length) {
                      return null;
                    }
                    final item = _dailyQuizActivity[idx];
                    final sessions = (item['sessions'] as int?) ?? 0;
                    final acc = ((item['avg_accuracy'] as num?) ?? 0)
                        .toDouble()
                        .round();
                    return BarTooltipItem(
                      '$sessions sessions\n$acc% avg',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  },
                ),
              ),
              barGroups: _dailyQuizActivity.asMap().entries.map((entry) {
                final sessions =
                    ((entry.value['sessions'] as int?) ?? 0).toDouble();
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: sessions,
                      width: 14,
                      color: AppColors.primaryLight,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'You completed $_weeklyQuizSessions quiz sessions in the last 7 days.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildQuizPerformanceSection() {
    final lastCompleted = (_quizStats['last_completed_at'] as String?) ?? '';
    final hasLastQuiz = lastCompleted.isNotEmpty;

    String formattedLastDate = '-';
    if (hasLastQuiz) {
      try {
        formattedLastDate =
            DateFormat('MMM d, HH:mm').format(DateTime.parse(lastCompleted));
      } catch (_) {
        formattedLastDate = lastCompleted;
      }
    }

    final lastScore = (_quizStats['last_score'] as int?) ?? 0;
    final lastTotal = (_quizStats['last_total_questions'] as int?) ?? 0;
    final lastAccuracy =
        lastTotal > 0 ? ((lastScore / lastTotal) * 100).round() : 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _metricTile(
                label: 'Total Quizzes',
                value: '$_totalQuizSessions',
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricTile(
                label: 'Best Accuracy',
                value: '${_bestQuizAccuracy.round()}%',
                color: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metricTile(
                label: 'Average Accuracy',
                value: '${_avgQuizAccuracy.round()}%',
                color: AppColors.primaryLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricTile(
                label: 'Last Quiz',
                value: hasLastQuiz ? '$lastAccuracy%' : '-',
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHighlight.withOpacity(0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            hasLastQuiz
                ? 'Last quiz: $lastScore/$lastTotal on $formattedLastDate'
                : 'No quiz history yet. Complete your first quiz to see performance stats.',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _scheduleLabelShort(String label) {
    if (label.startsWith('Overdue')) return 'Late';
    if (label.startsWith('Today')) return 'Today';
    if (label.startsWith('Soon')) return '1-3d';
    if (label.startsWith('Later')) return '4-7d';
    return '7+d';
  }

  Color _scheduleColor(String label) {
    if (label.startsWith('Overdue')) return AppColors.error;
    if (label.startsWith('Today')) return AppColors.warning;
    if (label.startsWith('Soon')) return AppColors.primaryLight;
    if (label.startsWith('Later')) return AppColors.secondary;
    return AppColors.success;
  }

  String _weekdayLabel(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('E').format(date);
    } catch (_) {
      return '-';
    }
  }
}

class _KpiCardData {
  const _KpiCardData({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;
}

class _ChartSlice {
  const _ChartSlice(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}
