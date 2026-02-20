import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:antinvestor_api_files/antinvestor_api_files.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../networking/client.dart';
import 'files_config_service.dart';
import 'mxc_uri.dart';

/// Default chunk size for streaming uploads (256KB).
const int _uploadChunkSize = 256 * 1024;

/// Result of an MXC upload operation.
class MxcUploadResult {
  const MxcUploadResult({
    required this.contentUri,
    required this.mediaId,
    required this.serverName,
  });

  /// The full MXC URI (e.g. `mxc://files.antinvestor.com/abc123`).
  final String contentUri;

  /// The media ID component.
  final String mediaId;

  /// The server name component.
  final String serverName;

  /// Parsed [MxcUri] for convenience.
  MxcUri get mxcUri => MxcUri.fromParts(serverName, mediaId);

  /// Legacy-compatible file URL getter.
  ///
  /// Returns the MXC URI string for backward compatibility with code
  /// that expects a `fileUrl` field.
  String get fileUrl => contentUri;
}

/// Service for uploading files via the proto [FilesServiceClient.uploadContent]
/// streaming RPC.
///
/// Provides a unified streaming upload path that works for all file sizes.
class MxcUploadService {
  MxcUploadService(this._getClient, this._configService);

  final Future<FilesServiceClient> Function() _getClient;
  final FilesConfigService _configService;

  /// Upload a [File] via streaming RPC.
  ///
  /// Reads the file in chunks to avoid loading it entirely into memory.
  /// Calls [onProgress] with values from 0.0 to 1.0 during upload.
  ///
  /// Throws [StateError] if the file exceeds the server's max upload size.
  Future<MxcUploadResult> uploadFile(
    File file, {
    String? mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final fileSize = await file.length();
    final fileName = file.path.split('/').last;
    final detectedMime = mimeType ?? _detectMimeType(fileName);

    await _validateFileSize(fileSize);

    final client = await _getClient();

    final controller = StreamController<UploadContentRequest>();

    // Send metadata first
    controller.add(
      UploadContentRequest(
        metadata: UploadMetadata(
          contentType: detectedMime,
          filename: fileName,
          totalSize: Int64(fileSize),
        ),
      ),
    );

    // Read and send chunks
    final randomAccess = await file.open();
    try {
      var bytesSent = 0;
      while (bytesSent < fileSize) {
        final remaining = fileSize - bytesSent;
        final chunkSize = remaining < _uploadChunkSize
            ? remaining
            : _uploadChunkSize;

        final chunkBytes = await randomAccess.read(chunkSize);
        controller.add(UploadContentRequest(chunk: chunkBytes));

        bytesSent += chunkSize;
        onProgress?.call(bytesSent / fileSize);
      }
    } finally {
      await randomAccess.close();
      await controller.close();
    }

    final response = await client.uploadContent(controller.stream);

    AppLogger.info(
      'File uploaded via MXC',
      data: {
        'contentUri': response.contentUri,
        'fileName': fileName,
        'size': fileSize,
      },
    );

    return MxcUploadResult(
      contentUri: response.contentUri,
      mediaId: response.mediaId,
      serverName: response.serverName,
    );
  }

  /// Upload raw bytes via streaming RPC.
  Future<MxcUploadResult> uploadBytes(
    Uint8List bytes,
    String filename,
    String mimeType, {
    void Function(double progress)? onProgress,
  }) async {
    await _validateFileSize(bytes.length);

    final client = await _getClient();

    final controller = StreamController<UploadContentRequest>();

    // Send metadata first
    controller.add(
      UploadContentRequest(
        metadata: UploadMetadata(
          contentType: mimeType,
          filename: filename,
          totalSize: Int64(bytes.length),
        ),
      ),
    );

    // Send in chunks
    var bytesSent = 0;
    while (bytesSent < bytes.length) {
      final end = bytesSent + _uploadChunkSize;
      final chunkEnd = end > bytes.length ? bytes.length : end;
      final chunk = bytes.sublist(bytesSent, chunkEnd);

      controller.add(UploadContentRequest(chunk: chunk));

      bytesSent = chunkEnd;
      onProgress?.call(bytesSent / bytes.length);
    }

    await controller.close();

    final response = await client.uploadContent(controller.stream);

    return MxcUploadResult(
      contentUri: response.contentUri,
      mediaId: response.mediaId,
      serverName: response.serverName,
    );
  }

  /// Upload a thumbnail image (convenience wrapper with simpler logging).
  Future<MxcUploadResult> uploadThumbnail(
    Uint8List bytes,
    String mimeType,
  ) async {
    final result = await uploadBytes(bytes, 'thumbnail', mimeType);

    AppLogger.debug(
      'Thumbnail uploaded via MXC',
      data: {'contentUri': result.contentUri, 'size': bytes.length},
    );

    return result;
  }

  /// Validate file size against server config.
  Future<void> _validateFileSize(int fileSize) async {
    final maxSize = await _configService.getMaxUploadSize();
    if (fileSize > maxSize) {
      throw StateError(
        'File size ($fileSize bytes) exceeds maximum upload size ($maxSize bytes)',
      );
    }
  }

  /// Detect MIME type from file extension.
  String _detectMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'avi' => 'video/x-msvideo',
      'webm' => 'video/webm',
      'mkv' => 'video/x-matroska',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'm4a' => 'audio/mp4',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt' => 'text/plain',
      'json' => 'application/json',
      _ => 'application/octet-stream',
    };
  }
}

/// Provider for [MxcUploadService].
final mxcUploadServiceProvider = Provider<MxcUploadService>((ref) {
  final configService = ref.watch(filesConfigServiceProvider);
  return MxcUploadService(
    () => ref.read(filesServiceClientProvider.future),
    configService,
  );
});
