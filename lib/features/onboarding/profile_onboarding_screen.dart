import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/database_service.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  final bool forceCompletion;

  const ProfileOnboardingScreen({super.key}) : forceCompletion = false;
  const ProfileOnboardingScreen.force({super.key}) : forceCompletion = true;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  final _databaseService = DatabaseService();
  final _nameController = TextEditingController();
  final _nativeLanguageController = TextEditingController(text: 'Turkish');

  int _step = 0;
  bool _isSaving = false;

  String? _selectedGoal;
  String? _selectedDiscovery;
  int _dailyGoal = 10;

  final List<String> _goalOptions = const [
    'Travel confidently',
    'Career growth',
    'Exam preparation',
    'Read books & articles',
    'Daily language habit',
  ];

  final List<String> _discoveryOptions = const [
    'App Store / Play Store',
    'Friend recommendation',
    'YouTube / Social media',
    'Search engine',
    'Community / Forum',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nativeLanguageController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingProfile() async {
    final profile = await _databaseService.getUserProfile();
    if (!mounted || profile == null) return;

    final displayName = (profile['display_name'] as String?) ?? '';
    final nativeLanguage = (profile['native_language'] as String?) ?? '';
    final learningGoal = profile['learning_goal'] as String?;
    final discoverySource = profile['discovery_source'] as String?;
    final dailyGoal = (profile['daily_goal_words'] as int?) ?? _dailyGoal;
    setState(() {
      _nameController.text = displayName;
      if (nativeLanguage.trim().isNotEmpty) {
        _nativeLanguageController.text = nativeLanguage;
      }
      _selectedGoal = _goalOptions.contains(learningGoal) ? learningGoal : null;
      _selectedDiscovery =
          _discoveryOptions.contains(discoverySource) ? discoverySource : null;
      _dailyGoal = dailyGoal < 1 ? 1 : dailyGoal;
    });
  }

  void _next() {
    if (_step == 0 && _nameController.text.trim().isEmpty) {
      _showToast('Please enter your name.');
      return;
    }
    if (_step == 0 && _nativeLanguageController.text.trim().isEmpty) {
      _showToast('Please enter your native language.');
      return;
    }
    if (_step == 1 && _selectedGoal == null) {
      _showToast('Choose your main learning goal.');
      return;
    }
    if (_step == 2 && _selectedDiscovery == null) {
      _showToast('Select where you heard about us.');
      return;
    }
    if (_step < 3) {
      setState(() => _step += 1);
      return;
    }
    _finishOnboarding();
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  Future<void> _finishOnboarding() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final existingTarget =
          (await _databaseService.getSetting('target_language'))
              ?.trim()
              .toUpperCase();
      final detectedTarget =
          _detectLanguageCode(_nativeLanguageController.text.trim());
      final targetLanguageCode = detectedTarget ?? existingTarget ?? 'TR';

      await _databaseService.saveUserProfile(
        displayName: _nameController.text.trim(),
        learningGoal: _selectedGoal ?? '',
        discoverySource: _selectedDiscovery ?? '',
        nativeLanguage: _nativeLanguageController.text.trim(),
        targetLanguage: targetLanguageCode,
        dailyGoalWords: _dailyGoal,
        onboardingCompleted: true,
      );
      await _databaseService.saveSetting('target_language', targetLanguageCode);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showToast('Could not save profile: $e');
      setState(() => _isSaving = false);
    }
  }

  void _showToast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  String? _detectLanguageCode(String nativeLanguage) {
    final normalized = nativeLanguage.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    const aliases = <String, String>{
      'english': 'EN',
      'en': 'EN',
      'spanish': 'ES',
      'es': 'ES',
      'french': 'FR',
      'fr': 'FR',
      'german': 'DE',
      'de': 'DE',
      'italian': 'IT',
      'it': 'IT',
      'portuguese': 'PT',
      'pt': 'PT',
      'dutch': 'NL',
      'nl': 'NL',
      'polish': 'PL',
      'pl': 'PL',
      'russian': 'RU',
      'ru': 'RU',
      'japanese': 'JA',
      'ja': 'JA',
      'chinese': 'ZH',
      'mandarin': 'ZH',
      'zh': 'ZH',
      'turkish': 'TR',
      'turkce': 'TR',
      'türkçe': 'TR',
      'tr': 'TR',
    };

    return aliases[normalized];
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_step + 1) / 4;

    return PopScope(
      canPop: !widget.forceCompletion,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.forceCompletion,
          title: const Text('Set Up Your Profile'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(child: _buildStepContent()),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _step == 0 || _isSaving ? null : _back,
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _next,
                        child: Text(_step == 3 ? 'Create Profile' : 'Continue'),
                      ),
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

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildIdentityStep();
      case 1:
        return _buildGoalStep();
      case 2:
        return _buildDiscoveryStep();
      default:
        return _buildDailyGoalStep();
    }
  }

  Widget _buildIdentityStep() {
    return ListView(
      children: [
        const Text(
          'What should we call you?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your profile helps us personalize your learning journey.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Yusuf',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nativeLanguageController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Native language',
            hintText: 'e.g. Turkish',
            prefixIcon: Icon(Icons.language),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your native language will be used as initial translation language.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildGoalStep() {
    return ListView(
      children: [
        const Text(
          'What is your main aim?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Pick the goal that best matches your motivation.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        ..._goalOptions.map((goal) => _selectCard(
              label: goal,
              selected: _selectedGoal == goal,
              onTap: () => setState(() => _selectedGoal = goal),
            )),
      ],
    );
  }

  Widget _buildDiscoveryStep() {
    return ListView(
      children: [
        const Text(
          'Where did you hear about us?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'This helps us improve how we reach learners.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        ..._discoveryOptions.map((source) => _selectCard(
              label: source,
              selected: _selectedDiscovery == source,
              onTap: () => setState(() => _selectedDiscovery = source),
            )),
      ],
    );
  }

  Widget _buildDailyGoalStep() {
    return ListView(
      children: [
        const Text(
          'Set your daily goal',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Consistency beats intensity. Choose a realistic target.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [5, 10, 15, 20, 30].map((value) {
            final selected = _dailyGoal == value;
            return ChoiceChip(
              label: Text('$value words/day'),
              selected: selected,
              onSelected: (_) => setState(() => _dailyGoal = value),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile Summary',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text('Name: ${_nameController.text.trim()}'),
              Text('Native language: ${_nativeLanguageController.text.trim()}'),
              Text('Goal: ${_selectedGoal ?? '-'}'),
              Text('Discovery: ${_selectedDiscovery ?? '-'}'),
              Text('Daily target: $_dailyGoal words'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectCard({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.15)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Theme.of(context).dividerColor.withOpacity(0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked_outlined,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            )
          ],
        ),
      ),
    );
  }
}
