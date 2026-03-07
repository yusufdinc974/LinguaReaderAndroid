import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum FoxAnimation {
  idleSouth,
  staticIdleSouth,
  walkEast,
  walkWest,
  jumpSouth,
  jumpEast,
  jumpWest,
  yawnSouth,
  yawnEast,
  yawnWest,
}

class FoxSpriteAnimator extends StatefulWidget {
  const FoxSpriteAnimator({
    super.key,
    this.animation = FoxAnimation.idleSouth,
    this.size = 72,
    this.frameDuration = const Duration(milliseconds: 130),
    this.autoplay = true,
  });

  final FoxAnimation animation;
  final double size;
  final Duration frameDuration;
  final bool autoplay;

  @override
  State<FoxSpriteAnimator> createState() => _FoxSpriteAnimatorState();
}

class _FoxSpriteAnimatorState extends State<FoxSpriteAnimator> {
  late List<String> _frames;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _frames = _buildFrames(widget.animation);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant FoxSpriteAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _frames = _buildFrames(widget.animation);
      _index = 0;
    }
    if (oldWidget.frameDuration != widget.frameDuration ||
        oldWidget.autoplay != widget.autoplay) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!widget.autoplay || _frames.length <= 1) return;
    _timer = Timer.periodic(widget.frameDuration, (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _frames.length;
      });
    });
  }

  List<String> _buildFrames(FoxAnimation animation) {
    switch (animation) {
      case FoxAnimation.walkEast:
        return _paths('assets/fox/animations/walk-8-frames/east', 8);
      case FoxAnimation.walkWest:
        return _paths('assets/fox/animations/walk-8-frames/west', 8);
      case FoxAnimation.jumpSouth:
        return _paths('assets/fox/animations/jump/south', 8);
      case FoxAnimation.jumpEast:
        return _paths('assets/fox/animations/jump/east', 8);
      case FoxAnimation.jumpWest:
        return _paths('assets/fox/animations/jump/west', 8);
      case FoxAnimation.yawnSouth:
        return _paths('assets/fox/animations/yawning/south', 11);
      case FoxAnimation.yawnEast:
        return _paths('assets/fox/animations/yawning/east', 11);
      case FoxAnimation.yawnWest:
        return _paths('assets/fox/animations/yawning/west', 11);
      case FoxAnimation.idleSouth:
        return _paths('assets/fox/animations/seated-on-belly-idle/south', 10);
      case FoxAnimation.staticIdleSouth:
        return _paths('assets/fox/animations/seated-on-belly-idle/south', 1);
    }
  }

  List<String> _paths(String basePath, int frameCount) {
    return List<String>.generate(
      frameCount,
      (index) => '$basePath/frame_${index.toString().padLeft(3, '0')}.png',
    );
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frames[_index];
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Image.asset(
        frame,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        isAntiAlias: false,
        gaplessPlayback: true,
      ),
    );
  }
}

class FoxMascotHeader extends StatelessWidget {
  const FoxMascotHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.animation = FoxAnimation.walkEast,
  });

  final String title;
  final String subtitle;
  final FoxAnimation animation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Row(
        children: [
          FoxSpriteAnimator(animation: animation, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
