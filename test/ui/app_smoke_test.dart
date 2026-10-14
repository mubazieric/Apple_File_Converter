import 'dart:io';

import 'package:apple_file_converter/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/in_memory_services.dart';

/// Builds the real widget tree with in-memory services and walks every bottom-navigation tab.
///
/// This is the broadest automated check that the whole UI composes: every screen is built,
/// no screen touches a platform channel it should not, and the app renders on a phone-sized
/// surface without throwing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('afc_smoke_');
  });

  tearDown(() {
    disposeTestDirectory(root);
  });

  testWidgets('every bottom-navigation tab renders without error', (
    WidgetTester tester,
  ) async {
    final services = await buildTestServices(directory: root);
    addTearDown(services.coordinator.dispose);

    await tester.pumpWidget(AppleFileConverterApp(services: services));
    // Let the post-frame callbacks (history, storage, consent) settle. We pump fixed frames
    // rather than pumpAndSettle because the skeleton loader animates forever.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Home tab.
    expect(find.text('Apple File Converter'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);

    // The five destinations are all present.
    for (final label in <String>[
      'Home',
      'Gallery',
      'Convert',
      'Tools',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing $label tab');
    }

    // Gallery tab: no system photo library in tests, so the honest empty state shows.
    await tester.tap(find.text('Gallery'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gallery unavailable on this platform'), findsOneWidget);

    // Convert tab.
    await tester.tap(find.text('Convert'));
    await tester.pump(const Duration(milliseconds: 300));

    // Tools tab.
    await tester.tap(find.text('Tools'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Compress photos'), findsOneWidget);

    // Settings tab.
    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('switching tabs keeps the app alive and returns home', (
    WidgetTester tester,
  ) async {
    final services = await buildTestServices(directory: root);
    addTearDown(services.coordinator.dispose);

    await tester.pumpWidget(AppleFileConverterApp(services: services));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.text('Apple File Converter'), findsWidgets);
  });
}
