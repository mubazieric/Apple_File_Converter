import 'dart:convert';

import 'package:apple_file_converter/domain/conversion/conversion_error.dart';
import 'package:apple_file_converter/domain/conversion/conversion_request.dart';
import 'package:apple_file_converter/domain/conversion/image_spec.dart';
import 'package:apple_file_converter/domain/conversion/metadata_policy.dart';
import 'package:apple_file_converter/domain/conversion/naming_policy.dart';
import 'package:apple_file_converter/domain/conversion/video_spec.dart';
import 'package:apple_file_converter/domain/media/image_format.dart';
import 'package:apple_file_converter/domain/media/media_item.dart';
import 'package:apple_file_converter/domain/media/media_kind.dart';
import 'package:apple_file_converter/domain/media/video_format.dart';
import 'package:apple_file_converter/domain/queue/conversion_job.dart';
import 'package:apple_file_converter/domain/queue/conversion_queue.dart';
import 'package:apple_file_converter/domain/queue/job_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Encodes a snapshot to a JSON string and back, exactly like the on-disk store does, so the
/// tests prove the serialisation survives real JSON — not just in-memory maps.
List<Map<String, Object?>> _roundTrip(List<Map<String, Object?>> snapshot) {
  final decoded = jsonDecode(jsonEncode(snapshot)) as List<dynamic>;
  return decoded
      .cast<Map<String, dynamic>>()
      .map((map) => map.cast<String, Object?>())
      .toList();
}

MediaItem _imageSource() => MediaItem(
  id: 'asset-1',
  kind: MediaKind.image,
  displayName: 'beach.HEIC',
  path: '/media/beach.HEIC',
  mimeType: 'image/heic',
  sizeBytes: 2000000,
  width: 4032,
  height: 3024,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  imageFormat: ImageFormat.heic,
  isFavorite: true,
);

MediaItem _videoSource() => const MediaItem(
  id: 'asset-2',
  kind: MediaKind.video,
  displayName: 'clip.MOV',
  path: '/media/clip.MOV',
  sizeBytes: 8000000,
  width: 1920,
  height: 1080,
  duration: Duration(seconds: 12),
  videoContainer: VideoContainer.mov,
);

void main() {
  group('ConversionRequest serialisation', () {
    test('an image request survives a JSON round-trip', () {
      final request = ImageConversionRequest(
        source: _imageSource(),
        spec: const ImageConversionSpec(
          outputFormat: ImageFormat.jpeg,
          quality: 82,
          resize: ResizeSpec.longestEdge(1920),
          rotation: Rotation.clockwise90,
          flip: FlipAxis.horizontal,
          watermark: WatermarkSpec(text: 'Iwat Digital'),
        ),
        metadataPolicy: MetadataPolicy.preserve,
        naming: const NamingPolicy(template: '{name}-{format}'),
      );

      final restored = ConversionRequest.fromJson(
        _roundTrip(<Map<String, Object?>>[request.toJson()]).single,
      );

      expect(restored, isA<ImageConversionRequest>());
      final image = restored as ImageConversionRequest;
      expect(image.source.id, 'asset-1');
      expect(image.source.imageFormat, ImageFormat.heic);
      expect(image.source.isFavorite, isTrue);
      expect(
        image.source.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(image.spec.outputFormat, ImageFormat.jpeg);
      expect(image.spec.quality, 82);
      expect(image.spec.resize.mode, ResizeMode.longestEdge);
      expect(image.spec.resize.longestEdge, 1920);
      expect(image.spec.rotation, Rotation.clockwise90);
      expect(image.spec.flip, FlipAxis.horizontal);
      expect(image.spec.watermark?.text, 'Iwat Digital');
      expect(image.metadataPolicy, MetadataPolicy.preserve);
      expect(image.naming.template, '{name}-{format}');
    });

    test('a video request survives a JSON round-trip', () {
      final request = VideoConversionRequest(
        source: _videoSource(),
        spec: const VideoConversionSpec(
          container: VideoContainer.webm,
          videoCodec: VideoCodec.vp9,
          audioCodec: AudioCodec.opus,
          resolution: ResolutionPreset.p1080,
          frameRate: 30,
          trimStart: Duration(seconds: 1),
          trimEnd: Duration(seconds: 5),
          speed: SpeedMode.x2,
          quality: VideoQuality.high,
        ),
      );

      final restored = ConversionRequest.fromJson(
        _roundTrip(<Map<String, Object?>>[request.toJson()]).single,
      );

      expect(restored, isA<VideoConversionRequest>());
      final video = restored as VideoConversionRequest;
      expect(video.source.duration, const Duration(seconds: 12));
      expect(video.spec.container, VideoContainer.webm);
      expect(video.spec.videoCodec, VideoCodec.vp9);
      expect(video.spec.audioCodec, AudioCodec.opus);
      expect(video.spec.resolution, ResolutionPreset.p1080);
      expect(video.spec.frameRate, 30);
      expect(video.spec.trimStart, const Duration(seconds: 1));
      expect(video.spec.trimEnd, const Duration(seconds: 5));
      expect(video.spec.speed, SpeedMode.x2);
      expect(video.spec.quality, VideoQuality.high);
    });
  });

  group('queue snapshot & restore', () {
    ConversionJob imageJob(String id) => ConversionJob(
      id: id,
      request: ImageConversionRequest(
        source: _imageSource(),
        spec: const ImageConversionSpec(),
      ),
    );

    test('a pending batch is rebuilt after a restart', () {
      final queue = ConversionQueue()
        ..enqueue(<ConversionJob>[
          imageJob('a'),
          ConversionJob(
            id: 'b',
            request: VideoConversionRequest(
              source: _videoSource(),
              spec: const VideoConversionSpec(),
            ),
          ),
        ]);
      queue.start('b'); // b is mid-flight when the process is killed.

      final restoredQueue = ConversionQueue()
        ..restore(_roundTrip(queue.pendingSnapshot()));
      expect(restoredQueue.jobs.length, 2);
      expect(restoredQueue.jobById('a')!.status, JobStatus.queued);
      expect(restoredQueue.jobById('b')!.status.isActive, isTrue);

      // A job that was running when the process died must never look like it is still running.
      expect(restoredQueue.recoverAfterRestart(), 1);
      expect(restoredQueue.jobById('b')!.status, JobStatus.failed);
      expect(restoredQueue.jobById('b')!.error, isNotNull);
      expect(restoredQueue.jobById('a')!.status, JobStatus.queued);
    });

    test('pendingSnapshot drops terminal jobs', () {
      final queue = ConversionQueue()
        ..enqueue(<ConversionJob>[imageJob('done'), imageJob('waiting')]);
      queue.start('done');
      queue.complete(
        'done',
        const ConversionSuccess(
          outputPath: '/out/done.jpg',
          outputBytes: 1000,
          sourceBytes: 4000,
        ),
      );

      final snapshot = queue.pendingSnapshot();
      expect(snapshot.map((map) => map['id']), <String>['waiting']);
    });

    test('an unreadable entry is skipped without losing the rest', () {
      final queue = ConversionQueue();
      final restored = queue.restore(<Map<String, Object?>>[
        <String, Object?>{'id': 'garbage', 'status': 'queued'}, // No request.
        <String, Object?>{
          'id': 'good',
          'status': 'queued',
          'request': ImageConversionRequest(
            source: _imageSource(),
            spec: const ImageConversionSpec(),
          ).toJson(),
        },
      ]);
      expect(restored, 1);
      expect(queue.jobs.single.id, 'good');
    });
  });
}
