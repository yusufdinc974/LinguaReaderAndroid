import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';

class TutorialService {
  static const String tutorialSeenKey = 'tutorial_seen';
  static const String sampleOpenedKey = 'tutorial_sample_opened';
  static const String readerTutorialCompletedKey = 'tutorial_reader_completed';
  static const String sampleVersionKey = 'tutorial_sample_version';
  static const int sampleVersion = 6;

  static const String sampleAssetPath = 'assets/tutorial_getting_started.pdf';
  static const String sampleFileName = 'LinguaReader_Quick_Start.pdf';
  static const String sampleDisplayName = "Lexi's Diary (Sample)";

  static Future<String> getSamplePdfPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, sampleFileName);
  }

  static Future<String> ensureSamplePdf() async {
    final path = await getSamplePdfPath();
    final file = File(path);
    final bytes = await rootBundle.load(sampleAssetPath);
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    await DatabaseService()
        .saveSetting(sampleVersionKey, sampleVersion.toString());

    final db = DatabaseService();
    final existsInRecents = await db.hasRecentPdfPath(path);
    if (!existsInRecents) {
      await db.addRecentPdf(sampleDisplayName, path);
    }

    return path;
  }

  static Future<bool> isTutorialSeen() async {
    final value = await DatabaseService().getSetting(tutorialSeenKey);
    return value == '1';
  }

  static Future<void> markTutorialSeen() async {
    await DatabaseService().saveSetting(tutorialSeenKey, '1');
  }

  static Future<bool> isSampleOpened() async {
    final value = await DatabaseService().getSetting(sampleOpenedKey);
    return value == '1';
  }

  static Future<void> markSampleOpened() async {
    await DatabaseService().saveSetting(sampleOpenedKey, '1');
  }

  static Future<void> markSampleOpenedIfMatches(String filePath) async {
    final samplePath = await getSamplePdfPath();
    if (filePath == samplePath) {
      await markSampleOpened();
    }
  }

  static Future<bool> isReaderTutorialCompleted() async {
    final value =
        await DatabaseService().getSetting(readerTutorialCompletedKey);
    return value == '1';
  }

  static Future<void> markReaderTutorialCompleted() async {
    await DatabaseService().saveSetting(readerTutorialCompletedKey, '1');
  }
}
