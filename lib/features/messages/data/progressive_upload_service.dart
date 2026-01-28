import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/api_config.dart';
import '../../../core/networking/client.dart';
import '../domain/upload_progress.dart';
import 'file_upload_service.dart' show UploadResult;

/// Default chunk size for large file uploads (5MB)
const int defaultChunkSize = 5 * 1024 * 1024;

/// Threshold above which files are uploaded in chunks (5MB)
const int chunkUploadThreshold = 5 * 1024 * 1024;

/// Maximum number of retry attempts for failed uploads
const int maxUploadRetries = 3;

/// Base delay for exponential backoff (in milliseconds)
const int baseRetryDelayMs = 1000;

/// Service for progressive file uploads with chunking and resumability
///
/// Features:
/// - Chunked uploads for large files (>5MB)
/// - Progress tracking via stream
/// - Resumable uploads (stores chunk progress in database)
/// - Retry mechanism with exponential backoff
/// - Cancel upload capability
///
/// Example:
/// ```dart
/// final service = ref.read(progressiveUploadServiceProvider);
///
/// // Listen to progress updates
/// service.progressStream.listen((progress) {
///   print('Upload ${progress.progressPercent}%');
/// });
///
/// // Start upload
/// final result = await service.uploadFile(file, localId: 'msg-123');
/// ```
class ProgressiveUploadService {
  ProgressiveUploadService(this._getAccessToken, this._db);

  final Future<String?> Function() _getAccessToken;
  final AppDatabase _db;

  /// Stream controller for progress updates
  final _progressController = StreamController<UploadProgress>.broadcast();

  /// Map of active upload cancellation tokens
  final Map<String, bool> _cancellationTokens = {};

  /// Map of active uploads for tracking
  final Map<String, UploadProgress> _activeUploads = {};

  /// Stream of upload progress updates
  Stream<UploadProgress> get progressStream => _progressController.stream;

  /// Get current progress for a specific upload
  UploadProgress? getProgress(String localId) => _activeUploads[localId];

  /// Get all active uploads
  Map<String, UploadProgress> get activeUploads =>
      Map.unmodifiable(_activeUploads);

  /// Upload a file with progress tracking
  ///
  /// For files larger than [chunkUploadThreshold] (5MB), the upload
  /// is automatically split into chunks for better reliability.
  ///
  /// Parameters:
  /// - [file]: The file to upload
  /// - [localId]: Local message ID for tracking
  /// - [mimeType]: Optional MIME type (auto-detected if not provided)
  ///
  /// Returns [UploadResult] with file URL on success
  Future<UploadResult> uploadFile(
    File file, {
    required String localId,
    String? mimeType,
  }) async {
    try {
      // Register cancellation token
      _cancellationTokens[localId] = false;

      final fileSize = await file.length();
      final fileName = file.path.split('/').last;

      // Initialize progress
      final initialProgress = UploadProgress.pending(
        localId: localId,
        fileName: fileName,
        totalBytes: fileSize,
      );
      _updateProgress(initialProgress);

      // Check for existing chunk progress (resumable upload)
      final existingChunks = await _getUploadChunks(localId);
      final startChunk = existingChunks.length;

      if (fileSize > chunkUploadThreshold) {
        // Large file: use chunked upload
        return await _uploadChunked(
          file,
          localId: localId,
          mimeType: mimeType,
          startChunk: startChunk,
        );
      } else {
        // Small file: use direct upload
        return await _uploadDirect(file, localId: localId, mimeType: mimeType);
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Progressive upload failed',
        error: e,
        stackTrace: stackTrace,
        data: {'localId': localId},
      );

      final errorProgress = UploadProgress.failed(
        localId: localId,
        error: e.toString(),
      );
      _updateProgress(errorProgress);

      return UploadResult.failure(e.toString());
    } finally {
      _cancellationTokens.remove(localId);
    }
  }

