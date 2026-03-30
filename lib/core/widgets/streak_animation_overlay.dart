import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'flat_fire_painter.dart';

class StreakAnimationOverlay extends StatefulWidget {
  final int newStreak;
  final VoidCallback onComplete;

  const StreakAnimationOverlay({
    super.key,
    required this.newStreak,
    required this.onComplete,
  });

  /// Helper to show this directly as an overlay dialog
  static Future<void> show(BuildContext context,
      {required int newStreak}) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent, // We handle the background
      builder: (context) {
        return StreakAnimationOverlay(
          newStreak: newStreak,
          onComplete: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        );
      },
    );
  }

  @override
  State<StreakAnimationOverlay> createState() => _StreakAnimationOverlayState();
}

class _StreakAnimationOverlayState extends State<StreakAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  bool _readyToDismiss = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000), // Fire burns for 3 seconds
    );

    // Bounce the typography in after a small delay
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 5,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 65),
    ]).animate(_controller);

    _controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _readyToDismiss = true;
        });

        // Auto-dismiss after another 2 seconds if user doesn't tap
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _readyToDismiss) {
            widget.onComplete();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_readyToDismiss) {
          widget.onComplete();
        }
      },
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // Darken background over time
                Container(
                  color: Colors.black.withValues(
                      alpha: (_controller.value * 0.85).clamp(0.0, 1.0)),
                ),

                // Blur effect to focus entirely on the animation
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(color: Colors.transparent),
                ),

                // The Fire Layer
                Positioned.fill(
                  child: CustomPaint(
                    painter: FlatFirePainter(
                      animationProgress: _controller.value,
                    ),
                  ),
                ),

                // The Typography Layer
                Center(
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'STREAK INCREASED!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              fontSize: 22,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                    color: AppColors.primary,
                                    offset: Offset(0, 1),
                                    blurRadius: 10),
                                Shadow(
                                    color: Colors.black54,
                                    offset: Offset(0, 2),
                                    blurRadius: 4),
                              ]),
                        ),
                        const SizedBox(height: 20),
                        Icon(Icons.local_fire_department,
                            color: AppColors.warning,
                            size: 72,
                            shadows: const [
                              Shadow(
                                  color: AppColors.primary,
                                  offset: Offset(0, 0),
                                  blurRadius: 15),
                            ]),
                        const SizedBox(height: 10),
                        Text(
                          '${widget.newStreak}',
                          style: const TextStyle(
                              fontSize: 96,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.0,
                              shadows: [
                                Shadow(
                                    color: AppColors.warning,
                                    offset: Offset(0, 0),
                                    blurRadius: 20),
                                Shadow(
                                    color: Colors.black54,
                                    offset: Offset(0, 4),
                                    blurRadius: 8),
                              ]),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'DAYS',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 6,
                              fontSize: 18,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                    color: AppColors.primary,
                                    offset: Offset(0, 1),
                                    blurRadius: 10),
                                Shadow(
                                    color: Colors.black54,
                                    offset: Offset(0, 2),
                                    blurRadius: 4),
                              ]),
                        ),

                        // Tap to continue prompt
                        if (_readyToDismiss)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: AnimatedOpacity(
                              opacity: 1.0,
                              duration: const Duration(milliseconds: 500),
                              child: Text(
                                'Tap anywhere to continue',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
