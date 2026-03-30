import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/pixel_text_bubble.dart';
import '../../services/database_service.dart';
import '../../services/sync_service.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  final bool forceCompletion;
  final VoidCallback? onComplete;

  const ProfileOnboardingScreen({super.key, this.onComplete})
      : forceCompletion = false;
  const ProfileOnboardingScreen.force({super.key, this.onComplete})
      : forceCompletion = true;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen>
    with TickerProviderStateMixin {
  final _databaseService = DatabaseService();
  final _nameController = TextEditingController();
  final _nativeLanguageController = TextEditingController(text: 'Turkish');

  int _step = 0;
  bool _isSaving = false;

  // Exit Animation
  bool _isPlayingExitAnimation = false;
  double _exitFoxOffset = 0.0;
  FoxAnimation _foxAnimation = FoxAnimation.staticIdleSouth;

  // Portal Tracking
  final GlobalKey _portalKey = GlobalKey();
  Offset? _portalCenter;

  // Entrance Animation Choreography
  late AnimationController _entranceAnimController;
  late Animation<double> _orangeRadiusAnim;
  late Animation<double> _foxJumpYAnim;
  late Animation<double> _foxScaleAnim;

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

  final List<String> _languageOptions = const [
    'English',
    'Spanish',
    'French',
    'German',
    'Italian',
    'Portuguese',
    'Dutch',
    'Polish',
    'Russian',
    'Japanese',
    'Chinese',
    'Turkish',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
    _setupEntranceAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updatePortalCenter();
    });
  }

  void _updatePortalCenter() {
    final RenderBox? renderBox =
        _portalKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final size = renderBox.size;
      final offset = renderBox.localToGlobal(Offset.zero);
      setState(() {
        _portalCenter =
            Offset(offset.dx + size.width / 2, offset.dy + size.height / 2);
      });
    }
  }

  void _setupEntranceAnimation() {
    _entranceAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5500),
    );

    // 0.0 - 0.4: Orange circle shrinks to 50
    // 0.4 - 0.6: Fox pops out and jumps
    // 0.6 - 0.7: Portal closes
    _orangeRadiusAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 2500.0, end: 50.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(50.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 50.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInBack)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 30,
      ),
    ]).animate(_entranceAnimController);

    // Fox pops out of portal scale (0.4 - 0.5)
    _foxScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 40),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
    ]).animate(_entranceAnimController);

    // Fox jumps UP and lands (0.4 - 0.5)
    _foxJumpYAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 40),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -60.0)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -60.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 5,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 50),
    ]).animate(_entranceAnimController);

    _entranceAnimController.addListener(() {
      final t = _entranceAnimController.value;
      FoxAnimation anim;

      if (t < 0.4) {
        // Fox is hidden
        anim = FoxAnimation.jumpSouth;
      } else if (t >= 0.4 && t < 0.5) {
        // Fox is jumping out
        anim = FoxAnimation.jumpSouth;
      } else {
        // Fox arrived and is standing still
        anim = FoxAnimation.staticIdleSouth;
      }

      // Avoid overriding exit animation state
      if (_foxAnimation != anim && !_isPlayingExitAnimation) {
        setState(() => _foxAnimation = anim);
      }
    });

    _entranceAnimController.forward();
  }

  @override
  void dispose() {
    _entranceAnimController.dispose();
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

    if (_step == 0 && !_isPlayingExitAnimation) {
      _playFoxRunningSequence();
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

  Future<void> _playFoxRunningSequence() async {
    setState(() {
      _isPlayingExitAnimation = true;
      _foxAnimation = FoxAnimation.jumpEast;
      _exitFoxOffset = MediaQuery.of(context).size.width;
    });

    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;

    setState(() {
      _isPlayingExitAnimation = false;
      _foxAnimation = FoxAnimation.walkWest;
      _exitFoxOffset = 0.0;
      _step += 1;
    });
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

      // CRITICAL: Push profile to cloud immediately
      await SyncService.pushToCloud();

      if (!mounted) return;
      if (widget.onComplete != null) {
        widget.onComplete!();
      } else {
        Navigator.of(context).pop(true);
      }
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
      child: Stack(
        children: [
          Scaffold(
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
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_step > 0) ...[
                      const FoxSpriteAnimator(
                        animation: FoxAnimation.walkWest,
                        size: 66,
                      ),
                      const SizedBox(height: 18),
                    ],
                    Expanded(child: _buildStepContent()),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _step == 0 ||
                                    _isSaving ||
                                    _isPlayingExitAnimation ||
                                    _entranceAnimController.value < 0.95
                                ? null
                                : _back,
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _isSaving ||
                                    _isPlayingExitAnimation ||
                                    _entranceAnimController.value < 0.95
                                ? null
                                : _next,
                            child: Text(
                                _step == 3 ? 'Create Profile' : 'Continue'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Orange Screen Shrinking Reveal Overlay (only on step 0)
          if (_step == 0)
            AnimatedBuilder(
              animation: _entranceAnimController,
              builder: (context, child) {
                if (_entranceAnimController.value >= 0.5)
                  return const SizedBox.shrink();
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _OrangeCirclePainter(
                    holeRadius: _orangeRadiusAnim.value,
                    portalCenter: _portalCenter,
                  ),
                );
              },
            ),
        ],
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
        const SizedBox(height: 20),

        // Animated Fox Sequence
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Dummy invisible widget to track precise Fox center at start
              IgnorePointer(
                child: Opacity(
                  opacity: 0.0,
                  child: Transform.translate(
                    offset: const Offset(0, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PixelTextBubble(
                          text:
                              "Hi there! I'm your language fox.\nWhat should I call you?",
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          key: _portalKey,
                          width: 90,
                          height: 90,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                  animation: _entranceAnimController,
                  builder: (context, child) {
                    final double x = 0.0;
                    final double y = _foxJumpYAnim.value;
                    final double scale = _foxScaleAnim.value;
                    final double bubbleOpacity =
                        (_entranceAnimController.value > 0.75 &&
                                !_isPlayingExitAnimation)
                            ? 1.0
                            : 0.0;

                    return AnimatedContainer(
                      duration: _isPlayingExitAnimation
                          ? const Duration(milliseconds: 1000)
                          : Duration.zero,
                      curve: Curves.easeInCubic,
                      transform: Matrix4.translationValues(
                          _isPlayingExitAnimation ? _exitFoxOffset : x,
                          _isPlayingExitAnimation ? 0.0 : y,
                          0.0),
                      child: Transform.scale(
                        scale: scale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: bubbleOpacity,
                              child: const PixelTextBubble(
                                text:
                                    "Hi there! I'm Lexi, your language fox.\nWhat should I call you?",
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FoxSpriteAnimator(
                              animation: _foxAnimation,
                              size: 90,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
            ],
          ),
        ),

        const SizedBox(height: 32),
        AnimatedBuilder(
          animation: _entranceAnimController,
          builder: (context, child) {
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: _entranceAnimController.value > 0.8 ? 1.0 : 0.0,
              child: child,
            );
          },
          child: Column(
            children: [
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
              DropdownButtonFormField<String>(
                value: _languageOptions.any((l) =>
                        l.toLowerCase() ==
                        _nativeLanguageController.text.trim().toLowerCase())
                    ? _languageOptions.firstWhere((l) =>
                        l.toLowerCase() ==
                        _nativeLanguageController.text.trim().toLowerCase())
                    : 'Turkish',
                decoration: const InputDecoration(
                  labelText: 'Native language',
                  prefixIcon: Icon(Icons.language),
                ),
                items: _languageOptions.map((lang) {
                  return DropdownMenuItem(
                    value: lang,
                    child: Text(lang),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _nativeLanguageController.text = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'Your native language will be used as initial translation language.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
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
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.primary, width: 1.5),
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
              ? AppColors.primary.withOpacity(0.2)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
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

class _OrangeCirclePainter extends CustomPainter {
  final double holeRadius;
  final Offset? portalCenter;

  _OrangeCirclePainter({required this.holeRadius, this.portalCenter});

  @override
  void paint(Canvas canvas, Size size) {
    if (holeRadius <= 0) return;

    final paint = Paint()..color = AppColors.primary;
    // Default fallback while portalCenter is null
    final center =
        portalCenter ?? Offset(size.width / 2 - 100, size.height / 2);

    // Draw an orange circle that acts as the shrinking background.
    canvas.drawCircle(center, holeRadius, paint);
  }

  @override
  bool shouldRepaint(_OrangeCirclePainter oldDelegate) {
    return oldDelegate.holeRadius != holeRadius ||
        oldDelegate.portalCenter != portalCenter;
  }
}