  /// Cancel an active upload
  ///
  /// Returns true if the upload was successfully cancelled
  bool cancelUpload(String localId) {
    if (_cancellationTokens.containsKey(localId)) {
      _cancellationTokens[localId] = true;

      final progress = _activeUploads[localId];
      if (progress != null) {
        _updateProgress(
          progress.copyWith(
            state: UploadState.cancelled,
            completedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }

      AppLogger.info('Upload cancelled', data: {'localId': localId});
      return true;
    }
    return false;
  }

  /// Retry a failed upload
  ///
  /// Resumes from the last successful chunk if available
  Future<UploadResult> retryUpload(
    File file, {
    required String localId,
    String? mimeType,
  }) async {
    // Clear cancellation token
    _cancellationTokens.remove(localId);

    // Get existing progress for retry count
    final existingProgress = _activeUploads[localId];
    final retryCount = (existingProgress?.retryCount ?? 0) + 1;

    if (retryCount > maxUploadRetries) {
      final errorProgress = UploadProgress.failed(
        localId: localId,
        error: 'Maximum retry attempts exceeded',
        retryCount: retryCount,
      );
      _updateProgress(errorProgress);
      return UploadResult.failure('Maximum retry attempts exceeded');
    }

    // Apply exponential backoff
    final delay = baseRetryDelayMs * pow(2, retryCount - 1);
    await Future.delayed(Duration(milliseconds: delay.toInt()));

    AppLogger.info(
      'Retrying upload',
      data: {'localId': localId, 'attempt': retryCount},
    );

    // Update progress with retry count
    if (existingProgress != null) {
      _updateProgress(
        existingProgress.copyWith(
          state: UploadState.pending,
          retryCount: retryCount,
          error: null,
        ),
      );
    }

    return uploadFile(file, localId: localId, mimeType: mimeType);
  }

  /// Pause an active upload (for resumable uploads)
  bool pauseUpload(String localId) {
    final progress = _activeUploads[localId];
    if (progress != null && progress.isInProgress) {
      _cancellationTokens[localId] = true;
      _updateProgress(progress.copyWith(state: UploadState.paused));
      return true;
    }
    return false;
  }

  /// Resume a paused upload
  Future<UploadResult> resumeUpload(
    File file, {
    required String localId,
    String? mimeType,
  }) async {
    _cancellationTokens[localId] = false;
    return uploadFile(file, localId: localId, mimeType: mimeType);
  }

  /// Clear progress for a completed or cancelled upload
  void clearProgress(String localId) {
    _activeUploads.remove(localId);
    _clearUploadChunks(localId);
  }

  /// Direct upload for small files
  Future<UploadResult> _uploadDirect(
    File file, {
    required String localId,
    String? mimeType,
  }) async {
    final token = await _getAccessToken();
    if (token == null || token.isEmpty) {
      return UploadResult.failure('Not authenticated');
    }

    final fileBytes = await file.readAsBytes();
    final fileName = file.path.split('/').last;
    final fileSize = fileBytes.length;

    // Update progress to uploading
    _updateProgress(
      UploadProgress.uploading(
        localId: localId,
        progress: 0,
        fileName: fileName,
        totalBytes: fileSize,
      ),
    );

    // Use a custom HTTP client with progress tracking
    final uri = Uri.parse('${ApiConfig.filesBaseUrl}/v1/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );

    if (mimeType != null) {
      request.fields['content_type'] = mimeType;
    }

    // Check for cancellation
    if (_isCancelled(localId)) {
      return UploadResult.failure('Upload cancelled');
    }

    final streamedResponse = await request.send();

    // Simulate progress (since standard http package doesn't track upload progress)
    // In production, you might use dio or a custom http client for real progress
    _updateProgress(
      UploadProgress.uploading(
        localId: localId,
        progress: 0.5,
        fileName: fileName,
        totalBytes: fileSize,
        uploadedBytes: fileSize ~/ 2,
      ),
    );

    if (_isCancelled(localId)) {
      return UploadResult.failure('Upload cancelled');
    }

    if (streamedResponse.statusCode == 200 ||
        streamedResponse.statusCode == 201) {
      final responseBody = await streamedResponse.stream.bytesToString();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      // Update progress to completed
      _updateProgress(
        UploadProgress.completed(
          localId: localId,
          fileName: fileName,
          totalBytes: fileSize,
        ),
      );

      AppLogger.info(
        'Direct upload completed',
        data: {'localId': localId, 'fileName': fileName},
      );

      return UploadResult.success(
        fileId: json['id'] as String? ?? '',
        fileUrl: json['url'] as String? ?? '',
        thumbnailUrl: json['thumbnail_url'] as String?,
        mimeType: mimeType,
        size: fileSize,
      );
    } else {
      final errorBody = await streamedResponse.stream.bytesToString();
      final error =
          'Upload failed: ${streamedResponse.statusCode} - $errorBody';

      _updateProgress(
        UploadProgress.failed(
          localId: localId,
          error: error,
          fileName: fileName,
          totalBytes: fileSize,
        ),
      );

      return UploadResult.failure(error);
    }
  }

  /// Chunked upload for large files
  Future<UploadResult> _uploadChunked(
    File file, {
    required String localId,
    String? mimeType,
    int startChunk = 0,
  }) async {
    final token = await _getAccessToken();
    if (token == null || token.isEmpty) {
      return UploadResult.failure('Not authenticated');
    }

    final fileSize = await file.length();
    final fileName = file.path.split('/').last;
    final totalChunks = (fileSize / defaultChunkSize).ceil();

    AppLogger.info(
      'Starting chunked upload',
      data: {
        'localId': localId,
        'fileName': fileName,
        'fileSize': fileSize,
        'totalChunks': totalChunks,
        'startChunk': startChunk,
      },
    );

    // Get or create upload ID for resumable upload
    var uploadId = await _getUploadId(localId);

    // If starting fresh, initiate chunked upload on server
    if (uploadId == null || startChunk == 0) {
      uploadId = await _initiateChunkedUpload(
        fileName: fileName,
        fileSize: fileSize,
        totalChunks: totalChunks,
        mimeType: mimeType,
        token: token,
      );

      if (uploadId == null) {
        return UploadResult.failure('Failed to initiate chunked upload');
      }

      await _saveUploadId(localId, uploadId);
    }

    // Open file for reading chunks
    final randomAccessFile = await file.open();

    try {
      for (
        var chunkIndex = startChunk;
        chunkIndex < totalChunks;
        chunkIndex++
      ) {
        // Check for cancellation
        if (_isCancelled(localId)) {
          return UploadResult.failure('Upload cancelled');
        }

        // Calculate chunk boundaries
        final chunkStart = chunkIndex * defaultChunkSize;
        final chunkEnd = min(chunkStart + defaultChunkSize, fileSize);
        final chunkSize = chunkEnd - chunkStart;

        // Read chunk
        await randomAccessFile.setPosition(chunkStart);
        final chunkBytes = await randomAccessFile.read(chunkSize);

        // Upload chunk with retry
        final success = await _uploadChunkWithRetry(
          chunkBytes: chunkBytes,
          uploadId: uploadId,
          chunkIndex: chunkIndex,
          totalChunks: totalChunks,
          token: token,
        );

        if (!success) {
          final error = 'Failed to upload chunk $chunkIndex';
          _updateProgress(
            UploadProgress.failed(
              localId: localId,
              error: error,
              fileName: fileName,
              totalBytes: fileSize,
              uploadedBytes: chunkStart,
            ),
          );
          return UploadResult.failure(error);
        }

        // Save chunk progress to database
        await _saveChunkProgress(localId, chunkIndex, chunkSize);

        // Update progress
        final uploadedBytes = chunkEnd;
        final progress = uploadedBytes / fileSize;

        _updateProgress(
          UploadProgress.uploading(
            localId: localId,
            progress: progress,
            fileName: fileName,
            totalBytes: fileSize,
            uploadedBytes: uploadedBytes,
            currentChunk: chunkIndex + 1,
            totalChunks: totalChunks,
            uploadId: uploadId,
            isChunked: true,
          ),
        );

        AppLogger.debug(
          'Chunk uploaded',
          data: {
            'localId': localId,
            'chunk': chunkIndex + 1,
            'totalChunks': totalChunks,
            'progress': '${(progress * 100).toStringAsFixed(1)}%',
          },
        );
      }

      // Finalize chunked upload
      final result = await _finalizeChunkedUpload(
        uploadId: uploadId,
        token: token,
      );

      if (result != null) {
        // Update progress to completed
        _updateProgress(
          UploadProgress.completed(
            localId: localId,
            fileName: fileName,
            totalBytes: fileSize,
          ),
        );

        // Clean up chunk progress
        await _clearUploadChunks(localId);

        AppLogger.info(
          'Chunked upload completed',
          data: {'localId': localId, 'uploadId': uploadId},
        );

        return result;
      } else {
        const error = 'Failed to finalize chunked upload';
        _updateProgress(
          UploadProgress.failed(
            localId: localId,
            error: error,
            fileName: fileName,
            totalBytes: fileSize,
          ),
        );
        return UploadResult.failure(error);
      }
    } finally {
      await randomAccessFile.close();
    }
  }

  /// Initiate a chunked upload on the server
  Future<String?> _initiateChunkedUpload({
    required String fileName,
    required int fileSize,
    required int totalChunks,
    required String token,
    String? mimeType,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.filesBaseUrl}/v1/upload/init');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'file_name': fileName,
          'file_size': fileSize,
          'total_chunks': totalChunks,
          if (mimeType != null) 'content_type': mimeType,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['upload_id'] as String?;
      }

      AppLogger.error(
        'Failed to initiate chunked upload',
        data: {'statusCode': response.statusCode, 'body': response.body},
      );
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error initiating chunked upload',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Upload a single chunk with retry
  Future<bool> _uploadChunkWithRetry({
    required Uint8List chunkBytes,
    required String uploadId,
    required int chunkIndex,
    required int totalChunks,
    required String token,
  }) async {
    for (var attempt = 0; attempt < maxUploadRetries; attempt++) {
      try {
        final uri = Uri.parse('${ApiConfig.filesBaseUrl}/v1/upload/chunk');
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer $token';

        request.fields['upload_id'] = uploadId;
        request.fields['chunk_index'] = chunkIndex.toString();
        request.fields['total_chunks'] = totalChunks.toString();

        request.files.add(
          http.MultipartFile.fromBytes(
            'chunk',
            chunkBytes,
            filename: 'chunk_$chunkIndex',
          ),
        );

        final response = await request.send();

        if (response.statusCode == 200 || response.statusCode == 201) {
          return true;
        }

        final errorBody = await response.stream.bytesToString();
        AppLogger.warning(
          'Chunk upload attempt failed',
          data: {
            'chunkIndex': chunkIndex,
            'attempt': attempt + 1,
            'statusCode': response.statusCode,
            'error': errorBody,
          },
        );
      } catch (e) {
        AppLogger.warning(
          'Chunk upload attempt error',
          error: e,
          data: {'chunkIndex': chunkIndex, 'attempt': attempt + 1},
        );
      }

      // Exponential backoff before retry
      if (attempt < maxUploadRetries - 1) {
        final delay = baseRetryDelayMs * pow(2, attempt);
        await Future.delayed(Duration(milliseconds: delay.toInt()));
      }
    }

    return false;
  }

  /// Finalize a chunked upload
  Future<UploadResult?> _finalizeChunkedUpload({
    required String uploadId,
    required String token,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.filesBaseUrl}/v1/upload/finalize');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'upload_id': uploadId}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return UploadResult.success(
          fileId: json['id'] as String? ?? '',
          fileUrl: json['url'] as String? ?? '',
          thumbnailUrl: json['thumbnail_url'] as String?,
          mimeType: json['content_type'] as String?,
          size: json['size'] as int?,
        );
      }

      AppLogger.error(
        'Failed to finalize chunked upload',
        data: {'statusCode': response.statusCode, 'body': response.body},
      );
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error finalizing chunked upload',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Check if upload is cancelled
  bool _isCancelled(String localId) => _cancellationTokens[localId] ?? false;

  /// Update and broadcast progress
  void _updateProgress(UploadProgress progress) {
    _activeUploads[progress.localId] = progress;
    _progressController.add(progress);
  }

  // Database operations for resumable uploads
  /// Get upload ID for a local message (for resuming)
  Future<String?> _getUploadId(String localId) async {
    final query = _db.select(_db.uploadChunks)
      ..where((t) => t.localId.equals(localId))
      ..limit(1);
    final result = await query.getSingleOrNull();
    return result?.uploadId;
  }

  /// Save upload ID for resumable upload
  Future<void> _saveUploadId(String localId, String uploadId) async {
    await _db
        .into(_db.uploadChunks)
        .insert(
          UploadChunksCompanion.insert(
            localId: localId,
            uploadId: Value(uploadId),
            chunkIndex: const Value(-1),
            chunkSize: const Value(0),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Save chunk progress
  Future<void> _saveChunkProgress(
    String localId,
    int chunkIndex,
    int chunkSize,
  ) async {
    // First retrieve the upload ID for this local message
    final existingUploadId = await _getUploadId(localId);

    await _db
        .into(_db.uploadChunks)
        .insert(
          UploadChunksCompanion.insert(
            localId: localId,
            uploadId: existingUploadId != null
                ? Value(existingUploadId)
                : const Value.absent(),
            chunkIndex: Value(chunkIndex),
            chunkSize: Value(chunkSize),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Get completed chunks for resumable upload
  Future<List<int>> _getUploadChunks(String localId) async {
    final query = _db.select(_db.uploadChunks)
      ..where(
        (t) => t.localId.equals(localId) & t.chunkIndex.isBiggerOrEqualValue(0),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.chunkIndex)]);
    final results = await query.get();
    return results.map((r) => r.chunkIndex).toList();
  }

  /// Clear chunk progress after successful upload
  Future<void> _clearUploadChunks(String localId) async {
    await (_db.delete(
      _db.uploadChunks,
    )..where((t) => t.localId.equals(localId))).go();
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
  }
}

// Provider
final progressiveUploadServiceProvider = Provider<ProgressiveUploadService>((
  ref,
) {
  final tokenManager = ref.watch(tokenManagerProvider);
  final db = AppDatabase.instance;

  final service = ProgressiveUploadService(
    () async => tokenManager.accessToken,
    db,
  );

  ref.onDispose(service.dispose);

  return service;
});
