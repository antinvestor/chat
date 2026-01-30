import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/upload_progress.dart';
import 'file_upload_service.dart' show UploadResult;
import 'progressive_upload_service.dart';

part 'upload_progress_provider.g.dart';

/// Manages upload progress state for multiple concurrent uploads
///
/// Provides methods to start, cancel, retry, and track uploads.
/// Exposes a stream of progress updates for UI binding.
///
/// Example:
/// ```dart
/// // Watch a specific upload's progress
/// final progress = ref.watch(uploadProgressProvider)['msg-123'];
///
/// // Start an upload
/// ref.read(uploadProgressProvider.notifier).startUpload(file, 'msg-123');
///
/// // Cancel an upload
/// ref.read(uploadProgressProvider.notifier).cancelUpload('msg-123');
/// ```
@riverpod
class UploadProgressNotifier extends _$UploadProgressNotifier {
  StreamSubscription<UploadProgress>? _subscription;

  @override
  Map<String, UploadProgress> build() {
    final uploadService = ref.watch(progressiveUploadServiceProvider);

    // Listen to progress updates from the service
    _subscription?.cancel();
    _subscription = uploadService.progressStream.listen(_onProgressUpdate);

    ref.onDispose(() {
      _subscription?.cancel();
    });

    return {};
  }

  ProgressiveUploadService get _uploadService =>
      ref.read(progressiveUploadServiceProvider);

  /// Start a new upload
  ///
  /// Parameters:
  /// - [file]: File to upload
  /// - [localId]: Local message ID for tracking
  /// - [mimeType]: Optional MIME type
  ///
  /// Returns [UploadResult] when complete
  Future<UploadResult> startUpload(
    File file, {
    required String localId,
    String? mimeType,
  }) async {
    AppLogger.info(
      'Starting upload via provider',
      data: {'localId': localId, 'path': file.path},
    );

    // Initialize progress state
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();

    state = {
      ...state,
      localId: UploadProgress.pending(
        localId: localId,
        fileName: fileName,
        totalBytes: fileSize,
      ),
    };

    // Start the upload
    final result = await _uploadService.uploadFile(
      file,
      localId: localId,
      mimeType: mimeType,
    );

    return result;
  }

  /// Cancel an active upload
  ///
  /// Returns true if the upload was successfully cancelled
  bool cancelUpload(String localId) {
    final success = _uploadService.cancelUpload(localId);
    if (success) {
      AppLogger.info(
        'Upload cancelled via provider',
        data: {'localId': localId},
      );
    }
    return success;
  }

  /// Retry a failed upload
  ///
  /// Parameters:
  /// - [file]: File to retry uploading
  /// - [localId]: Local message ID
  /// - [mimeType]: Optional MIME type
  ///
  /// Returns [UploadResult] when complete
  Future<UploadResult> retryUpload(
    File file, {
    required String localId,
    String? mimeType,
  }) async {
    AppLogger.info('Retrying upload via provider', data: {'localId': localId});

    // Update state to pending
    final currentProgress = state[localId];
    if (currentProgress != null) {
      state = {
        ...state,
        localId: currentProgress.copyWith(
          state: UploadState.pending,
          error: null,
        ),
      };
    }

    return _uploadService.retryUpload(
      file,
      localId: localId,
      mimeType: mimeType,
    );
  }

  /// Pause an active upload (for resumable uploads)
  bool pauseUpload(String localId) {
    final success = _uploadService.pauseUpload(localId);
    if (success) {
      AppLogger.info('Upload paused via provider', data: {'localId': localId});
    }
    return success;
  }

  /// Resume a paused upload
  Future<UploadResult> resumeUpload(
    File file, {
    required String localId,
    String? mimeType,
  }) async {
    AppLogger.info('Resuming upload via provider', data: {'localId': localId});
    return _uploadService.resumeUpload(
      file,
      localId: localId,
      mimeType: mimeType,
    );
  }

  /// Clear progress for a completed upload
  void clearProgress(String localId) {
    _uploadService.clearProgress(localId);
    state = Map.from(state)..remove(localId);
  }

  /// Clear all completed or failed uploads
  void clearCompleted() {
    final activeUploads = <String, UploadProgress>{};
    for (final entry in state.entries) {
      if (!entry.value.isDone) {
        activeUploads[entry.key] = entry.value;
      } else {
        _uploadService.clearProgress(entry.key);
      }
    }
    state = activeUploads;
  }

  /// Get progress for a specific upload
  UploadProgress? getProgress(String localId) => state[localId];

  /// Check if there are any active uploads
  bool get hasActiveUploads => state.values.any((p) => p.isInProgress);

  /// Get count of active uploads
  int get activeUploadCount => state.values.where((p) => p.isInProgress).length;

  /// Handle progress updates from the service
  void _onProgressUpdate(UploadProgress progress) {
    state = {...state, progress.localId: progress};
  }
}

/// Provider for a specific upload's progress
///
/// Example:
/// ```dart
/// final progress = ref.watch(singleUploadProgressProvider('msg-123'));
/// if (progress != null && progress.isInProgress) {
///   // Show progress indicator
/// }
/// ```
@riverpod
UploadProgress? singleUploadProgress(Ref ref, String localId) {
  final allUploads = ref.watch(uploadProgressProvider);
  return allUploads[localId];
}

/// Provider for checking if a specific upload is active
@riverpod
bool isUploading(Ref ref, String localId) {
  final progress = ref.watch(singleUploadProgressProvider(localId));
  return progress?.isInProgress ?? false;
}

/// Provider for active upload count
@riverpod
int activeUploadCount(Ref ref) {
  final uploads = ref.watch(uploadProgressProvider);
  return uploads.values.where((p) => p.isInProgress).length;
}

/// Provider for total upload progress across all active uploads
@riverpod
double totalUploadProgress(Ref ref) {
  final uploads = ref.watch(uploadProgressProvider);
  final activeUploads = uploads.values.where((p) => p.isInProgress).toList();

  if (activeUploads.isEmpty) return 0;

  var totalBytes = 0;
  var uploadedBytesTotal = 0;

  for (final upload in activeUploads) {
    final uploadTotal = upload.totalBytes;
    if (uploadTotal != null) {
      totalBytes += uploadTotal;
    }
    uploadedBytesTotal += upload.uploadedBytes;
  }

  if (totalBytes == 0) return 0;
  return uploadedBytesTotal / totalBytes;
}

/// Stream provider for real-time progress updates
///
/// Use when you need a stream of all progress events
@riverpod
Stream<UploadProgress> uploadProgressStream(Ref ref) {
  final uploadService = ref.watch(progressiveUploadServiceProvider);
  return uploadService.progressStream;
}
