import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:linguareader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: LinguaReaderApp()));

    // Verify that the app builds and shows the title (or Home screen).
    // ReviewDashboard is on the home screen, let's look for "Review Due" text.
    await tester.pumpAndSettle(); // Wait for animations and futures
    
    // Since we have async data loading, we might see a loader first or the content.
    // For a basic smoke test, just ensuring it doesn't crash is good.
    // But let's check for a known string 'LinguaReader' in AppBar.
    expect(find.text('LinguaReader'), findsOneWidget);
  });
}
