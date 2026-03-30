import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/pixel_card.dart';
import '../../core/widgets/pixel_text_bubble.dart';
import '../../services/database_service.dart';
import '../../services/tutorial_service.dart';
import '../reader/reader_screen.dart';
import '../words/word_list_screen.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _databaseService = DatabaseService();

  bool _isLoading = true;
  int _listCount = 0;
  int _wordCount = 0;
  bool _sampleOpened = false;
  String? _samplePath;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);

    final samplePath = await TutorialService.ensureSamplePdf();
    final listCount = await _databaseService.getWordListCount();
    final wordCount = await _databaseService.getWordListItemCount();
    final sampleOpened = await TutorialService.isSampleOpened();

    if (!mounted) return;
    setState(() {
      _samplePath = samplePath;
      _listCount = listCount;
      _wordCount = wordCount;
      _sampleOpened = sampleOpened;
      _isLoading = false;
    });
  }

  Future<void> _openVocabulary() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WordListScreen()),
    );
    if (mounted) {
      await _loadStatus();
    }
  }

  Future<void> _openSamplePdf() async {
    final path = _samplePath ?? await TutorialService.ensureSamplePdf();
    await TutorialService.markSampleOpened();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          filePath: path,
          showTutorial: true,
        ),
      ),
    );
    if (mounted) {
      await _loadStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedSteps = [
      _listCount > 0,
      _sampleOpened,
      _wordCount > 0,
    ].where((done) => done).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Getting Started'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close tutorial',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  PixelCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Let’s set you up in 3 quick steps.',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Progress: $completedSteps/3',
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: completedSteps / 3,
                          minHeight: 8,
                          backgroundColor: AppColors.surfaceHighlight,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.success),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  PixelCard(
                    child: Column(
                      children: [
                        const PixelTextBubble(
                          text:
                              "I'm Lexi. This is my diary... please be gentle.",
                        ),
                        const SizedBox(height: 12),
                        Image.asset(
                          'assets/fox_tutorial/casual.png',
                          height: 230,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildStepCard(
                    title: 'Create a vocabulary list',
                    description: 'Add your first list to organize new words.',
                    completed: _listCount > 0,
                    actionLabel: 'Go to Vocabulary',
                    onAction: _openVocabulary,
                  ),
                  const SizedBox(height: 12),
                  _buildStepCard(
                    title: 'Open the example PDF',
                    description:
                        'Read the included sample and try selecting a word.',
                    completed: _sampleOpened,
                    actionLabel: 'Open Sample PDF',
                    onAction: _openSamplePdf,
                  ),
                  const SizedBox(height: 12),
                  _buildStepCard(
                    title: 'Add a word to your list',
                    description:
                        'In the reader, select a word, choose your list, and save it.',
                    completed: _wordCount > 0,
                    actionLabel: 'Open Sample PDF',
                    onAction: _openSamplePdf,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStepCard({
    required String title,
    required String description,
    required bool completed,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final badgeColor = completed ? AppColors.success : AppColors.warning;
    final badgeLabel = completed ? 'Done' : 'To do';

    return PixelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                completed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: badgeColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              PixelPill(label: badgeLabel, color: badgeColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
