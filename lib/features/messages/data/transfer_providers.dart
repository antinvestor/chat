import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/sync/transfer_job_repository.dart';
import '../../notifications/transfer_notification_service.dart';
import '../domain/download_progress.dart';
import '../domain/upload_progress.dart';
import 'progressive_download_service.dart';
import 'progressive_upload_service.dart';
import 'upload_progress_provider.dart';

part 'transfer_providers.g.dart';

// ============================================================================
// Download Progress Provider
// ============================================================================

/// Manages download progress state for multiple concurrent downloads
///
/// Provides methods to start, cancel, retry, and track downloads.
/// Exposes a stream of progress updates for UI binding.
///
/// Example:
/// ```dart
/// // Watch a specific download's progress
/// final progress = ref.watch(downloadProgressProvider)['dl-123'];
///
/// // Start a download
/// ref.read(downloadProgressProvider.notifier).startDownload(
///   fileUrl: 'https://example.com/file.pdf',
///   downloadId: 'dl-123',
/// );
///
/// // Cancel a download
/// ref.read(downloadProgressProvider.notifier).cancelDownload('dl-123');
/// ```
@riverpod
class DownloadProgressNotifier extends _$DownloadProgressNotifier {
  StreamSubscription<DownloadProgress>? _subscription;

  @override
  Map<String, DownloadProgress> build() {
    final downloadService = ref.watch(progressiveDownloadServiceProvider);

    // Listen to progress updates from the service
    _subscription?.cancel();
    _subscription = downloadService.progressStream.listen(_onProgressUpdate);

    ref.onDispose(() {
      _subscription?.cancel();
    });

    return {};
  }

  ProgressiveDownloadService get _downloadService =>
      ref.read(progressiveDownloadServiceProvider);

  /// Start a new download
  ///
  /// Parameters:
  /// - [fileUrl]: URL of the file to download
  /// - [downloadId]: Unique download ID for tracking
  /// - [fileName]: Optional custom file name
  /// - [destinationPath]: Optional custom destination path
  /// - [roomId]: Optional room ID for context
  ///
  /// Returns [DownloadResult] when complete
  Future<DownloadResult> startDownload({
    required String fileUrl,
    required String downloadId,
    String? fileName,
    String? destinationPath,
    String? roomId,
  }) async {
    AppLogger.info(
      'Starting download via provider',
      data: {'downloadId': downloadId, 'fileUrl': fileUrl},
    );

    // Initialize progress state
    final extractedFileName =
        fileName ?? fileUrl.split('/').last.split('?').first;

    state = {
      ...state,
      downloadId: DownloadProgress.pending(
        downloadId: downloadId,
        fileName: extractedFileName,
        fileUrl: fileUrl,
        roomId: roomId,
      ),
    };

    // Start the download
    final result = await _downloadService.downloadFile(
      fileUrl: fileUrl,
      downloadId: downloadId,
      fileName: fileName,
      destinationPath: destinationPath,
      roomId: roomId,
    );

    return result;
  }

  /// Cancel an active download
  ///
  /// Returns true if the download was successfully cancelled
  bool cancelDownload(String downloadId) {
    final success = _downloadService.cancelDownload(downloadId);
    if (success) {
      AppLogger.info(
        'Download cancelled via provider',
        data: {'downloadId': downloadId},
      );
    }
    return success;
  }

  /// Retry a failed download
  ///
  /// Returns [DownloadResult] when complete
  Future<DownloadResult> retryDownload({
    required String fileUrl,
    required String downloadId,
    String? fileName,
    String? destinationPath,
    String? roomId,
  }) async {
    AppLogger.info(
      'Retrying download via provider',
      data: {'downloadId': downloadId},
    );

    // Update state to pending
    final currentProgress = state[downloadId];
    if (currentProgress != null) {
      state = {
        ...state,
        downloadId: currentProgress.copyWith(
          state: DownloadState.pending,
          error: null,
        ),
      };
    }

    return _downloadService.retryDownload(
      fileUrl: fileUrl,
      downloadId: downloadId,
      fileName: fileName,
      destinationPath: destinationPath,
      roomId: roomId,
    );
  }

  /// Pause an active download
  bool pauseDownload(String downloadId) {
    final success = _downloadService.pauseDownload(downloadId);
    if (success) {
      AppLogger.info(
        'Download paused via provider',
        data: {'downloadId': downloadId},
      );
    }
    return success;
  }

