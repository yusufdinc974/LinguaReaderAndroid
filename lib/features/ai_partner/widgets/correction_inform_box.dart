import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/ai_partner_service.dart';

class CorrectionInformBox extends StatefulWidget {
  final CorrectionData correction;
  const CorrectionInformBox({super.key, required this.correction});

  @override
  State<CorrectionInformBox> createState() => _CorrectionInformBoxState();
}

class _CorrectionInformBoxState extends State<CorrectionInformBox>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _controller;
  late Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  Color get _categoryColor {
    switch (widget.correction.category) {
      case 'spelling':
        return const Color(0xFFEC4899); // pink
      case 'naturalness':
        return AppColors.secondary; // teal
      default:
        return AppColors.warning; // amber – grammar
    }
  }

  String get _categoryLabel {
    switch (widget.correction.category) {
      case 'spelling':
        return 'Spelling';
      case 'naturalness':
        return 'Naturalness';
      default:
        return 'Grammar';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(top: 6, left: 44, right: 12),
        decoration: BoxDecoration(
          color: _categoryColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: _categoryColor.withOpacity(0.45), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Collapsed header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(Icons.auto_fix_high_rounded,
                      size: 15, color: _categoryColor),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _categoryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _categoryLabel,
                      style: TextStyle(
                        color: _categoryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fixement · tap to ${_expanded ? 'collapse' : 'expand'}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 280),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            // ── Expanded content ──────────────────────────────────────────────
            SizeTransition(
              sizeFactor: _expandAnim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    _Row(
                      icon: Icons.close_rounded,
                      iconColor: AppColors.error,
                      label: 'Original',
                      text: widget.correction.original,
                      textStyle: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.error,
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Row(
                      icon: Icons.check_circle_rounded,
                      iconColor: AppColors.success,
                      label: 'Corrected',
                      text: widget.correction.corrected,
                      textStyle: TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Row(
                      icon: Icons.lightbulb_outline_rounded,
                      iconColor: AppColors.primaryLight,
                      label: 'Why',
                      text: widget.correction.explanation,
                      textStyle: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        height: 1.4,
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
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String text;
  final TextStyle textStyle;

  const _Row({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.text,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textTertiary,
                      letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(text, style: textStyle),
            ],
          ),
        ),
      ],
    );
  }
}
