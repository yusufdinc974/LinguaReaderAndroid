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
  static Future<Uint8List> highlightWords(Uint8List pdfBytes, List<WordColor> words) async {
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
              annotation.textMarkupAnnotationType == PdfTextMarkupAnnotationType.highlight) {
            annotationsToRemove.add(annotation);
          }
        }
        
        for (final annotation in annotationsToRemove) {
          page.annotations.remove(annotation);
        }
      }

      // 2. Add new highlights if any words provided
      if (words.isNotEmpty) {
        // Iterate through each word to find and highlight
        for (final wordColor in words) {
          if (wordColor.word.trim().isEmpty) continue;

          // Create a text searcher
          PdfTextExtractor extractor = PdfTextExtractor(document);
          
          // Find all occurrences of the word
          List<MatchedItem> matches = extractor.findText([wordColor.word]);

          for (final match in matches) {
             // Iterate through matches and add annotation to the specific page
             int pageIndex = match.pageIndex;
             PdfPage page = document.pages[pageIndex];

             final pdfColor = PdfColor(
               wordColor.color.red, 
               wordColor.color.green, 
               wordColor.color.blue,
             );

             // Create highlight annotation
             PdfTextMarkupAnnotation highlight = PdfTextMarkupAnnotation(
               match.bounds,
               wordColor.word,
               pdfColor,
             );
             
             highlight.textMarkupAnnotationType = PdfTextMarkupAnnotationType.highlight;
             
             // Set opacity to be semi-transparent
             highlight.opacity = 0.4;

             // Add the annotation to the page
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
  static Future<List<MatchedItem>> findText(Uint8List pdfBytes, String text) async {
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
    final normalized = words.map((w) => w.trim()).where((w) => w.isNotEmpty).toList();
    if (normalized.isEmpty) return {};

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: pdfBytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final Map<String, List<MatchedItem>> results = {};

      for (final word in normalized) {
        final matches = extractor.findText([word]);
        if (matches.isNotEmpty) {
          results[word] = matches;
        }
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
