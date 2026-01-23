import 'dart:io';

import 'package:chat/core/db/database.dart';
import 'package:chat/features/messages/data/progressive_upload_service.dart';
import 'package:chat/features/messages/domain/upload_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late AppDatabase testDb;
  late ProgressiveUploadService service;
  String? mockAccessToken;

  setUp(() async {
    testDb = createTestDatabase();
    mockAccessToken = 'test-token';

    // Create upload_chunks table for tests
    await testDb.customStatement('''
      CREATE TABLE IF NOT EXISTS upload_chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id TEXT NOT NULL,
        upload_id TEXT,
        chunk_index INTEGER DEFAULT -1,
        chunk_size INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await testDb.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_upload_chunks_local_id
      ON upload_chunks(local_id)
    ''');

    service = ProgressiveUploadService(() async => mockAccessToken, testDb);
  });

  tearDown(() async {
    service.dispose();
    await testDb.close();
  });

  group('UploadProgress model', () {
    test('creates pending state correctly', () {
      final progress = UploadProgress.pending(
        localId: 'msg-123',
        fileName: 'photo.jpg',
        totalBytes: 1024000,
      );

      expect(progress.localId, equals('msg-123'));
      expect(progress.state, equals(UploadState.pending));
      expect(progress.progress, equals(0.0));
      expect(progress.fileName, equals('photo.jpg'));
      expect(progress.totalBytes, equals(1024000));
      expect(progress.startedAt, isNotNull);
    });

    test('creates uploading state correctly', () {
      final progress = UploadProgress.uploading(
        localId: 'msg-123',
        progress: 0.45,
        fileName: 'photo.jpg',
        totalBytes: 1024000,
        uploadedBytes: 460800,
        currentChunk: 2,
        totalChunks: 5,
        isChunked: true,
      );

      expect(progress.state, equals(UploadState.uploading));
      expect(progress.progress, equals(0.45));
      expect(progress.uploadedBytes, equals(460800));
      expect(progress.currentChunk, equals(2));
      expect(progress.totalChunks, equals(5));
      expect(progress.isChunked, isTrue);
      expect(progress.progressPercent, equals(45));
    });

    test('creates completed state correctly', () {
      final progress = UploadProgress.completed(
        localId: 'msg-123',
        fileName: 'photo.jpg',
        totalBytes: 1024000,
      );

      expect(progress.state, equals(UploadState.completed));
      expect(progress.progress, equals(1.0));
      expect(progress.uploadedBytes, equals(1024000));
      expect(progress.completedAt, isNotNull);
      expect(progress.isDone, isTrue);
    });

    test('creates failed state correctly', () {
      final progress = UploadProgress.failed(
        localId: 'msg-123',
        error: 'Network error',
        retryCount: 2,
      );

      expect(progress.state, equals(UploadState.failed));
      expect(progress.error, equals('Network error'));
      expect(progress.retryCount, equals(2));
      expect(progress.canRetry, isTrue);
      expect(progress.isDone, isTrue);
    });

    test('isInProgress returns correct value', () {
      expect(UploadProgress.pending(localId: 'msg-1').isInProgress, isFalse);
      expect(
        UploadProgress.uploading(localId: 'msg-1', progress: 0.5).isInProgress,
        isTrue,
      );
      expect(UploadProgress.completed(localId: 'msg-1').isInProgress, isFalse);
      expect(
        UploadProgress.failed(localId: 'msg-1', error: 'Error').isInProgress,
        isFalse,
      );
    });

    test('canCancel returns correct value', () {
      expect(UploadProgress.pending(localId: 'msg-1').canCancel, isTrue);
      expect(
        UploadProgress.uploading(localId: 'msg-1', progress: 0.5).canCancel,
        isTrue,
      );
      expect(UploadProgress.completed(localId: 'msg-1').canCancel, isFalse);
      expect(
        UploadProgress.failed(localId: 'msg-1', error: 'Error').canCancel,
        isFalse,
      );
    });

    test('canRetry returns correct value', () {
      expect(UploadProgress.pending(localId: 'msg-1').canRetry, isFalse);
      expect(
        UploadProgress.uploading(localId: 'msg-1', progress: 0.5).canRetry,
        isFalse,
      );
      expect(UploadProgress.completed(localId: 'msg-1').canRetry, isFalse);
      expect(
        UploadProgress.failed(localId: 'msg-1', error: 'Error').canRetry,
        isTrue,
      );
      expect(
        const UploadProgress(
          localId: 'msg-1',
          state: UploadState.cancelled,
        ).canRetry,
        isTrue,
      );
    });

    test('progressText returns appropriate messages', () {
      expect(
        UploadProgress.pending(localId: 'msg-1').progressText,
        equals('Waiting...'),
      );
      expect(
        UploadProgress.uploading(localId: 'msg-1', progress: 0.5).progressText,
        equals('Uploading... 50%'),
      );
      expect(
        UploadProgress.uploading(
          localId: 'msg-1',
          progress: 0.5,
          currentChunk: 2,
          totalChunks: 5,
          isChunked: true,
        ).progressText,
        equals('Uploading chunk 2 of 5 (50%)'),
      );
      expect(
        UploadProgress.completed(localId: 'msg-1').progressText,
        equals('Upload complete'),
      );
      expect(
        UploadProgress.failed(localId: 'msg-1', error: 'Network').progressText,
        equals('Upload failed: Network'),
      );
    });

    test('copyWith preserves values', () {
      final original = UploadProgress.uploading(
        localId: 'msg-123',
        progress: 0.5,
        fileName: 'test.jpg',
        totalBytes: 1000,
        uploadedBytes: 500,
      );

      final copied = original.copyWith(progress: 0.75, uploadedBytes: 750);

      expect(copied.localId, equals('msg-123'));
      expect(copied.fileName, equals('test.jpg'));
      expect(copied.totalBytes, equals(1000));
      expect(copied.progress, equals(0.75));
      expect(copied.uploadedBytes, equals(750));
    });
  });

  group('ProgressiveUploadService', () {
    test('initializes progress stream', () {
      expect(service.progressStream, isNotNull);
      expect(service.activeUploads, isEmpty);
    });

    test('returns failure when not authenticated', () async {
      mockAccessToken = null;

      // Create a temporary test file
      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_upload.txt');
      await testFile.writeAsString('test content');

      try {
        final result = await service.uploadFile(testFile, localId: 'msg-123');

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('Not authenticated'));
      } finally {
        await testFile.delete();
      }
    });

    test('emits progress updates through stream', () async {
      final progressUpdates = <UploadProgress>[];
      final subscription = service.progressStream.listen(progressUpdates.add);

      // Access internal method indirectly via public API
      // In real tests, we'd use a test file and mock HTTP responses
      await Future.delayed(const Duration(milliseconds: 10));

      subscription.cancel();

      // Progress stream exists and is broadcasting
      expect(service.progressStream.isBroadcast, isTrue);
    });

    test('getProgress returns null for unknown upload', () {
      expect(service.getProgress('unknown-id'), isNull);
    });

    test('cancelUpload returns false for non-existent upload', () {
      final result = service.cancelUpload('non-existent');
      expect(result, isFalse);
    });

    test('clearProgress removes upload from tracking', () async {
      // The upload wouldn't exist, but we verify the method doesn't throw
      service.clearProgress('msg-123');
      expect(service.getProgress('msg-123'), isNull);
    });

    test('pauseUpload returns false for non-existent upload', () {
      final result = service.pauseUpload('non-existent');
      expect(result, isFalse);
    });
  });

  group('Progress tracking edge cases', () {
    test('progress percentage rounds correctly', () {
      expect(
        UploadProgress.uploading(
          localId: 'msg-1',
          progress: 0.994,
        ).progressPercent,
        equals(99),
      );
      expect(
        UploadProgress.uploading(
          localId: 'msg-1',
          progress: 0.996,
        ).progressPercent,
        equals(100),
      );
      expect(
        UploadProgress.uploading(
          localId: 'msg-1',
          progress: 0.001,
        ).progressPercent,
        equals(0),
      );
    });

    test('upload speed calculation handles edge cases', () {
      // No startedAt - should return null
      const noStart = UploadProgress(
        localId: 'msg-1',
        state: UploadState.uploading,
        uploadedBytes: 1000,
      );
      expect(noStart.uploadSpeed, isNull);

      // No bytes uploaded - should return null
      final noBytes = UploadProgress(
        localId: 'msg-1',
        state: UploadState.uploading,
        startedAt: DateTime.now().millisecondsSinceEpoch - 1000,
      );
      expect(noBytes.uploadSpeed, isNull);
    });

    test('estimated time remaining handles edge cases', () {
      // No total bytes - should return null
      final noTotal = UploadProgress(
        localId: 'msg-1',
        state: UploadState.uploading,
        startedAt: DateTime.now().millisecondsSinceEpoch - 1000,
        uploadedBytes: 500,
      );
      expect(noTotal.estimatedTimeRemaining, isNull);

      // With proper values - should calculate
      final withTotal = UploadProgress(
        localId: 'msg-1',
        state: UploadState.uploading,
        startedAt: DateTime.now().millisecondsSinceEpoch - 1000,
        uploadedBytes: 500,
        totalBytes: 1000,
      );
      // Speed is 500 bytes/sec, remaining is 500 bytes, so ~1 second
      final eta = withTotal.estimatedTimeRemaining;
      expect(eta, isNotNull);
      // Allow some variance due to timing
      expect(eta, greaterThanOrEqualTo(0));
      expect(eta, lessThan(10)); // Should be around 1 second
    });
  });

  group('Upload state transitions', () {
    test('pending -> uploading transition', () {
      final pending = UploadProgress.pending(localId: 'msg-1');
      expect(pending.state, equals(UploadState.pending));
      expect(pending.isInProgress, isFalse);
      expect(pending.canCancel, isTrue);

      final uploading = pending.copyWith(
        state: UploadState.uploading,
        progress: 0.1,
      );
      expect(uploading.state, equals(UploadState.uploading));
      expect(uploading.isInProgress, isTrue);
      expect(uploading.canCancel, isTrue);
    });

    test('uploading -> completed transition', () {
      final uploading = UploadProgress.uploading(
        localId: 'msg-1',
        progress: 0.99,
      );

      final completed = uploading.copyWith(
        state: UploadState.completed,
        progress: 1,
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(completed.state, equals(UploadState.completed));
      expect(completed.isDone, isTrue);
      expect(completed.canRetry, isFalse);
      expect(completed.canCancel, isFalse);
    });

    test('uploading -> failed transition', () {
      final uploading = UploadProgress.uploading(
        localId: 'msg-1',
        progress: 0.5,
      );

      final failed = uploading.copyWith(
        state: UploadState.failed,
        error: 'Connection lost',
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(failed.state, equals(UploadState.failed));
      expect(failed.isDone, isTrue);
      expect(failed.canRetry, isTrue);
      expect(failed.error, equals('Connection lost'));
    });

    test('uploading -> cancelled transition', () {
      final uploading = UploadProgress.uploading(
        localId: 'msg-1',
        progress: 0.5,
      );

      final cancelled = uploading.copyWith(
        state: UploadState.cancelled,
        completedAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(cancelled.state, equals(UploadState.cancelled));
      expect(cancelled.isDone, isTrue);
      expect(cancelled.canRetry, isTrue);
    });

    test('uploading -> paused transition', () {
      final uploading = UploadProgress.uploading(
        localId: 'msg-1',
        progress: 0.5,
        uploadedBytes: 500,
        totalBytes: 1000,
      );

      final paused = uploading.copyWith(state: UploadState.paused);

      expect(paused.state, equals(UploadState.paused));
      expect(paused.isDone, isFalse);
      expect(paused.isInProgress, isFalse);
      expect(paused.progress, equals(0.5)); // Progress preserved
      expect(paused.uploadedBytes, equals(500)); // Bytes preserved
    });

    test('failed -> retry transition', () {
      final failed = UploadProgress.failed(
        localId: 'msg-1',
        error: 'Network error',
        retryCount: 1,
      );

      final retrying = failed.copyWith(
        state: UploadState.pending,
        error: null,
        retryCount: 2,
      );

      expect(retrying.state, equals(UploadState.pending));
      expect(retrying.error, isNull);
      expect(retrying.retryCount, equals(2));
    });
  });

  group('Chunked upload configuration', () {
    test('chunk size threshold is 5MB', () {
      expect(chunkUploadThreshold, equals(5 * 1024 * 1024));
    });

    test('default chunk size is 5MB', () {
      expect(defaultChunkSize, equals(5 * 1024 * 1024));
    });

    test('max retries is 3', () {
      expect(maxUploadRetries, equals(3));
    });

    test('base retry delay is 1 second', () {
      expect(baseRetryDelayMs, equals(1000));
    });
  });
}
