import 'dart:math';
import 'package:flutter/material.dart';

class FlatFirePainter extends CustomPainter {
  final double animationProgress;

  FlatFirePainter({
    required this.animationProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (animationProgress <= 0) return;

    final double time = animationProgress * 10.0;

    // Make the fire rise from the bottom smoothly as progress goes from 0 to 1
    final double riseFactor =
        Curves.easeOut.transform(animationProgress.clamp(0.0, 1.0));

    // Draw 3 layers of 2D wavy flames
    _drawFlameLayer(
      canvas: canvas,
      size: size,
      time: time,
      color: const Color(0xFFD84315), // Deep Orange
      heightScale: 0.65 * riseFactor,
      complexity: 8,
      speed: 1.2,
      phase: 0.0,
    );

    _drawFlameLayer(
      canvas: canvas,
      size: size,
      time: time,
      color: const Color(0xFFFF8F00), // Orange
      heightScale: 0.45 * riseFactor,
      complexity: 6,
      speed: 1.5,
      phase: 2.0,
    );

    _drawFlameLayer(
      canvas: canvas,
      size: size,
      time: time,
      color: const Color(0xFFFFCA28), // Amber / Yellow
      heightScale: 0.25 * riseFactor,
      complexity: 5,
      speed: 1.8,
      phase: 4.0,
    );
  }

  void _drawFlameLayer({
    required Canvas canvas,
    required Size size,
    required double time,
    required Color color,
    required double heightScale,
    required int complexity,
    required double speed,
    required double phase,
  }) {
    final Path path = Path();
    path.moveTo(0, size.height);

    final double width = size.width;
    final double baseY = size.height - (size.height * heightScale);

    List<Offset> points = [];
    points.add(Offset(0, baseY));

    for (int i = 1; i <= complexity; i++) {
      double normalizedX = i / complexity;
      double x = normalizedX * width;

      // Combine two sine waves for organic 2D flame wiggling
      double wave1 = sin(time * speed + normalizedX * pi * 2 + phase);
      double wave2 = cos(time * speed * 1.4 + normalizedX * pi * 4 + phase);

      // Amplitude of the flame spikes
      double spikeAmplitude = 80.0 * heightScale;

      // We want the edges to be lower and the center to have higher spikes occasionally?
      // For a uniform sea of fire, just base it on the waves.
      double y = baseY + (wave1 + wave2) * spikeAmplitude;
      points.add(Offset(x, y));
    }

    // Draw smooth curved lines between points
    path.lineTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      double cx = (points[i].dx + points[i + 1].dx) / 2;
      double cy = (points[i].dy + points[i + 1].dy) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, cx, cy);
    }
    // Connect to the last exact point
    path.lineTo(points.last.dx, points.last.dy);

    path.lineTo(size.width, size.height);
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant FlatFirePainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress;
  }
}
