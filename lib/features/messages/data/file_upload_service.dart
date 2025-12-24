import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../core/networking/api_config.dart';
import '../../../core/networking/client.dart';

/// Service for uploading files, images, and videos to the server
class FileUploadService {
  final Future<String?> Function() _getAccessToken;

  FileUploadService(this._getAccessToken);

  /// Upload a file and return the file URL
  Future<UploadResult> uploadFile(
    File file, {
    String? mimeType,
    void Function(double progress)? onProgress,
  }) async {
    try {
      AppLogger.info('Starting file upload', data: {'path': file.path});

      final token = await _getAccessToken();
      if (token == null || token.isEmpty) {
        return UploadResult.failure('Not authenticated');
      }

      final fileName = file.path.split('/').last;
      final fileBytes = await file.readAsBytes();
      final detectedMimeType = mimeType ?? _detectMimeType(fileName);

      return await _uploadBytes(
        fileBytes,
        fileName,
        detectedMimeType,
        token,
        onProgress: onProgress,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'File upload failed',
        error: e,
        stackTrace: stackTrace,
      );
      return UploadResult.failure(e.toString());
    }
  }

  /// Upload bytes directly (useful for in-memory data)
  Future<UploadResult> uploadBytes(
    Uint8List bytes,
    String fileName, {
    String? mimeType,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final token = await _getAccessToken();
      if (token == null || token.isEmpty) {
        return UploadResult.failure('Not authenticated');
      }

      final detectedMimeType = mimeType ?? _detectMimeType(fileName);

      return await _uploadBytes(
        bytes,
        fileName,
        detectedMimeType,
        token,
        onProgress: onProgress,
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Bytes upload failed',
        error: e,
        stackTrace: stackTrace,
      );
      return UploadResult.failure(e.toString());
    }
  }

  Future<UploadResult> _uploadBytes(
    Uint8List bytes,
    String fileName,
    String mimeType,
    String token, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('${ApiConfig.filesBaseUrl}/v1/upload');

    // Create multipart request
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
    ));

    request.fields['content_type'] = mimeType;

    // Send request with progress tracking
    final streamedResponse = await request.send();

    if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201) {
      final responseBody = await streamedResponse.stream.bytesToString();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      AppLogger.info('File uploaded successfully', data: {'fileName': fileName});

      return UploadResult.success(
        fileId: json['id'] as String? ?? '',
        fileUrl: json['url'] as String? ?? '',
        thumbnailUrl: json['thumbnail_url'] as String?,
        mimeType: mimeType,
        size: bytes.length,
      );
    } else {
      final errorBody = await streamedResponse.stream.bytesToString();
      AppLogger.error(
        'Upload failed',
        data: {
          'statusCode': streamedResponse.statusCode,
          'error': errorBody,
        },
      );
      return UploadResult.failure(
        'Upload failed: ${streamedResponse.statusCode}',
      );
    }
  }

  /// Upload an image with optional compression
  Future<UploadResult> uploadImage(
    File imageFile, {
    int? maxWidth,
    int? maxHeight,
    int quality = 85,
    void Function(double progress)? onProgress,
  }) async {
    // For now, upload as-is. Image compression can be added later
    // using image package if needed
    return await uploadFile(
      imageFile,
      mimeType: _detectMimeType(imageFile.path),
      onProgress: onProgress,
    );
  }

  /// Upload a video
  Future<UploadResult> uploadVideo(
    File videoFile, {
    void Function(double progress)? onProgress,
  }) async {
    return await uploadFile(
      videoFile,
      mimeType: _detectMimeType(videoFile.path),
      onProgress: onProgress,
    );
  }

  /// Download a file
  Future<Uint8List?> downloadFile(String fileUrl) async {
    try {
      final token = await _getAccessToken();
      final response = await http.get(
        Uri.parse(fileUrl),
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'File download failed',
        error: e,
        stackTrace: stackTrace,
        data: {'url': fileUrl},
      );
      return null;
    }
  }

  String _detectMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      // Images
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      // Videos
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      // Audio
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      // Documents
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }
}

class UploadResult {
  final bool isSuccess;
  final String? fileId;
  final String? fileUrl;
  final String? thumbnailUrl;
  final String? mimeType;
  final int? size;
  final String? errorMessage;

  UploadResult._({
    required this.isSuccess,
    this.fileId,
    this.fileUrl,
    this.thumbnailUrl,
    this.mimeType,
    this.size,
    this.errorMessage,
  });

  factory UploadResult.success({
    required String fileId,
    required String fileUrl,
    String? thumbnailUrl,
    String? mimeType,
    int? size,
  }) {
    return UploadResult._(
      isSuccess: true,
      fileId: fileId,
      fileUrl: fileUrl,
      thumbnailUrl: thumbnailUrl,
      mimeType: mimeType,
      size: size,
    );
  }

  factory UploadResult.failure(String message) {
    return UploadResult._(
      isSuccess: false,
      errorMessage: message,
    );
  }
}

// Providers
final fileUploadServiceProvider = Provider<FileUploadService>((ref) {
  final tokenManager = ref.watch(tokenManagerProvider);

  return FileUploadService(() async {
    return tokenManager.accessToken;
  });
});
