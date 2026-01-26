import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/database_service.dart';
import '../../../core/constants/app_colors.dart';
import '../sync/qr_scan_screen.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  final _databaseService = DatabaseService();
  bool _isExporting = false;
  bool _isImporting = false;

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      // 1. Get Data
      final data = await _databaseService.getAllData();
      final jsonString = jsonEncode(data);

      // 2. Write to Temp File
      final directory = await getTemporaryDirectory();
      final date = DateTime.now().toIso8601String().split('T')[0];
      final file = File('${directory.path}/linguareader_backup_$date.json');
      await file.writeAsString(jsonString);

      // 3. Share File
      final xFile = XFile(file.path);
      await Share.shareXFiles([xFile], text: 'LinguaReader Backup');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export ready. Select an app to save/send.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importData() async {
    setState(() => _isImporting = true);
    try {
      // 1. Pick File
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final data = jsonDecode(jsonString) as Map<String, dynamic>;

        // 2. Import Data
        await _databaseService.importData(data);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data imported successfully!')),
          );
        }
      } else {
        // User canceled
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Sync Section ---
          const Text(
            'Synchronization',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sync with your Desktop app instantly by scanning a QR code.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
            title: const Text('Sync with Desktop'),
            subtitle: const Text('Scan QR code'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const QrScanScreen()),
              );
            },
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: AppColors.secondary.withOpacity(0.1),
          ),
          const SizedBox(height: 32),

          // --- Backup Section ---
          const Text(
            'Backup & Restore',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Export your data to a JSON file to transfer it to another device or backup your progress.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          
          ListTile(
            leading: const Icon(Icons.download, color: AppColors.success),
            title: const Text('Export Data'),
            subtitle: const Text('Save backup file'),
            onTap: _isExporting ? null : _exportData,
            trailing: _isExporting 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Icon(Icons.arrow_forward_ios, size: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: AppColors.secondary.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.upload, color: AppColors.primary),
            title: const Text('Import Data'),
            subtitle: const Text('Restore from backup file'),
            onTap: _isImporting ? null : _importData,
            trailing: _isImporting 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Icon(Icons.arrow_forward_ios, size: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: AppColors.secondary.withOpacity(0.1),
          ),
        ],
      ),
    );
  }
}
