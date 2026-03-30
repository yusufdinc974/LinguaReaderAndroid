import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class WordColor {
  final String word;
  final Color color;

  WordColor(this.word, this.color);
}

class PdfHighlightService {
  /// Highlights the given [words] in the [pdfBytes] and returns the modified PDF bytes.
  static Future<Uint8List> highlightWords(
      Uint8List pdfBytes, List<WordColor> words) async {
    try {
      // 1. Load the PDF document
      final PdfDocument document = PdfDocument(inputBytes: pdfBytes);

      // 1.5 Clear existing highlights (to handle dirty files / previous highlights)
      for (int i = 0; i < document.pages.count; i++) {
        final PdfPage page = document.pages[i];
        final annotationsToRemove = <PdfAnnotation>[];

        for (int j = 0; j < page.annotations.count; j++) {
          final annotation = page.annotations[j];
          // Check if it's a highlight annotation
          if (annotation is PdfTextMarkupAnnotation &&
              annotation.textMarkupAnnotationType ==
                  PdfTextMarkupAnnotationType.highlight) {
            annotationsToRemove.add(annotation);
          }
        }

        for (final annotation in annotationsToRemove) {
          page.annotations.remove(annotation);
        }
      }

      // 2. Add new highlights if any words provided
      final normalized = words.where((w) => w.word.trim().isNotEmpty).toList();
      if (normalized.isNotEmpty) {
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        final matches = extractor.findText(
          normalized.map((w) => w.word).toList(),
        );
        if (matches.isNotEmpty) {
          final Map<String, WordColor> colorByWord = {
            for (final w in normalized) w.word: w,
          };
          for (final match in matches) {
            final wordColor = colorByWord[match.text];
            if (wordColor == null) continue;
            final PdfPage page = document.pages[match.pageIndex];
            final pdfColor = PdfColor(
              wordColor.color.red,
              wordColor.color.green,
              wordColor.color.blue,
            );

            final PdfTextMarkupAnnotation highlight = PdfTextMarkupAnnotation(
              match.bounds,
              wordColor.word,
              pdfColor,
            );

            highlight.textMarkupAnnotationType =
                PdfTextMarkupAnnotationType.highlight;
            highlight.opacity = 0.4;
            page.annotations.add(highlight);
          }
        }
      }

      // 3. Save the document and return bytes
      final List<int> savedBytes = await document.save();
      document.dispose();

      return Uint8List.fromList(savedBytes);
    } catch (e) {
      debugPrint('Error highlighting PDF: $e');
      return pdfBytes; // Return original if failure
    }
  }

  /// Finds all occurrences of [text] in the [pdfBytes].
  static Future<List<MatchedItem>> findText(
      Uint8List pdfBytes, String text) async {
    if (text.trim().isEmpty) return [];

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: pdfBytes);
      PdfTextExtractor extractor = PdfTextExtractor(document);
      final matches = extractor.findText([text]);
      return matches;
    } catch (e) {
      debugPrint('Error finding text: $e');
      return [];
    } finally {
      document?.dispose();
    }
  }

  /// Finds occurrences for multiple [words] in a single pass over the PDF.
  /// Returns a map of word -> matches. This avoids reloading the PDF per word.
  static Future<Map<String, List<MatchedItem>>> findTextForWords(
      Uint8List pdfBytes, List<String> words) async {
    final normalized =
        words.map((w) => w.trim()).where((w) => w.isNotEmpty).toList();
    if (normalized.isEmpty) return {};

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: pdfBytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final Map<String, List<MatchedItem>> results = {};
      final matches = extractor.findText(normalized);
      for (final match in matches) {
        results.putIfAbsent(match.text, () => []).add(match);
      }
      return results;
    } catch (e) {
      debugPrint('Error finding text for words: $e');
      return {};
    } finally {
      document?.dispose();
    }
  }
}
