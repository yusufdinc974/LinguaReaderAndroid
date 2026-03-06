import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/constants/app_colors.dart';
import 'widgets/translation_sheet.dart';
import '../../services/database_service.dart';
import '../../services/pdf_highlight_service.dart';

class ReaderScreen extends StatefulWidget {
  final String filePath;

  const ReaderScreen({super.key, required this.filePath});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final DatabaseService _databaseService = DatabaseService();

  PdfTextSelectionChangedDetails? _selectionDetails;
  Uint8List? _pdfBytes; // Original PDF bytes (never modified)
  bool _isLoading = true;
  bool _pdfLoaded = false; // Track if PDF document is loaded in viewer
  Offset? _preservedScrollOffset;
  double? _preservedZoomLevel;
  List<int> _selectedListIds = []; // Empty means ALL lists
  List<Map<String, dynamic>> _availableLists = [];
  String? _tempSelectedText;
  bool _showSelectionActions = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  /// Load the raw PDF bytes (without any baked highlights)
  Future<void> _loadPdf() async {
    setState(() => _isLoading = true);
    try {
      // 1. Read original file bytes (never modify these)
      final File file = File(widget.filePath);
      final rawBytes = await file.readAsBytes();

      // 2. Fetch available lists for filter
      _availableLists = await _databaseService.getWordLists();

      // Initialize with all list IDs so UI matches behavior (All checked initially)
      _selectedListIds = _availableLists.map((l) => l['id'] as int).toList();

      if (mounted) {
        setState(() {
          _pdfBytes = rawBytes;
          _isLoading = false;
          _pdfLoaded = false; // Will be set true when document loads
        });
      }
    } catch (e) {
      debugPrint('Error loading PDF: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Apply highlight overlays based on current filter selection
  /// This uses controller annotations (not baked into PDF bytes)
  Future<void> _applyHighlightOverlays() async {
    if (_pdfBytes == null || !_pdfLoaded) return;

    try {
      // 1. CLEAR all existing overlay annotations first
      _pdfViewerController.removeAllAnnotations();

      // If explicit empty selection, show NOTHING
      if (_selectedListIds.isEmpty) {
        return;
      }

      // 2. Get words based on filter
      final wordsData =
          await _databaseService.getWordsWithColors(listIds: _selectedListIds);

      if (wordsData.isEmpty) return;

      // 3. Convert to WordColor objects
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

      // 4. Add overlay annotations for each word
      for (final wordColor in words) {
        await _addWordHighlightOverlay(wordColor);
      }
    } catch (e) {
      debugPrint('Error applying highlight overlays: $e');
    }
  }

  /// Add highlight overlay for a single word
  Future<void> _addWordHighlightOverlay(WordColor wordColor) async {
    if (_pdfBytes == null || wordColor.word.trim().isEmpty) return;

    try {
      final matches =
          await PdfHighlightService.findText(_pdfBytes!, wordColor.word);

      // Group matches by page
      final Map<int, List<MatchedItem>> matchesByPage = {};
      for (final match in matches) {
        matchesByPage.putIfAbsent(match.pageIndex, () => []).add(match);
      }

      // Add annotation for each page
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

  void _clearSelectionState() {
    _pdfViewerController.clearSelection();
    setState(() {
      _selectionDetails = null;
      _tempSelectedText = null;
      _showSelectionActions = false;
    });
  }

  Future<void> _copySelectedText() async {
    final text = _tempSelectedText?.trim();
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
    _clearSelectionState();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_pdfBytes == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Failed to load PDF')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadPdf();
              // Highlights will be applied when document loads
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
          SfPdfViewer.memory(
            _pdfBytes!,
            key: ValueKey(widget.filePath), // Stable key based on file path
            controller: _pdfViewerController,
            initialScrollOffset: _preservedScrollOffset ?? Offset.zero,
            initialZoomLevel: _preservedZoomLevel ?? 1.0,
            enableTextSelection: true,
            canShowTextSelectionMenu: false,
            onDocumentLoaded: (PdfDocumentLoadedDetails details) {
              // Document is now ready for annotations
              _pdfLoaded = true;
              // Apply initial highlights
              _applyHighlightOverlays();
            },
            onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
              if (details.selectedText == null ||
                  details.selectedText!.trim().isEmpty) {
                setState(() {
                  _selectionDetails = null;
                  _tempSelectedText = null;
                  _showSelectionActions = false;
                });
                return;
              }

              final text = details.selectedText!.trim();
              if (text.isNotEmpty) {
                setState(() {
                  _selectionDetails = details;
                  _tempSelectedText = text;
                  _showSelectionActions = false;
                });
              }
            },
          ),
          if (_selectionDetails != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Card(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _showSelectionActions
                      ? Row(
                          children: [
                            Expanded(
                              child: _buildLargeActionButton(
                                icon: Icons.translate,
                                label: 'Translate',
                                onTap: () {
                                  final selected = _tempSelectedText?.trim();
                                  if (selected == null || selected.isEmpty) {
                                    return;
                                  }
                                  _showTranslation(selected);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildLargeActionButton(
                                icon: Icons.copy,
                                label: 'Copy',
                                onTap: _copySelectedText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildLargeActionButton(
                                icon: Icons.close,
                                label: 'Cancel',
                                onTap: _clearSelectionState,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Selection ready (${(_tempSelectedText ?? '').length} chars)',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() => _showSelectionActions = true);
                              },
                              icon: const Icon(Icons.touch_app, size: 20),
                              label: const Text('Actions'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(132, 52),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _clearSelectionState,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(88, 52),
                              ),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
        ],
      ),
    );
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

  Future<void> _showHighlightFilterDialog() async {
    // Clone current selection to temp set
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

    // Apply new filter (clear old annotations and add new ones)
    await _applyHighlightOverlays();
  }

  void _showTranslation(String text) async {
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

    // Clear selection UI
    _clearSelectionState();

    // If word was saved, add instant highlight overlay
    if (result is WordColor) {
      await _addWordHighlightOverlay(result);
    }
  }
}
