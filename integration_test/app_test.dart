import 'package:apple_file_converter/app/app.dart';
import 'package:apple_file_converter/app/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-device smoke test.
///
/// Unlike the widget test in `test/ui/`, this boots the **real** composition root
/// ([AppServices.bootstrap]) with the actual plugins: `shared_preferences`, `sqflite`,
/// `path_provider` and `photo_manager`. It proves the app starts on a real Android/iOS device
/// and that the empty states render without a platform channel throwing.
///
/// Run with a connected device or emulator:
///   flutter test integration_test/app_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real services boot and every tab renders', (tester) async {
    final services = await AppServices.bootstrap();
    addTearDown(services.coordinator.dispose);

    await tester.pumpWidget(AppleFileConverterApp(services: services));
    // Fixed frames rather than pumpAndSettle: the gallery/home skeleton animates forever.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in <String>[
      'Home',
      'Gallery',
      'Convert',
      'Tools',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets, reason: 'missing $label tab');
    }

    // Tools and Settings never require a permission prompt, so they are safe to open here.
    await tester.tap(find.text('Tools'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Compress photos'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
