import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/database_service.dart';
import '../../core/constants/app_colors.dart';
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
  int _overdueCount = 0;
  int _dueTodayCount = 0;
  int _dueSoonCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final stats = await _databaseService.getFamiliarityStats();
    final upcoming = await _databaseService.getUpcomingReviews();
    
    // Extract counts from upcoming reviews
    int overdue = 0, today = 0, soon = 0;
    for (var item in upcoming) {
      final label = item['review_day'] as String;
      final count = item['count'] as int;
      if (label.contains('Overdue')) overdue = count;
      else if (label.contains('Today')) today = count;
      else if (label.contains('Soon')) soon = count;
    }
    
    if (mounted) {
      setState(() {
        _familiarityStats = stats;
        _upcomingReviews = upcoming;
        _overdueCount = overdue;
        _dueTodayCount = today;
        _dueSoonCount = soon;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DataManagementScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Urgent Review Alert
                    if (_overdueCount > 0 || _dueTodayCount > 0)
                      _buildUrgentAlert(),
                    
                    // Detailed Status Cards
                    _buildDetailedCards(),
                    const SizedBox(height: 24),
                    
                    // Mastery Pie Chart with Legend
                    _buildSectionTitle('Mastery Distribution'),
                    const SizedBox(height: 16),
                    _buildMasteryChartWithLegend(),
                    const SizedBox(height: 32),

                    // Schedule Bar Chart
                    _buildSectionTitle('Upcoming Reviews'),
                    const SizedBox(height: 16),
                    _buildScheduleChart(),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildUrgentAlert() {
    final urgentCount = _overdueCount + _dueTodayCount;
    final isOverdue = _overdueCount > 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOverdue 
            ? [Colors.red.shade400, Colors.red.shade600]
            : [Colors.orange.shade400, Colors.orange.shade600],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isOverdue ? Colors.red : Colors.orange).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOverdue ? Icons.warning_amber_rounded : Icons.schedule,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOverdue ? 'Words Overdue!' : 'Review Due Today',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '$urgentCount ${urgentCount == 1 ? 'word needs' : 'words need'} your attention',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$urgentCount',
              style: TextStyle(
                color: isOverdue ? Colors.red : Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedCards() {
    int total = 0;
    _familiarityStats.forEach((_, count) => total += count);
    
    return Column(
      children: [
        // First row: Total and Mastered
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                'Total Words',
                total.toString(),
                Icons.book,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatusCard(
                'Mastered',
                _familiarityStats['Mastered']?.toString() ?? '0',
                Icons.star,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Second row: Overdue, Due Today, Due Soon
        Row(
          children: [
            Expanded(
              child: _buildCompactStatusCard(
                'Overdue',
                _overdueCount.toString(),
                Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCompactStatusCard(
                'Due Today',
                _dueTodayCount.toString(),
                Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCompactStatusCard(
                'Due Soon',
                _dueSoonCount.toString(),
                Colors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            title,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStatusCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildMasteryChartWithLegend() {
    final chartData = [
      {'label': 'Unknown', 'value': _familiarityStats['Unknown'] ?? 0, 'color': Colors.grey},
      {'label': 'Seen', 'value': _familiarityStats['Seen'] ?? 0, 'color': Colors.orange},
      {'label': 'Learning', 'value': _familiarityStats['Learning'] ?? 0, 'color': Colors.blue},
      {'label': 'Mastered', 'value': _familiarityStats['Mastered'] ?? 0, 'color': Colors.green},
    ];
    
    return Row(
      children: [
        // Chart
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 35,
                sections: chartData.map((data) {
                  final value = data['value'] as int;
                  return PieChartSectionData(
                    color: data['color'] as Color,
                    value: value.toDouble(),
                    title: value > 0 ? '$value' : '',
                    radius: 45,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        
        // Legend
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: chartData.map((data) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: data['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data['label'] as String,
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

  Widget _buildScheduleChart() {
    if (_upcomingReviews.isEmpty) {
      return const SizedBox(
        height: 100, 
        child: Center(child: Text('No upcoming reviews scheduled.', style: TextStyle(color: AppColors.textSecondary)))
      );
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _upcomingReviews.map((e) => e['count'] as int).reduce(max).toDouble() + 1,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < _upcomingReviews.length) {
                    final label = _upcomingReviews[value.toInt()]['review_day'] as String;
                    // Shorten labels for mobile
                    String shortLabel = label;
                    if (label.contains('Overdue')) shortLabel = 'Late';
                    else if (label.contains('Today')) shortLabel = 'Today';
                    else if (label.contains('Soon')) shortLabel = '1-3d';
                    else if (label.contains('Later')) shortLabel = '4-7d';
                    else if (label.contains('Mastered')) shortLabel = '7+d';
                    
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        shortLabel, 
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: _upcomingReviews.asMap().entries.map((entry) {
            Color barColor = AppColors.primary;
            final label = entry.value['review_day'] as String;
             if (label.contains('Overdue')) barColor = Colors.red;
             if (label.contains('Today')) barColor = Colors.orange;
             if (label.contains('Mastered')) barColor = Colors.green;

            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: (entry.value['count'] as int).toDouble(),
                  color: barColor,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
  
  int max(int a, int b) => a > b ? a : b;
}