  /// Resume a paused download
  Future<DownloadResult> resumeDownload({
    required String fileUrl,
    required String downloadId,
    String? fileName,
    String? destinationPath,
    String? roomId,
  }) async {
    AppLogger.info(
      'Resuming download via provider',
      data: {'downloadId': downloadId},
    );
    return _downloadService.resumeDownload(
      fileUrl: fileUrl,
      downloadId: downloadId,
      fileName: fileName,
      destinationPath: destinationPath,
      roomId: roomId,
    );
  }

  /// Clear progress for a completed download
  void clearProgress(String downloadId) {
    _downloadService.clearProgress(downloadId);
    state = Map.from(state)..remove(downloadId);
  }

  /// Clear all completed or failed downloads
  void clearCompleted() {
    final activeDownloads = <String, DownloadProgress>{};
    for (final entry in state.entries) {
      if (!entry.value.isDone) {
        activeDownloads[entry.key] = entry.value;
      } else {
        _downloadService.clearProgress(entry.key);
      }
    }
    state = activeDownloads;
  }

  /// Get progress for a specific download
  DownloadProgress? getProgress(String downloadId) => state[downloadId];

  /// Check if there are any active downloads
  bool get hasActiveDownloads => state.values.any((p) => p.isInProgress);

  /// Get count of active downloads
  int get activeDownloadCount =>
      state.values.where((p) => p.isInProgress).length;

  /// Handle progress updates from the service
  void _onProgressUpdate(DownloadProgress progress) {
    state = {...state, progress.downloadId: progress};
  }
}

// ============================================================================
// Single Download Progress Provider
// ============================================================================

/// Provider for a specific download's progress
///
/// Example:
/// ```dart
/// final progress = ref.watch(singleDownloadProgressProvider('dl-123'));
/// if (progress != null && progress.isInProgress) {
///   // Show progress indicator
/// }
/// ```
@riverpod
DownloadProgress? singleDownloadProgress(Ref ref, String downloadId) {
  final allDownloads = ref.watch(downloadProgressProvider);
  return allDownloads[downloadId];
}

/// Provider for checking if a specific download is active
@riverpod
bool isDownloading(Ref ref, String downloadId) {
  final progress = ref.watch(singleDownloadProgressProvider(downloadId));
  return progress?.isInProgress ?? false;
}

/// Provider for active download count
@riverpod
int activeDownloadCount(Ref ref) {
  final downloads = ref.watch(downloadProgressProvider);
  return downloads.values.where((p) => p.isInProgress).length;
}

/// Provider for total download progress across all active downloads
@riverpod
double totalDownloadProgress(Ref ref) {
  final downloads = ref.watch(downloadProgressProvider);
  final activeDownloads = downloads.values
      .where((p) => p.isInProgress)
      .toList();

  if (activeDownloads.isEmpty) return 0;

  var totalBytes = 0;
  var downloadedBytesTotal = 0;

  for (final download in activeDownloads) {
    final downloadTotal = download.totalBytes;
    if (downloadTotal != null) {
      totalBytes += downloadTotal;
    }
    downloadedBytesTotal += download.downloadedBytes;
  }

  if (totalBytes == 0) return 0;
  return downloadedBytesTotal / totalBytes;
}

/// Stream provider for real-time download progress updates
///
/// Use when you need a stream of all progress events
@riverpod
Stream<DownloadProgress> downloadProgressStream(Ref ref) {
  final downloadService = ref.watch(progressiveDownloadServiceProvider);
  return downloadService.progressStream;
}

// ============================================================================
// Transfer Queue Service
// ============================================================================

/// Service for managing the unified transfer queue for uploads and downloads
///
/// Coordinates transfer jobs, prioritizes uploads over downloads,
/// and handles notifications for transfer progress. This is a non-Riverpod
/// service wrapper around TransferJobRepository.
///
/// Example:
/// ```dart
/// final queue = ref.read(transferQueueServiceProvider);
///
/// // Queue an upload
/// await queue.queueUpload(
///   file: File('/path/to/file.jpg'),
///   localId: 'msg-123',
///   roomId: 'room-456',
/// );
///
/// // Queue a download
/// await queue.queueDownload(
///   fileUrl: 'https://example.com/file.pdf',
///   downloadId: 'dl-789',
///   roomId: 'room-456',
/// );
/// ```
class TransferQueueService {
  TransferQueueService(this._repository);

  final TransferJobRepository _repository;

