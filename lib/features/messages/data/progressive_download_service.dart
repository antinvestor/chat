import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';
import '../domain/download_progress.dart';

/// Default chunk size for large file downloads (5MB)
const int defaultDownloadChunkSize = 5 * 1024 * 1024;

/// Threshold above which files are downloaded in chunks (5MB)
const int chunkDownloadThreshold = 5 * 1024 * 1024;

/// Maximum number of retry attempts for failed downloads
const int maxDownloadRetries = 3;

/// Base delay for exponential backoff (in milliseconds)
const int baseDownloadRetryDelayMs = 1000;

/// Result of a download operation
class DownloadResult {
  DownloadResult._({
    required this.isSuccess,
    this.localPath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.errorMessage,
  });

  factory DownloadResult.success({
    required String localPath,
    String? fileName,
    int? fileSize,
    String? mimeType,
  }) => DownloadResult._(
    isSuccess: true,
    localPath: localPath,
    fileName: fileName,
    fileSize: fileSize,
    mimeType: mimeType,
  );

  factory DownloadResult.failure(String message) =>
      DownloadResult._(isSuccess: false, errorMessage: message);

  final bool isSuccess;
  final String? localPath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? errorMessage;
}

/// Service for progressive file downloads with chunking and resumability
///
/// Features:
/// - Chunked downloads for large files (>5MB)
/// - Progress tracking via stream
/// - Resumable downloads (uses HTTP Range requests and stores progress)
/// - Retry mechanism with exponential backoff
/// - Cancel download capability
///
/// Example:
/// ```dart
/// final service = ref.read(progressiveDownloadServiceProvider);
///
/// // Listen to progress updates
/// service.progressStream.listen((progress) {
///   print('Download ${progress.progressPercent}%');
/// });
///
/// // Start download
/// final result = await service.downloadFile(
///   fileUrl: 'https://example.com/file.pdf',
///   downloadId: 'dl-123',
/// );
/// ```
class ProgressiveDownloadService {
  ProgressiveDownloadService(this._getAccessToken, this._db);

  final Future<String?> Function() _getAccessToken;
  final AppDatabase _db;

  /// Stream controller for progress updates
  final _progressController = StreamController<DownloadProgress>.broadcast();

  /// Map of active download cancellation tokens
  final Map<String, bool> _cancellationTokens = {};

  /// Map of active downloads for tracking
  final Map<String, DownloadProgress> _activeDownloads = {};

  /// Stream of download progress updates
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Get current progress for a specific download
  DownloadProgress? getProgress(String downloadId) =>
      _activeDownloads[downloadId];

  /// Get all active downloads
  Map<String, DownloadProgress> get activeDownloads =>
      Map.unmodifiable(_activeDownloads);

