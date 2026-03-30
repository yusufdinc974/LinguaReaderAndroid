import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class PixelTextBubble extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;

  const PixelTextBubble({
    super.key,
    required this.text,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.backgroundColor,
    this.borderColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? Theme.of(context).colorScheme.surface;
    final bColor = borderColor ?? AppColors.border;
    final tColor = textColor ?? AppColors.textPrimary;

    return CustomPaint(
      painter: PixelBubblePainter(
        backgroundColor: bgColor,
        borderColor: bColor,
      ),
      child: Padding(
        padding: padding,
        child: Text(
          text,
          style: TextStyle(
            color: tColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class PixelBubblePainter extends CustomPainter {
  final Color backgroundColor;
  final Color borderColor;
  final double pixelSize;

  PixelBubblePainter({
    required this.backgroundColor,
    required this.borderColor,
    this.pixelSize = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;

    // We draw a pixelated border by drawing a series of rectangles.
    // Inner background
    canvas.drawRect(
      Rect.fromLTWH(pixelSize, pixelSize, size.width - 2 * pixelSize,
          size.height - 2 * pixelSize),
      bgPaint,
    );

    // Top border
    canvas.drawRect(
        Rect.fromLTWH(pixelSize * 2, 0, size.width - pixelSize * 4, pixelSize),
        borderPaint);
    // Bottom border
    canvas.drawRect(
        Rect.fromLTWH(pixelSize * 2, size.height - pixelSize,
            size.width - pixelSize * 4, pixelSize),
        borderPaint);
    // Left border
    canvas.drawRect(
        Rect.fromLTWH(0, pixelSize * 2, pixelSize, size.height - pixelSize * 4),
        borderPaint);
    // Right border
    canvas.drawRect(
        Rect.fromLTWH(size.width - pixelSize, pixelSize * 2, pixelSize,
            size.height - pixelSize * 4),
        borderPaint);

    // Corners
    // Top-left
    canvas.drawRect(
        Rect.fromLTWH(pixelSize, pixelSize, pixelSize, pixelSize), borderPaint);
    // Top-right
    canvas.drawRect(
        Rect.fromLTWH(
            size.width - pixelSize * 2, pixelSize, pixelSize, pixelSize),
        borderPaint);
    // Bottom-left
    canvas.drawRect(
        Rect.fromLTWH(
            pixelSize, size.height - pixelSize * 2, pixelSize, pixelSize),
        borderPaint);
    // Bottom-right
    canvas.drawRect(
        Rect.fromLTWH(size.width - pixelSize * 2, size.height - pixelSize * 2,
            pixelSize, pixelSize),
        borderPaint);

    // Pointing triangle (tail) at the bottom middle
    final tailCenterX = size.width / 2;

    // Tail border
    canvas.drawRect(
        Rect.fromLTWH(tailCenterX - pixelSize * 1.5, size.height, pixelSize * 3,
            pixelSize),
        borderPaint);
    canvas.drawRect(
        Rect.fromLTWH(tailCenterX - pixelSize * 0.5, size.height + pixelSize,
            pixelSize, pixelSize),
        borderPaint);

    // Fill the hole in the bottom border where the tail attaches
    canvas.drawRect(
        Rect.fromLTWH(tailCenterX - pixelSize * 1.5, size.height - pixelSize,
            pixelSize * 3, pixelSize),
        bgPaint);

    // Fill the tail
    canvas.drawRect(
        Rect.fromLTWH(
            tailCenterX - pixelSize * 0.5, size.height, pixelSize, pixelSize),
        bgPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
