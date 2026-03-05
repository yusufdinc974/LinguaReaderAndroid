import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import 'translation_sheet.dart';

class TextViewWidget extends StatelessWidget {
  final String text;

  const TextViewWidget({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    // Split text by spaces but keep punctuation attached or handle generically
    // For simplicity, we split by space and simple punctuation handling could be added
    final words = text.split(RegExp(r'(\s+)'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Wrap(
        spacing: 4,
        runSpacing: 8,
        children: words.map((word) {
          final cleanWord = word.trim();
          if (cleanWord.isEmpty) return const SizedBox.shrink();

          return GestureDetector(
            onTap: () => _showTranslation(context, cleanWord),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                // color: AppColors.surfaceHighlight.withOpacity(0.3), // Debug box
              ),
              child: Text(
                word, // Keep original parsing including trailing spaces if any
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showTranslation(BuildContext context, String word) {
    // Strip punctuation for translation
    // simple regex to remove common punctuation
    final lookupWord = word.replaceAll(RegExp(r'[^\w\s\u00C0-\u00FF]'), '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 1.0,
        expand: false,
        builder: (_, controller) => TranslationSheet(
          word: lookupWord,
          sentence:
              "Context extraction from text...", // Advanced: Find sentence in 'text'
          scrollController: controller,
        ),
      ),
    );
  }
}
