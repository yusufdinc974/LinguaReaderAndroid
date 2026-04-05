import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/pixel_text_bubble.dart';
import 'widgets/translation_sheet.dart';
import '../../services/database_service.dart';
import '../../services/pdf_highlight_service.dart';
import '../../core/widgets/streak_animation_overlay.dart';
import '../../services/tutorial_service.dart';

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final bool showTutorial;

  const ReaderScreen({
    super.key,
    required this.filePath,
    this.showTutorial = false,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final DatabaseService _databaseService = DatabaseService();
  late final DateTime _sessionStartedAt;

  File? _pdfFile;
  Uint8List? _pdfBytesCache;
  int _pdfFileSizeBytes = 0;
  bool _isLoading = true;
  bool _pdfLoaded = false;
  Offset? _preservedScrollOffset;
  double? _preservedZoomLevel;
  List<int> _selectedListIds = [];
  List<Map<String, dynamic>> _availableLists = [];
  bool _isApplyingHighlights = false;
  bool _didShowLargePdfNotice = false;
  bool _allowLargePdfHighlights = false;
  bool _isSamplePdf = false;
  bool _showReaderTutorial = false;
  int _readerTutorialStep = 0;
  bool _readerTutorialVisible = false;

  // Page navigation state
  int _currentPage = 1;
  int _totalPages = 0;

  // Word tap selection state
  PdfDocument? _extractionDocument;
  final Map<int, List<TextLine>> _cachedTextLines = {};
  final List<_SelectedWord> _selectedWords = [];
  bool _showWordActions = false;

  static const int _largePdfThresholdBytes = 10 * 1024 * 1024; // 10 MB

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _loadPdf();
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    _extractionDocument?.dispose();
    super.dispose();
  }

  /// Load PDF file metadata and setup reader state
  Future<void> _loadPdf() async {
    setState(() => _isLoading = true);
    try {
      final File file = File(widget.filePath);
      final exists = await file.exists();
      if (!exists) {
        if (mounted) {
          setState(() {
            _pdfFile = null;
            _pdfFileSizeBytes = 0;
            _pdfBytesCache = null;
            _isLoading = false;
          });
        }
        return;
      }

      _pdfFileSizeBytes = await file.length();
      _pdfBytesCache = null;
      await TutorialService.markSampleOpenedIfMatches(widget.filePath);

      final samplePath = await TutorialService.getSamplePdfPath();
      final isSamplePdf = widget.filePath == samplePath;
      final completed = await TutorialService.isReaderTutorialCompleted();
      final shouldShowTutorial =
          isSamplePdf && (widget.showTutorial || !completed);

      _availableLists = await _databaseService.getWordLists();
      _selectedListIds = _availableLists.map((l) => l['id'] as int).toList();

      if (mounted) {
        setState(() {
          _pdfFile = file;
          _isLoading = false;
          _pdfLoaded = false;
          _didShowLargePdfNotice = false;
          _isApplyingHighlights = false;
          _allowLargePdfHighlights = false;
          _isSamplePdf = isSamplePdf;
          _showReaderTutorial = shouldShowTutorial;
          _readerTutorialVisible = shouldShowTutorial;
          if (shouldShowTutorial) {
            _readerTutorialStep = 0;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading PDF: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _advanceReaderTutorial(int step) {
    if (!_showReaderTutorial) return;
    if (step <= _readerTutorialStep) return;
    setState(() {
      _readerTutorialStep = step;
      _readerTutorialVisible = true;
    });
  }

  Future<void> _completeReaderTutorial() async {
    if (!_showReaderTutorial) return;
    await TutorialService.markReaderTutorialCompleted();
    if (mounted) {
      setState(() {
        _showReaderTutorial = false;
        _readerTutorialVisible = false;
      });
    }
  }

  void _hideReaderTutorial() {
    if (!_showReaderTutorial) return;
    setState(() => _readerTutorialVisible = false);
  }

  Future<Uint8List?> _getPdfBytes({bool cacheIfSmall = true}) async {
    final file = _pdfFile;
    if (file == null) return null;
    if (_isLargePdf && !_allowLargePdfHighlights) return null;
    if (_pdfBytesCache != null) return _pdfBytesCache;

    final bytes = await file.readAsBytes();
    if (cacheIfSmall && _pdfFileSizeBytes <= _largePdfThresholdBytes) {
      _pdfBytesCache = bytes;
    }
    return bytes;
  }

  bool get _isLargePdf => _pdfFileSizeBytes >= _largePdfThresholdBytes;

  void _maybeShowLargePdfNotice() {
    if (!mounted || _didShowLargePdfNotice) return;
    _didShowLargePdfNotice = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Large PDF detected. Performance mode is enabled (single-page view). Highlights are off by default.'),
      ),
    );
  }

  // ── Text extraction for word tapping ──

  /// Load extraction document for text extraction (lazily)
  Future<void> _loadExtractionDocument() async {
    if (_extractionDocument != null) return;
    try {
      final bytes = await _pdfFile!.readAsBytes();
      _extractionDocument = PdfDocument(inputBytes: bytes);
    } catch (e) {
      debugPrint('Error loading extraction document: $e');
    }
  }

  /// Get text lines for a given page (0-indexed), with caching
  List<TextLine>? _getTextLinesForPage(int pageIndex) {
    if (_cachedTextLines.containsKey(pageIndex)) {
      return _cachedTextLines[pageIndex];
    }
    if (_extractionDocument == null) return null;
    try {
      final extractor = PdfTextExtractor(_extractionDocument!);
      final textLines = extractor.extractTextLines(startPageIndex: pageIndex);
      _cachedTextLines[pageIndex] = textLines;
      return textLines;
    } catch (e) {
      debugPrint('Error extracting text lines for page $pageIndex: $e');
      return null;
    }
  }

  /// Handle tap on PDF page to find and select a word
  void _handleWordTap(PdfGestureDetails details) {
    if (details.pageNumber < 1) return;

    final pageIndex = details.pageNumber - 1;
    final tapPos = details.pagePosition;

    if (tapPos.dx < 0 || tapPos.dy < 0) return;

    final textLines = _getTextLinesForPage(pageIndex);
    if (textLines == null || textLines.isEmpty) return;

    // Find the word at the tap position
    for (final textLine in textLines) {
      for (final word in textLine.wordCollection) {
        if (word.bounds.contains(tapPos)) {
          final wordText = word.text.trim();
          if (wordText.isEmpty) return;

          _toggleWordSelection(wordText, word.bounds, pageIndex);
          return;
        }
      }
    }

    // Tapped outside any word - clear selection if any
    if (_selectedWords.isNotEmpty) {
      _clearWordSelection();
    }
  }

  void _toggleWordSelection(String word, Rect bounds, int pageIndex) {
    setState(() {
      // Check if word is already selected
      final existingIndex = _selectedWords.indexWhere(
        (sw) => sw.text == word && sw.pageIndex == pageIndex &&
                (sw.bounds.left - bounds.left).abs() < 1.0,
      );

      if (existingIndex >= 0) {
        // Deselect
        _selectedWords.removeAt(existingIndex);
        if (_selectedWords.isEmpty) {
          _showWordActions = false;
        }
      } else {
        // Select
        _selectedWords.add(_SelectedWord(
          text: word,
          bounds: bounds,
          pageIndex: pageIndex,
        ));
        _showWordActions = true;

        if (_showReaderTutorial && _readerTutorialStep == 0) {
          _advanceReaderTutorial(1);
        }
      }
    });

    // Update visual highlights for selected words
    _updateWordSelectionHighlights();
  }

  void _clearWordSelection() {
    // Remove selection highlight annotations
    _removeSelectionHighlights();
    setState(() {
      _selectedWords.clear();
      _showWordActions = false;
    });
  }

  void _updateWordSelectionHighlights() {
    // Remove old selection highlights
    _removeSelectionHighlights();

    // Add new highlights for all selected words
    for (final sw in _selectedWords) {
      final textLine = PdfTextLine(sw.bounds, sw.text, sw.pageIndex + 1);
      final annotation = HighlightAnnotation(textBoundsCollection: [textLine]);
      annotation.color = Colors.amber;
      annotation.opacity = 0.5;
      // Tag with a name so we can identify selection highlights
      _pdfViewerController.addAnnotation(annotation);
    }
  }

  void _removeSelectionHighlights() {
    // Remove all highlight annotations that match our selection color/opacity
    // We'll use amber color as the identifier for selection highlights
    final allAnnotations = _pdfViewerController.getAnnotations();
    final toRemove = <Annotation>[];
    for (final ann in allAnnotations) {
      if (ann is HighlightAnnotation &&
          ann.color == Colors.amber &&
          (ann.opacity - 0.5).abs() < 0.01) {
        toRemove.add(ann);
      }
    }
    for (final ann in toRemove) {
      _pdfViewerController.removeAnnotation(ann);
    }
  }

  String get _selectedText {
    if (_selectedWords.isEmpty) return '';
    // Sort by page, then by vertical position, then horizontal
    final sorted = List<_SelectedWord>.from(_selectedWords)
      ..sort((a, b) {
        if (a.pageIndex != b.pageIndex) return a.pageIndex.compareTo(b.pageIndex);
        if ((a.bounds.top - b.bounds.top).abs() > 5) return a.bounds.top.compareTo(b.bounds.top);
        return a.bounds.left.compareTo(b.bounds.left);
      });
    return sorted.map((sw) => sw.text).join(' ');
  }

  Future<void> _copySelectedWords() async {
    final text = _selectedText;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
    _clearWordSelection();
  }

  // ── Highlight overlays ──

  Future<void> _applyHighlightOverlays() async {
    if (!_pdfLoaded || _isApplyingHighlights) return;
    if (_isLargePdf && !_allowLargePdfHighlights) {
      _maybeShowLargePdfNotice();
      return;
    }
    _isApplyingHighlights = true;
    final pdfBytes = await _getPdfBytes();
    if (pdfBytes == null) {
      _isApplyingHighlights = false;
      return;
    }

    try {
      _pdfViewerController.removeAllAnnotations();

      if (_selectedListIds.isEmpty) {
        return;
      }

      final wordsData =
          await _databaseService.getWordsWithColors(listIds: _selectedListIds);

      if (wordsData.isEmpty) return;

      final words = wordsData.map((data) {
        final colorStr = data['color'] as String? ?? '0xFF2196F3';
        Color color;
        try {
          if (colorStr.startsWith('#')) {
            final hex = colorStr.replaceAll('#', '');
            if (hex.length == 6) {
              color = Color(int.parse('FF$hex', radix: 16));
            } else if (hex.length == 8) {
              color = Color(int.parse(hex, radix: 16));
            } else {
              color = const Color(0xFF2196F3);
            }
          } else if (colorStr.startsWith('0x')) {
            color = Color(int.parse(colorStr));
          } else {
            color = Color(int.parse(colorStr));
          }
        } catch (e) {
          color = const Color(0xFF2196F3);
        }
        return WordColor(data['word'] as String, color);
      }).toList();

      final matchesByWord = await PdfHighlightService.findTextForWords(
        pdfBytes,
        words.map((w) => w.word).toList(),
      );

      for (final wordColor in words) {
        final matches = matchesByWord[wordColor.word];
        if (matches == null || matches.isEmpty) continue;

        final Map<int, List<MatchedItem>> matchesByPage = {};
        for (final match in matches) {
          matchesByPage.putIfAbsent(match.pageIndex, () => []).add(match);
        }

        for (final entry in matchesByPage.entries) {
          final pageIndex = entry.key;
          final pageMatches = entry.value;

          final textLines = pageMatches
              .map((m) => PdfTextLine(m.bounds, wordColor.word, pageIndex + 1))
              .toList();

          final annotation =
              HighlightAnnotation(textBoundsCollection: textLines);
          annotation.color = wordColor.color;
          annotation.opacity = 0.4;

          _pdfViewerController.addAnnotation(annotation);
        }
      }
    } catch (e) {
      debugPrint('Error applying highlight overlays: $e');
    } finally {
      _isApplyingHighlights = false;
    }
  }

  Future<void> _addWordHighlightOverlay(WordColor wordColor) async {
    if (wordColor.word.trim().isEmpty) return;
    if (_isLargePdf && !_allowLargePdfHighlights) {
      _maybeShowLargePdfNotice();
      return;
    }
    final pdfBytes = await _getPdfBytes(cacheIfSmall: true);
    if (pdfBytes == null) return;

    try {
      final matches =
          await PdfHighlightService.findText(pdfBytes, wordColor.word);

      final Map<int, List<MatchedItem>> matchesByPage = {};
      for (final match in matches) {
        matchesByPage.putIfAbsent(match.pageIndex, () => []).add(match);
      }

      for (final entry in matchesByPage.entries) {
        final pageIndex = entry.key;
        final pageMatches = entry.value;

        final textLines = pageMatches
            .map((m) => PdfTextLine(m.bounds, wordColor.word, pageIndex + 1))
            .toList();

        final annotation = HighlightAnnotation(textBoundsCollection: textLines);
        annotation.color = wordColor.color;
        annotation.opacity = 0.4;

        _pdfViewerController.addAnnotation(annotation);
      }
    } catch (e) {
      debugPrint('Error adding highlight overlay for "${wordColor.word}": $e');
    }
  }

  // ── Page navigation ──

  void _showGoToPageDialog() {
    if (_totalPages == 0) return;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to Page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '1 - $_totalPages',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            _navigateToPage(value);
            Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _navigateToPage(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  void _navigateToPage(String value) {
    final pageNum = int.tryParse(value.trim());
    if (pageNum == null || pageNum < 1 || pageNum > _totalPages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid page number (1 - $_totalPages)')),
      );
      return;
    }
    _pdfViewerController.jumpToPage(pageNum);
  }

  // ── Highlight filter dialog ──

  Future<bool> _confirmLargePdfHighlights() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Highlights?'),
        content: const Text(
          'Highlights on large PDFs can be slow and may cause stutter. Do you want to enable them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _showHighlightFilterDialog() async {
    if (_isLargePdf && !_allowLargePdfHighlights) {
      final proceed = await _confirmLargePdfHighlights();
      if (!proceed) {
        _maybeShowLargePdfNotice();
        return;
      }
      _allowLargePdfHighlights = true;
    }
    final Set<int> tempSelected = _selectedListIds.toSet();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Highlight Filter'),
            content: SizedBox(
              width: double.maxFinite,
              child: _availableLists.isEmpty
                  ? const Text('No lists available.')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _availableLists.length,
                      itemBuilder: (context, index) {
                        final list = _availableLists[index];
                        final id = list['id'] as int;
                        final isSelected = tempSelected.contains(id);

                        return CheckboxListTile(
                          title: Text(list['name']),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setDialogState(() {
                              if (value == true) {
                                tempSelected.add(id);
                              } else {
                                tempSelected.remove(id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    tempSelected.clear();
                    tempSelected
                        .addAll(_availableLists.map((l) => l['id'] as int));
                  });
                },
                child: const Text('Select All'),
              ),
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    tempSelected.clear();
                  });
                },
                child: const Text('Clear All'),
              ),
              ElevatedButton(
                onPressed: () {
                  _selectedListIds = tempSelected.toList();
                  Navigator.pop(context);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        });
      },
    );

    await _applyHighlightOverlays();
  }

  void _showTranslation(String text) async {
    if (_showReaderTutorial && _readerTutorialStep == 1) {
      _advanceReaderTutorial(2);
    }

    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 1.0,
        expand: false,
        builder: (_, controller) => TranslationSheet(
          word: text,
          sentence: "",
          scrollController: controller,
        ),
      ),
    );

    _clearWordSelection();

    if (result is WordColor) {
      await _addWordHighlightOverlay(result);
      if (_showReaderTutorial && _readerTutorialStep >= 2) {
        await _completeReaderTutorial();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_pdfFile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Failed to load PDF')),
      );
    }

    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) return;

          final spentMinutes =
              DateTime.now().difference(_sessionStartedAt).inMinutes;
          if (spentMinutes > 0) {
            try {
              final bumpedStreak = await _databaseService.logLearningActivity(
                readingMinutesDelta: spentMinutes,
              );
              if (bumpedStreak && mounted) {
                final streakData =
                    await _databaseService.getLearningStreakStats();
                if (mounted) {
                  await StreakAnimationOverlay.show(context,
                      newStreak: streakData['current'] ?? 0);
                }
              }
            } catch (_) {}
          }

          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: _showGoToPageDialog,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _totalPages > 0
                        ? 'Page $_currentPage / $_totalPages'
                        : 'Reader',
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (_totalPages > 0) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 14),
                  ],
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  _cachedTextLines.clear();
                  _extractionDocument?.dispose();
                  _extractionDocument = null;
                  await _loadPdf();
                },
              ),
              IconButton(
                icon: Icon(_selectedListIds.isEmpty
                    ? Icons.filter_alt_off
                    : Icons.filter_alt),
                onPressed: _showHighlightFilterDialog,
              ),
            ],
          ),
          body: Stack(
            children: [
              SfPdfViewer.file(
                _pdfFile!,
                key: ValueKey(widget.filePath),
                controller: _pdfViewerController,
                pageLayoutMode: _isLargePdf
                    ? PdfPageLayoutMode.single
                    : PdfPageLayoutMode.continuous,
                interactionMode: PdfInteractionMode.selection,
                pageSpacing: _isLargePdf ? 0 : 4,
                canShowScrollHead: true,
                canShowScrollStatus: true,
                canShowPaginationDialog: true,
                canShowSignaturePadDialog: !_isLargePdf,
                enableDocumentLinkAnnotation: !_isLargePdf,
                enableHyperlinkNavigation: !_isLargePdf,
                canShowHyperlinkDialog: !_isLargePdf,
                enableDoubleTapZooming: true,
                useFilePathOnAndroid: true,
                enableFullTextExtraction: false,
                maxRenderPixels: _isLargePdf ? 1500000 : 6000000,
                maxDevicePixelRatio: _isLargePdf ? 1.5 : 2.0,
                initialScrollOffset: _preservedScrollOffset ?? Offset.zero,
                initialZoomLevel: _preservedZoomLevel ?? 1.0,
                maxZoomLevel: _isLargePdf ? 2 : 3,
                enableTextSelection: true,
                canShowTextSelectionMenu: false,
                onDocumentLoaded: (PdfDocumentLoadedDetails details) async {
                  _pdfLoaded = true;
                  setState(() {
                    _totalPages = details.document.pages.count;
                  });

                  // Load extraction document for word tapping
                  await _loadExtractionDocument();

                  if (_isLargePdf) {
                    _maybeShowLargePdfNotice();
                    return;
                  }
                  _applyHighlightOverlays();
                },
                onPageChanged: (PdfPageChangedDetails details) {
                  setState(() {
                    _currentPage = details.newPageNumber;
                  });
                },
                onTap: (PdfGestureDetails details) {
                  _handleWordTap(details);
                },
                onTextSelectionChanged:
                    (PdfTextSelectionChangedDetails details) {
                  // Keep long-press selection as fallback
                  if (details.selectedText != null &&
                      details.selectedText!.trim().isNotEmpty) {
                    final text = details.selectedText!.trim();
                    // Add the selected text as if it were tapped words
                    setState(() {
                      _selectedWords.clear();
                      _selectedWords.add(_SelectedWord(
                        text: text,
                        bounds: Rect.zero,
                        pageIndex: _currentPage - 1,
                      ));
                      _showWordActions = true;
                    });
                  }
                },
              ),

              // Word action bar
              if (_showWordActions && _selectedWords.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 32,
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: AppColors.border, width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Selected text preview
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (_selectedWords.length > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_selectedWords.length} words',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildLargeActionButton(
                                  icon: Icons.translate,
                                  label: 'Translate',
                                  onTap: () {
                                    final selected = _selectedText;
                                    if (selected.isEmpty) return;
                                    _showTranslation(selected);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildLargeActionButton(
                                  icon: Icons.copy,
                                  label: 'Copy',
                                  onTap: _copySelectedWords,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildLargeActionButton(
                                  icon: Icons.close,
                                  label: 'Cancel',
                                  onTap: _clearWordSelection,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (_showReaderTutorial && _isSamplePdf && _readerTutorialVisible)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: SafeArea(
                    bottom: false,
                    child: _buildReaderTutorialCard(),
                  ),
                ),
            ],
          ),
        ));
  }

  Widget _buildLargeActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      ),
    );
  }

  Widget _buildReaderTutorialCard() {
    final steps = [
      _TutorialStep(
        imagePath: 'assets/fox_tutorial/casual.png',
        message: 'Tap any word to select it. Tap more words to select multiple!',
      ),
      _TutorialStep(
        imagePath: 'assets/fox_tutorial/joyful.png',
        message: 'Tap Translate to open the word sheet.',
      ),
      _TutorialStep(
        imagePath: 'assets/fox_tutorial/embarresed.png',
        message: 'Pick a list and hit Save. Please do not judge my diary...',
      ),
    ];

    final stepIndex = _readerTutorialStep.clamp(0, steps.length - 1);
    final step = steps[stepIndex];
    final stepLabel = 'Step ${stepIndex + 1} of ${steps.length}';

    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stepLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _hideReaderTutorial,
                  icon: const Icon(Icons.close),
                  tooltip: 'Hide',
                ),
              ],
            ),
            const SizedBox(height: 8),
            PixelTextBubble(
              text: step.message,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            const SizedBox(height: 10),
            Image.asset(
              step.imagePath,
              height: 230,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _completeReaderTutorial,
                    child: const Text('Skip Tutorial'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialStep {
  final String imagePath;
  final String message;

  const _TutorialStep({
    required this.imagePath,
    required this.message,
  });
}

class _SelectedWord {
  final String text;
  final Rect bounds;
  final int pageIndex;

  const _SelectedWord({
    required this.text,
    required this.bounds,
    required this.pageIndex,
  });
}
