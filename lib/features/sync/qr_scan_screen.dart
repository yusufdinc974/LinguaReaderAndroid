import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import '../../services/database_service.dart';
import '../../core/constants/app_colors.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final DatabaseService _databaseService = DatabaseService();
  bool _isSyncing = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isSyncing || _isSuccess) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _startSync(barcode.rawValue!);
        break;
      }
    }
  }

  Future<void> _startSync(String qrData) async {
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Connecting to Desktop...';
    });

    try {
      final data = jsonDecode(qrData);
      final String ip = data['ip'];
      final int port = data['port'];
      final String pin = data['pin'];
      final String baseUrl = 'http://$ip:$port';

      // 1. Handshake ? (Skip for speed, go straight to upload/download)
      
      // 2. Upload Data (Mobile -> Desktop)
      setState(() => _statusMessage = 'Uploading data...');
      final mobileData = await _databaseService.getAllData();
      
      final uploadResponse = await http.post(
        Uri.parse('$baseUrl/sync/upload'),
        headers: {
          'Content-Type': 'application/json',
          'x-auth-pin': pin,
        },
        body: jsonEncode(mobileData),
      ).timeout(const Duration(seconds: 30));

      if (uploadResponse.statusCode != 200) {
        throw Exception('Upload failed: ${uploadResponse.body}');
      }

      // 3. Download Data (Desktop -> Mobile)
      setState(() => _statusMessage = 'Downloading data...');
      final downloadResponse = await http.get(
        Uri.parse('$baseUrl/sync/download'),
        headers: {
           'x-auth-pin': pin,
        },
      ).timeout(const Duration(seconds: 30));

      if (downloadResponse.statusCode != 200) {
        throw Exception('Download failed: ${downloadResponse.body}');
      }

      final desktopData = jsonDecode(downloadResponse.body);
      
      // 4. Import Data
      setState(() => _statusMessage = 'Importing data...');
      await _databaseService.importData(desktopData);

      setState(() {
        _isSyncing = false;
        _isSuccess = true;
        _statusMessage = 'Sync Complete!';
      });

      // Close after delay
      // Future.delayed(const Duration(seconds: 2), () {
      //   if (mounted) Navigator.pop(context);
      // });

    } catch (e) {
      setState(() {
        _isSyncing = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync with Desktop')),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: _isSuccess 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 80),
                      const SizedBox(height: 16),
                      Text('Sync Successful!', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      )
                    ],
                  ),
                )
              : Stack(
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                    ),
                    // Overlay
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black54, width: 0),
                      ),
                      child: Center(
                        child: Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary, width: 3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(24),
              width: double.infinity,
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _statusMessage ?? 'Scan the QR code displayed on your Desktop app',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: _statusMessage != null && _statusMessage!.startsWith('Error') 
                          ? AppColors.error 
                          : AppColors.textPrimary,
                      fontWeight: _isSyncing ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (_isSyncing) ...[
                    const SizedBox(height: 24),
                    const CircularProgressIndicator(),
                  ]
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
