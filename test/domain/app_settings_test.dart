import 'package:apple_file_converter/domain/conversion/conversion_request.dart';
import 'package:apple_file_converter/domain/conversion/image_spec.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:apple_file_converter/domain/media/media_item.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/domain/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings defaults', () {
    test('targets JPEG and MP4 out of the box', () {
      const settings = AppSettings();
      expect(settings.defaultImageFormat, ImageFormat.jpeg);
      expect(settings.defaultVideoContainer.name, 'mp4');
      expect(settings.defaultImageQuality, 90);
      expect(settings.theme, ThemePreference.system);
      expect(settings.exportDestination, ExportDestination.gallery);
      expect(settings.confirmBeforeDelete, isTrue);
    });

    test('derives a naming policy from the template', () {
      const settings = AppSettings(namingTemplate: '{name}_x');
      expect(settings.namingPolicy.template, '{name}_x');
    });
  });

  group('AppSettings serialisation', () {
    test('round-trips through a map', () {
      const settings = AppSettings(
        theme: ThemePreference.dark,
        defaultImageFormat: ImageFormat.png,
        defaultImageQuality: 77,
        confirmBeforeDelete: false,
        galleryGridColumns: 4,
        gallerySort: SortField.name,
        gallerySortAscending: true,
        batchConcurrency: 3,
        customExportPath: '/exports',
      );
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.theme, ThemePreference.dark);
      expect(restored.defaultImageFormat, ImageFormat.png);
      expect(restored.defaultImageQuality, 77);
      expect(restored.confirmBeforeDelete, isFalse);
      expect(restored.galleryGridColumns, 4);
      expect(restored.gallerySort, SortField.name);
      expect(restored.gallerySortAscending, isTrue);
      expect(restored.batchConcurrency, 3);
      expect(restored.customExportPath, '/exports');
    });

    test('substitutes defaults for corrupt values', () {
      final restored = AppSettings.fromMap(<String, Object?>{
        'defaultImageFormat': 'not-a-format',
        'defaultImageQuality': 999,
        'galleryGridColumns': 'abc',
        'gallerySort': 'nonsense',
        'theme': 'neon',
        'batchConcurrency': 'x',
      });
      expect(restored.defaultImageFormat, ImageFormat.jpeg);
      expect(restored.defaultImageQuality, 100);
      expect(restored.galleryGridColumns, 3);
      expect(restored.gallerySort, SortField.dateModified);
      expect(restored.theme, ThemePreference.system);
      expect(restored.batchConcurrency, isNull);
    });

    test('clamps batch concurrency into the supported range', () {
      expect(
        AppSettings.fromMap(<String, Object?>{'batchConcurrency': 99})
            .batchConcurrency,
        8,
      );
      expect(
        AppSettings.fromMap(<String, Object?>{'batchConcurrency': 0})
            .batchConcurrency,
        1,
      );
    });

    test('effectiveConcurrency uses the hardware suggestion when unset', () {
      const settings = AppSettings();
      expect(settings.effectiveConcurrency(4), 4);
      expect(settings.effectiveConcurrency(99), 8);
    });
  });

  group('AppSettings.copyWith', () {
    test('can clear the custom export path', () {
      const settings = AppSettings(customExportPath: '/x');
      expect(
        settings.copyWith(clearCustomExportPath: true).customExportPath,
        isNull,
      );
    });

    test('can clear batch concurrency', () {
      const settings = AppSettings(batchConcurrency: 4);
      expect(
        settings.copyWith(clearBatchConcurrency: true).batchConcurrency,
        isNull,
      );
    });
  });

  group('ImageConversionRequest', () {
    test('reports the output extension and requires encoding', () {
      const request = ImageConversionRequest(
        source: MediaItem(id: '1', kind: MediaKind.image),
        spec: ImageConversionSpec(outputFormat: ImageFormat.webp),
      );
      expect(request.outputExtension, 'webp');
      expect(request.requiresEncoding, isTrue);
    });
  });
}