  /// Queue an upload job
  Future<int> queueUpload({
    required File file,
    required String localId,
    required String roomId,
    String? mimeType,
    int priority = TransferPriority.high,
  }) async {
    final fileName = file.path.split('/').last;
    final totalSize = await file.length();

    final jobId = await _repository.createUploadJob(
      referenceId: localId,
      roomId: roomId,
      localPath: file.path,
      fileName: fileName,
      totalSize: totalSize,
      mimeType: mimeType,
      priority: priority,
    );

    AppLogger.info(
      'Upload queued',
      data: {'jobId': jobId, 'localId': localId, 'fileName': fileName},
    );

    return jobId;
  }

  /// Queue a download job
  Future<int> queueDownload({
    required String fileUrl,
    required String downloadId,
    required String roomId,
    required String localPath,
    required String fileName,
    required int totalSize,
    String? mimeType,
    int priority = TransferPriority.normal,
  }) async {
    final jobId = await _repository.createDownloadJob(
      referenceId: downloadId,
      roomId: roomId,
      fileUrl: fileUrl,
      localPath: localPath,
      fileName: fileName,
      totalSize: totalSize,
      mimeType: mimeType,
      priority: priority,
    );

    AppLogger.info(
      'Download queued',
      data: {'jobId': jobId, 'downloadId': downloadId, 'fileName': fileName},
    );

    return jobId;
  }

  /// Cancel a queued job
  Future<void> cancelJob(int jobId) async {
    await _repository.deleteJob(jobId);
    AppLogger.info('Transfer job cancelled', data: {'jobId': jobId});
  }

  /// Cancel a job by reference ID
  Future<void> cancelJobByReferenceId(String referenceId) async {
    await _repository.deleteJobByReferenceId(referenceId);
  }

  /// Pause a job
  Future<void> pauseJob(int jobId) async {
    await _repository.markPaused(jobId);
  }

  /// Resume a job
  Future<void> resumeJob(int jobId) async {
    await _repository.resetToPending(jobId);
  }

  /// Retry a failed job
  Future<void> retryJob(int jobId) async {
    await _repository.resetToPending(jobId);
  }

  /// Update job priority
  Future<void> updatePriority(int jobId, int priority) async {
    await _repository.updatePriority(jobId, priority);
  }

  /// Clear completed jobs
  Future<int> clearCompleted() async {
    return _repository.deleteCompletedJobs();
  }

  /// Clear failed jobs
  Future<int> clearFailed() async {
    return _repository.deleteFailedJobs();
  }
}

/// Provider for TransferQueueService
@riverpod
TransferQueueService transferQueueService(Ref ref) {
  final repository = ref.watch(transferJobRepositoryProvider);
  return TransferQueueService(repository);
}

// ============================================================================
// Transfer Statistics Providers
// ============================================================================

/// Provider for pending upload count
@riverpod
Future<int> pendingUploadCount(Ref ref) async {
  final repository = ref.watch(transferJobRepositoryProvider);
  return repository.getPendingUploadCount();
}

/// Provider for pending download count
@riverpod
Future<int> pendingDownloadCount(Ref ref) async {
  final repository = ref.watch(transferJobRepositoryProvider);
  return repository.getPendingDownloadCount();
}

/// Provider for total pending bytes
@riverpod
Future<int> totalPendingBytes(Ref ref) async {
  final repository = ref.watch(transferJobRepositoryProvider);
  return repository.getTotalPendingBytes();
}

/// Provider for total transferred bytes
@riverpod
Future<int> totalTransferredBytes(Ref ref) async {
  final repository = ref.watch(transferJobRepositoryProvider);
  return repository.getTotalTransferredBytes();
}

/// Provider for checking if there are any active transfers
@riverpod
bool hasActiveTransfers(Ref ref) {
  final uploadProgress = ref.watch(uploadProgressProvider);
  final downloadProgress = ref.watch(downloadProgressProvider);

  final hasActiveUploads = uploadProgress.values.any((p) => p.isInProgress);
  final hasActiveDownloads = downloadProgress.values.any((p) => p.isInProgress);

  return hasActiveUploads || hasActiveDownloads;
}

/// Provider for overall transfer progress (uploads + downloads)
@riverpod
double overallTransferProgress(Ref ref) {
  final uploadProgress = ref.watch(totalUploadProgressProvider);
  final downloadProgress = ref.watch(totalDownloadProgressProvider);

  final uploadCount = ref.watch(activeUploadCountProvider);
  final downloadCount = ref.watch(activeDownloadCountProvider);

  final totalCount = uploadCount + downloadCount;
  if (totalCount == 0) return 0;

  return (uploadProgress * uploadCount + downloadProgress * downloadCount) /
      totalCount;
}

