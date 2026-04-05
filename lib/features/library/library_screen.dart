import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/fox_sprite.dart';
import '../../core/widgets/pixel_card.dart';
import '../../services/database_service.dart';
import '../../services/subscription_service.dart';
import '../reader/reader_screen.dart';
import '../subscription/paywall_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _databaseService = DatabaseService();
  List<Map<String, dynamic>> _pdfs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPdfs();
  }

  Future<void> _loadPdfs() async {
    setState(() => _isLoading = true);
    try {
      final pdfs = await _databaseService.getRecentPdfs();
      if (mounted) {
        setState(() {
          _pdfs = pdfs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickFile() async {
    final isPremium = await SubscriptionService.isPremium();
    if (!isPremium) {
      final count = await _databaseService.getPdfCount();
      if (count >= 5) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PaywallScreen()),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Free tier is limited to 5 PDFs. Upgrade to Premium for unlimited storage!')),
          );
        }
        return;
      }
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      final path = result.files.single.path;
      final name = result.files.single.name;

      if (path != null) {
        await _databaseService.addRecentPdf(name, path);
        await _loadPdfs();

        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
                builder: (context) => ReaderScreen(filePath: path)),
          );
          _loadPdfs();
        }
      }
    }
  }

  Future<void> _openPdf(Map<String, dynamic> pdf) async {
    final path = pdf['path'] as String;
    final file = File(path);

    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'File not found. It may have been moved or deleted.'),
            action: SnackBarAction(
              label: 'Remove',
              onPressed: () => _deletePdf(pdf['id'] as int),
            ),
          ),
        );
      }
      return;
    }

    // Update last_opened timestamp
    await _databaseService.addRecentPdf(
      pdf['name'] as String,
      path,
    );

    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (context) => ReaderScreen(filePath: path)),
      );
      _loadPdfs();
    }
  }

  Future<void> _deletePdf(int id) async {
    await _databaseService.deleteRecentPdf(id);
    _loadPdfs();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d, y').format(date);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Library')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pdfs.isEmpty
              ? _buildEmptyState()
              : _buildPdfList(),
      floatingActionButton: _pdfs.isNotEmpty
          ? FloatingActionButton(
              onPressed: _pickFile,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: const FoxSpriteAnimator(
                animation: FoxAnimation.idleSouth,
                size: 80,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Library is Empty',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Import PDF books to start building your personal collection and tracking your vocabulary.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PixelCard(
                child: ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text("Import PDF Book"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfList() {
    return RefreshIndicator(
      onRefresh: _loadPdfs,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _pdfs.length,
        itemBuilder: (context, index) {
          final pdf = _pdfs[index];
          final name = (pdf['name'] as String?) ?? 'Unknown PDF';
          final displayName =
              name.endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
          final dateStr = _formatDate(pdf['last_opened'] as String?);

          return Dismissible(
            key: ValueKey(pdf['id']),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Remove PDF?'),
                  content: const Text(
                      'This will remove the PDF from your library. The file itself will not be deleted.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (_) => _deletePdf(pdf['id'] as int),
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.border, width: 1.5),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 44,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.5)),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                ),
                title: Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: dateStr.isNotEmpty
                    ? Text(
                        'Opened $dateStr',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      )
                    : null,
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _openPdf(pdf),
              ),
            ),
          );
        },
      ),
    );
  }
}