  /// Download a file with progress tracking
  ///
  /// For files larger than [chunkDownloadThreshold] (5MB), the download
  /// is automatically split into chunks with resume support.
  ///
  /// Parameters:
  /// - [fileUrl]: URL of the file to download
  /// - [downloadId]: Unique download ID for tracking
  /// - [fileName]: Optional custom file name (extracted from URL if not provided)
  /// - [destinationPath]: Optional custom destination path
  /// - [roomId]: Optional room ID for context
  ///
  /// Returns [DownloadResult] with local path on success
  Future<DownloadResult> downloadFile({
    required String fileUrl,
    required String downloadId,
    String? fileName,
    String? destinationPath,
    String? roomId,
  }) async {
    try {
      // Register cancellation token
      _cancellationTokens[downloadId] = false;

      // Extract file name from URL if not provided
      final extractedFileName = fileName ?? _extractFileName(fileUrl);

      // Determine destination path
      final localPath =
          destinationPath ?? await _getDefaultDownloadPath(extractedFileName);

      // Initialize progress
      final initialProgress = DownloadProgress.pending(
        downloadId: downloadId,
        fileName: extractedFileName,
        fileUrl: fileUrl,
        localPath: localPath,
        roomId: roomId,
      );
      _updateProgress(initialProgress);

      // Get file size using HEAD request
      final fileInfo = await _getFileInfo(fileUrl);
      if (fileInfo == null) {
        return DownloadResult.failure('Failed to get file information');
      }

      final fileSize = fileInfo.size;
      final supportsRangeRequests = fileInfo.acceptRanges;
      final mimeType = fileInfo.contentType;
      final etag = fileInfo.etag;

      // Update progress with file size
      _updateProgress(
        initialProgress.copyWith(totalBytes: fileSize, mimeType: mimeType),
      );

      // Check for existing download progress (resumable download)
      final existingChunks = await _getDownloadChunks(downloadId);
      final startByte = existingChunks.fold<int>(
        0,
        (sum, chunk) => sum + chunk.bytesDownloaded,
      );

      if (fileSize > chunkDownloadThreshold && supportsRangeRequests) {
        // Large file with range support: use chunked download
        return await _downloadChunked(
          fileUrl: fileUrl,
          downloadId: downloadId,
          localPath: localPath,
          fileName: extractedFileName,
          totalSize: fileSize,
          startByte: startByte,
          mimeType: mimeType,
          etag: etag,
          roomId: roomId,
        );
      } else {
        // Small file or no range support: use direct download
        return await _downloadDirect(
          fileUrl: fileUrl,
          downloadId: downloadId,
          localPath: localPath,
          fileName: extractedFileName,
          totalSize: fileSize,
          mimeType: mimeType,
          roomId: roomId,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Progressive download failed',
        error: e,
        stackTrace: stackTrace,
        data: {'downloadId': downloadId, 'fileUrl': fileUrl},
      );

      final errorProgress = DownloadProgress.failed(
        downloadId: downloadId,
        error: e.toString(),
        fileUrl: fileUrl,
      );
      _updateProgress(errorProgress);

      return DownloadResult.failure(e.toString());
    } finally {
      _cancellationTokens.remove(downloadId);
    }
  }

  /// Cancel an active download
  ///
  /// Returns true if the download was successfully cancelled
  bool cancelDownload(String downloadId) {
    if (_cancellationTokens.containsKey(downloadId)) {
      _cancellationTokens[downloadId] = true;

      final progress = _activeDownloads[downloadId];
      if (progress != null) {
        _updateProgress(
          progress.copyWith(
            state: DownloadState.cancelled,
            completedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }

      AppLogger.info('Download cancelled', data: {'downloadId': downloadId});
      return true;
    }
    return false;
  }

  /// Retry a failed download
  ///
  /// Resumes from the last successful chunk if available
  Future<DownloadResult> retryDownload({
    required String fileUrl,
    required String downloadId,
    String? fileName,
    String? destinationPath,
    String? roomId,
  }) async {
    // Clear cancellation token
    _cancellationTokens.remove(downloadId);

    // Get existing progress for retry count
    final existingProgress = _activeDownloads[downloadId];
    final retryCount = (existingProgress?.retryCount ?? 0) + 1;

    if (retryCount > maxDownloadRetries) {
      final errorProgress = DownloadProgress.failed(
        downloadId: downloadId,
        error: 'Maximum retry attempts exceeded',
        fileUrl: fileUrl,
        retryCount: retryCount,
      );
      _updateProgress(errorProgress);
      return DownloadResult.failure('Maximum retry attempts exceeded');
    }

    // Apply exponential backoff
    final delay = baseDownloadRetryDelayMs * pow(2, retryCount - 1);
    await Future.delayed(Duration(milliseconds: delay.toInt()));

    AppLogger.info(
      'Retrying download',
      data: {'downloadId': downloadId, 'attempt': retryCount},
    );

    // Update progress with retry count
    if (existingProgress != null) {
      _updateProgress(
        existingProgress.copyWith(
          state: DownloadState.pending,
          retryCount: retryCount,
          error: null,
        ),
      );
    }

    return downloadFile(
      fileUrl: fileUrl,
      downloadId: downloadId,
      fileName: fileName,
      destinationPath: destinationPath,
      roomId: roomId,
    );
  }

  /// Pause an active download
  bool pauseDownload(String downloadId) {
    final progress = _activeDownloads[downloadId];
    if (progress != null && progress.isInProgress) {
      _cancellationTokens[downloadId] = true;
      _updateProgress(progress.copyWith(state: DownloadState.paused));
      return true;
    }
    return false;
  }

  /// Resume a paused download
  Future<DownloadResult> resumeDownload({
    required String fileUrl,
    required String downloadId,
    String? fileName,
    String? destinationPath,
    String? roomId,
  }) async {
    _cancellationTokens[downloadId] = false;
    return downloadFile(
      fileUrl: fileUrl,
      downloadId: downloadId,
      fileName: fileName,
      destinationPath: destinationPath,
      roomId: roomId,
    );
  }

  /// Clear progress for a completed or cancelled download
  void clearProgress(String downloadId) {
    _activeDownloads.remove(downloadId);
    _clearDownloadChunks(downloadId);
  }

  /// Direct download for small files
  Future<DownloadResult> _downloadDirect({
    required String fileUrl,
    required String downloadId,
    required String localPath,
    required String fileName,
    required int totalSize,
    String? mimeType,
    String? roomId,
  }) async {
    final token = await _getAccessToken();

    // Update progress to downloading
    _updateProgress(
      DownloadProgress.downloading(
        downloadId: downloadId,
        progress: 0,
        fileName: fileName,
        fileUrl: fileUrl,
        localPath: localPath,
        totalBytes: totalSize,
        mimeType: mimeType,
        roomId: roomId,
      ),
    );

    // Check for cancellation
    if (_isCancelled(downloadId)) {
      return DownloadResult.failure('Download cancelled');
    }

    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final request = http.Request('GET', Uri.parse(fileUrl));
    request.headers.addAll(headers);

    final response = await request.send();

    if (response.statusCode != 200) {
      final error = 'Download failed: ${response.statusCode}';
      _updateProgress(
        DownloadProgress.failed(
          downloadId: downloadId,
          error: error,
          fileName: fileName,
          fileUrl: fileUrl,
        ),
      );
      return DownloadResult.failure(error);
    }

    // Create destination file
    final file = File(localPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();

    try {
      var downloadedBytes = 0;

      await for (final chunk in response.stream) {
        if (_isCancelled(downloadId)) {
          await sink.close();
          await file.delete();
          return DownloadResult.failure('Download cancelled');
        }

        sink.add(chunk);
        downloadedBytes += chunk.length;

        // Update progress
        final progress = downloadedBytes / totalSize;
        _updateProgress(
          DownloadProgress.downloading(
            downloadId: downloadId,
            progress: progress,
            fileName: fileName,
            fileUrl: fileUrl,
            localPath: localPath,
            totalBytes: totalSize,
            downloadedBytes: downloadedBytes,
            mimeType: mimeType,
            roomId: roomId,
          ),
        );
      }

      await sink.close();

      // Update progress to completed
      _updateProgress(
        DownloadProgress.completed(
          downloadId: downloadId,
          fileName: fileName,
          fileUrl: fileUrl,
          localPath: localPath,
          totalBytes: totalSize,
          mimeType: mimeType,
          roomId: roomId,
        ),
      );

      AppLogger.info(
        'Direct download completed',
        data: {'downloadId': downloadId, 'fileName': fileName},
      );

      return DownloadResult.success(
        localPath: localPath,
        fileName: fileName,
        fileSize: totalSize,
        mimeType: mimeType,
      );
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  /// Chunked download for large files with resume support
  Future<DownloadResult> _downloadChunked({
    required String fileUrl,
    required String downloadId,
    required String localPath,
    required String fileName,
    required int totalSize,
    required int startByte,
    String? mimeType,
    String? etag,
    String? roomId,
  }) async {
    final token = await _getAccessToken();

    final totalChunks = (totalSize / defaultDownloadChunkSize).ceil();
    final startChunk = startByte ~/ defaultDownloadChunkSize;

    AppLogger.info(
      'Starting chunked download',
      data: {
        'downloadId': downloadId,
        'fileName': fileName,
        'totalSize': totalSize,
        'totalChunks': totalChunks,
        'startChunk': startChunk,
        'startByte': startByte,
      },
    );

    // Save download metadata
    await _saveDownloadMetadata(
      downloadId: downloadId,
      fileUrl: fileUrl,
      localPath: localPath,
      totalSize: totalSize,
      etag: etag,
    );

    // Create or open destination file
    final file = File(localPath);
    await file.parent.create(recursive: true);
    final randomAccessFile = await file.open(mode: FileMode.writeOnlyAppend);

    try {
      var downloadedBytes = startByte;

      for (
        var chunkIndex = startChunk;
        chunkIndex < totalChunks;
        chunkIndex++
      ) {
        // Check for cancellation
        if (_isCancelled(downloadId)) {
          await randomAccessFile.close();
          return DownloadResult.failure('Download cancelled');
        }

        // Calculate chunk boundaries
        final chunkStart = chunkIndex * defaultDownloadChunkSize;
        final chunkEnd =
            min(chunkStart + defaultDownloadChunkSize, totalSize) - 1;

        // Download chunk with retry
        final chunkBytes = await _downloadChunkWithRetry(
          fileUrl: fileUrl,
          rangeStart: chunkStart,
          rangeEnd: chunkEnd,
          token: token,
        );

        if (chunkBytes == null) {
          final error = 'Failed to download chunk $chunkIndex';
          _updateProgress(
            DownloadProgress.failed(
              downloadId: downloadId,
              error: error,
              fileName: fileName,
              fileUrl: fileUrl,
              localPath: localPath,
              totalBytes: totalSize,
              downloadedBytes: downloadedBytes,
            ),
          );
          await randomAccessFile.close();
          return DownloadResult.failure(error);
        }

        // Write chunk to file
        await randomAccessFile.setPosition(chunkStart);
        await randomAccessFile.writeFrom(chunkBytes);

        // Save chunk progress to database
        await _saveChunkProgress(
          downloadId: downloadId,
          chunkIndex: chunkIndex,
          chunkSize: chunkBytes.length,
          bytesDownloaded: chunkBytes.length,
          fileUrl: fileUrl,
          localPath: localPath,
          totalSize: totalSize,
        );

        downloadedBytes = chunkEnd + 1;
        final progress = downloadedBytes / totalSize;

        // Update progress
        _updateProgress(
          DownloadProgress.downloading(
            downloadId: downloadId,
            progress: progress,
            fileName: fileName,
            fileUrl: fileUrl,
            localPath: localPath,
            totalBytes: totalSize,
            downloadedBytes: downloadedBytes,
            currentChunk: chunkIndex + 1,
            totalChunks: totalChunks,
            etag: etag,
            isChunked: true,
            mimeType: mimeType,
            roomId: roomId,
          ),
        );

        AppLogger.debug(
          'Chunk downloaded',
          data: {
            'downloadId': downloadId,
            'chunk': chunkIndex + 1,
            'totalChunks': totalChunks,
            'progress': '${(progress * 100).toStringAsFixed(1)}%',
          },
        );
      }

      await randomAccessFile.close();

      // Update progress to completed
      _updateProgress(
        DownloadProgress.completed(
          downloadId: downloadId,
          fileName: fileName,
          fileUrl: fileUrl,
          localPath: localPath,
          totalBytes: totalSize,
          mimeType: mimeType,
          roomId: roomId,
        ),
      );

      // Clean up chunk progress
      await _clearDownloadChunks(downloadId);

      AppLogger.info(
        'Chunked download completed',
        data: {'downloadId': downloadId, 'fileName': fileName},
      );

      return DownloadResult.success(
        localPath: localPath,
        fileName: fileName,
        fileSize: totalSize,
        mimeType: mimeType,
      );
    } catch (e) {
      await randomAccessFile.close();
      rethrow;
    }
  }

  /// Download a single chunk with retry
  Future<List<int>?> _downloadChunkWithRetry({
    required String fileUrl,
    required int rangeStart,
    required int rangeEnd,
    String? token,
  }) async {
    for (var attempt = 0; attempt < maxDownloadRetries; attempt++) {
      try {
        final headers = <String, String>{
          'Range': 'bytes=$rangeStart-$rangeEnd',
        };

        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }

        final response = await http.get(Uri.parse(fileUrl), headers: headers);

        if (response.statusCode == 206 || response.statusCode == 200) {
          return response.bodyBytes;
        }

        AppLogger.warning(
          'Chunk download attempt failed',
          data: {
            'attempt': attempt + 1,
            'statusCode': response.statusCode,
            'rangeStart': rangeStart,
            'rangeEnd': rangeEnd,
          },
        );
      } catch (e) {
        AppLogger.warning(
          'Chunk download attempt error',
          error: e,
          data: {'attempt': attempt + 1},
        );
      }

      // Exponential backoff before retry
      if (attempt < maxDownloadRetries - 1) {
        final delay = baseDownloadRetryDelayMs * pow(2, attempt);
        await Future.delayed(Duration(milliseconds: delay.toInt()));
      }
    }

    return null;
  }

  /// Get file information using HEAD request
  Future<_FileInfo?> _getFileInfo(String fileUrl) async {
    try {
      final token = await _getAccessToken();
      final headers = <String, String>{};

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.head(Uri.parse(fileUrl), headers: headers);

      if (response.statusCode != 200) {
        AppLogger.warning(
          'HEAD request failed',
          data: {'statusCode': response.statusCode, 'url': fileUrl},
        );
        return null;
      }

      final contentLength = response.headers['content-length'];
      final acceptRanges = response.headers['accept-ranges'];
      final contentType = response.headers['content-type'];
      final etag = response.headers['etag'];

      return _FileInfo(
        size: contentLength != null ? int.tryParse(contentLength) ?? 0 : 0,
        acceptRanges: acceptRanges == 'bytes',
        contentType: contentType,
        etag: etag,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get file info',
        error: e,
        stackTrace: stackTrace,
        data: {'url': fileUrl},
      );
      return null;
    }
  }

  /// Check if download is cancelled
  bool _isCancelled(String downloadId) =>
      _cancellationTokens[downloadId] ?? false;

  /// Update and broadcast progress
  void _updateProgress(DownloadProgress progress) {
    _activeDownloads[progress.downloadId] = progress;
    _progressController.add(progress);
  }

  /// Extract file name from URL
  String _extractFileName(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      return Uri.decodeComponent(pathSegments.last);
    }
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Get default download path
  Future<String> _getDefaultDownloadPath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${directory.path}/downloads');
    await downloadDir.create(recursive: true);
    return '${downloadDir.path}/$fileName';
  }

  // ============================================================================
  // Database Operations
  // ============================================================================

  /// Save download metadata
  Future<void> _saveDownloadMetadata({
    required String downloadId,
    required String fileUrl,
    required String localPath,
    required int totalSize,
    String? etag,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db
        .into(_db.downloadChunks)
        .insert(
          DownloadChunksCompanion.insert(
            downloadId: downloadId,
            fileUrl: fileUrl,
            localPath: localPath,
            totalSize: totalSize,
            chunkIndex: const Value(-1),
            chunkSize: const Value(0),
            etag: Value(etag),
            createdAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Save chunk progress
  ///
  /// Takes metadata parameters directly to avoid redundant DB reads on each chunk.
  Future<void> _saveChunkProgress({
    required String downloadId,
    required int chunkIndex,
    required int chunkSize,
    required int bytesDownloaded,
    required String fileUrl,
    required String localPath,
    required int totalSize,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _db
        .into(_db.downloadChunks)
        .insert(
          DownloadChunksCompanion.insert(
            downloadId: downloadId,
            fileUrl: fileUrl,
            localPath: localPath,
            totalSize: totalSize,
            chunkIndex: Value(chunkIndex),
            chunkSize: Value(chunkSize),
            bytesDownloaded: Value(bytesDownloaded),
            createdAt: now,
            updatedAt: Value(now),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Get download chunks for resumable download
  Future<List<DownloadChunk>> _getDownloadChunks(String downloadId) async {
    final query = _db.select(_db.downloadChunks)
      ..where(
        (t) =>
            t.downloadId.equals(downloadId) &
            t.chunkIndex.isBiggerOrEqualValue(0),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.chunkIndex)]);
    return query.get();
  }

  /// Clear download chunks after successful download
  Future<void> _clearDownloadChunks(String downloadId) async {
    await (_db.delete(
      _db.downloadChunks,
    )..where((t) => t.downloadId.equals(downloadId))).go();
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
  }
}

/// Internal class for file information from HEAD request
class _FileInfo {
  _FileInfo({
    required this.size,
    required this.acceptRanges,
    this.contentType,
    this.etag,
  });

  final int size;
  final bool acceptRanges;
  final String? contentType;
  final String? etag;
}

// Provider
final progressiveDownloadServiceProvider = Provider<ProgressiveDownloadService>(
  (ref) {
    final tokenManager = ref.watch(tokenManagerProvider);
    final db = AppDatabase.instance;

    final service = ProgressiveDownloadService(
      () async => tokenManager.accessToken,
      db,
    );

    ref.onDispose(service.dispose);

    return service;
  },
);