// ============================================================================
// Transfer Notification Integration
// ============================================================================

/// Provider that automatically shows/updates transfer notifications
///
/// This provider listens to upload and download progress streams
/// and shows appropriate notifications.
@riverpod
class TransferNotifications extends _$TransferNotifications {
  StreamSubscription<UploadProgress>? _uploadSubscription;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  @override
  bool build() {
    final notificationService = ref.watch(transferNotificationServiceProvider);

    // Initialize notification service if not already
    if (!notificationService.isInitialized) {
      notificationService.initialize(onAction: _handleNotificationAction);
    }

    // Listen to upload progress
    final uploadService = ref.watch(progressiveUploadServiceProvider);
    _uploadSubscription?.cancel();
    _uploadSubscription = uploadService.progressStream.listen(
      (progress) => _handleUploadProgress(progress, notificationService),
    );

    // Listen to download progress
    final downloadService = ref.watch(progressiveDownloadServiceProvider);
    _downloadSubscription?.cancel();
    _downloadSubscription = downloadService.progressStream.listen(
      (progress) => _handleDownloadProgress(progress, notificationService),
    );

    ref.onDispose(() {
      _uploadSubscription?.cancel();
      _downloadSubscription?.cancel();
    });

    return true;
  }

  void _handleUploadProgress(
    UploadProgress progress,
    TransferNotificationService service,
  ) {
    switch (progress.state) {
      case UploadState.uploading:
        service.showUploadProgress(
          uploadId: progress.localId,
          fileName: progress.fileName ?? 'File',
          progress: progress.progress,
          uploadedBytes: progress.uploadedBytes,
          totalBytes: progress.totalBytes ?? 0,
        );
      case UploadState.completed:
        service.showUploadComplete(
          uploadId: progress.localId,
          fileName: progress.fileName ?? 'File',
          totalBytes: progress.totalBytes,
        );
      case UploadState.failed:
        service.showUploadFailed(
          uploadId: progress.localId,
          fileName: progress.fileName ?? 'File',
          error: progress.error,
        );
      case UploadState.cancelled:
        service.cancelUploadNotification(progress.localId);
      case UploadState.pending:
      case UploadState.paused:
        // No notification update needed
        break;
    }
  }

  void _handleDownloadProgress(
    DownloadProgress progress,
    TransferNotificationService service,
  ) {
    switch (progress.state) {
      case DownloadState.downloading:
        service.showDownloadProgress(
          downloadId: progress.downloadId,
          fileName: progress.fileName ?? 'File',
          progress: progress.progress,
          downloadedBytes: progress.downloadedBytes,
          totalBytes: progress.totalBytes ?? 0,
        );
      case DownloadState.completed:
        service.showDownloadComplete(
          downloadId: progress.downloadId,
          fileName: progress.fileName ?? 'File',
          localPath: progress.localPath,
          totalBytes: progress.totalBytes,
        );
      case DownloadState.failed:
        service.showDownloadFailed(
          downloadId: progress.downloadId,
          fileName: progress.fileName ?? 'File',
          error: progress.error,
        );
      case DownloadState.cancelled:
        service.cancelDownloadNotification(progress.downloadId);
      case DownloadState.pending:
      case DownloadState.paused:
        // No notification update needed
        break;
    }
  }

  void _handleNotificationAction(String actionId, String transferId) {
    AppLogger.info(
      'Transfer notification action',
      data: {'actionId': actionId, 'transferId': transferId},
    );

    switch (actionId) {
      case TransferNotificationActions.cancelUpload:
        ref.read(uploadProgressProvider.notifier).cancelUpload(transferId);
      case TransferNotificationActions.cancelDownload:
        ref.read(downloadProgressProvider.notifier).cancelDownload(transferId);
      case TransferNotificationActions.openFile:
        // Handle open file action - could navigate to file or open externally
        AppLogger.info('Open file requested', data: {'path': transferId});
    }
  }
}

/// Provider to activate transfer notifications
///
/// Use this at app startup to enable automatic transfer notifications:
/// ```dart
/// ref.watch(transferNotificationsActiveProvider);
/// ```
@riverpod
bool transferNotificationsActive(Ref ref) {
  // Just watching this provider activates the TransferNotifications provider
  ref.watch(transferNotificationsProvider);
  return true;
}
