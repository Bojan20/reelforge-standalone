/// Audio Export Queue Service Tests (P12.1.20)
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/audio_export_queue_service.dart';

void main() {
  late AudioExportQueueService service;

  setUp(() {
    service = AudioExportQueueService.instance;
    service.clearAll();
  });

  group('AudioExportFormat', () {
    test('has all expected formats', () {
      expect(AudioExportFormat.values.length, 8);
    });

    test('format extensions are correct', () {
      expect(AudioExportFormat.wav16.extension, 'wav');
      expect(AudioExportFormat.wav24.extension, 'wav');
      expect(AudioExportFormat.flac.extension, 'flac');
      expect(AudioExportFormat.mp3High.extension, 'mp3');
      expect(AudioExportFormat.ogg.extension, 'ogg');
    });

    test('display names are human readable', () {
      expect(AudioExportFormat.wav16.displayName, 'WAV 16-bit');
      expect(AudioExportFormat.flac.displayName, 'FLAC');
      expect(AudioExportFormat.mp3High.displayName, 'MP3 320kbps');
    });
  });

  group('AudioExportJob', () {
    test('creates with required fields', () {
      final job = AudioExportJob(
        id: 'job_1',
        inputPath: '/input/test.wav',
        outputPath: '/output/test.flac',
        format: AudioExportFormat.flac,
      );

      expect(job.id, 'job_1');
      expect(job.status, ExportJobStatus.pending);
      expect(job.progress, 0.0);
    });

    test('inputFileName extracts correctly', () {
      final job = AudioExportJob(
        id: 'job_1',
        inputPath: '/path/to/sound.wav',
        outputPath: '/output/sound.flac',
        format: AudioExportFormat.flac,
      );

      expect(job.inputFileName, 'sound.wav');
    });

    test('copyWith updates status', () {
      final original = AudioExportJob(
        id: 'job_1',
        inputPath: '/input.wav',
        outputPath: '/output.flac',
        format: AudioExportFormat.flac,
      );
      final updated = original.copyWith(
        status: ExportJobStatus.completed,
        progress: 1.0,
      );

      expect(updated.status, ExportJobStatus.completed);
      expect(updated.progress, 1.0);
      expect(updated.inputPath, original.inputPath);
    });
  });

  group('AudioExportQueueService', () {
    test('addJob adds to queue', () {
      expect(service.queue.length, 0);

      service.addJob(
        inputPath: '/input.wav',
        outputPath: '/output.flac',
        format: AudioExportFormat.flac,
      );

      expect(service.queue.length, 1);
      expect(service.pendingJobs.length, 1);
    });

    test('removeJob removes from queue', () {
      final id = service.addJob(
        inputPath: '/input.wav',
        outputPath: '/output.flac',
        format: AudioExportFormat.flac,
      );

      expect(service.queue.length, 1);
      service.removeJob(id);
      expect(service.queue.length, 0);
    });

    test('addBatch adds multiple jobs', () {
      final ids = service.addBatch(
        inputPaths: ['/a.wav', '/b.wav', '/c.wav'],
        outputDirectory: '/output',
        format: AudioExportFormat.mp3High,
      );

      expect(ids.length, 3);
      expect(service.queue.length, 3);
    });

    test('clearAll removes all jobs', () {
      service.addJob(
        inputPath: '/a.wav',
        outputPath: '/a.flac',
        format: AudioExportFormat.flac,
      );
      service.addJob(
        inputPath: '/b.wav',
        outputPath: '/b.flac',
        format: AudioExportFormat.flac,
      );

      expect(service.queue.length, 2);
      service.clearAll();
      expect(service.queue.length, 0);
    });
  });
}
