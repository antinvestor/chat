import 'dart:io';
import 'dart:typed_data';

import 'package:antinvestor_api_files/antinvestor_api_files.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../logging/app_logger.dart';
import '../networking/client.dart';
import 'mxc_download_service.dart';
import 'mxc_uri.dart';

/// Resolves media content from message content maps to downloadable bytes.
///
/// Bridges between the old content format (`{url: "https://..."}`) and the
/// new MXC format (`{contentUri: "mxc://...", mediaId, serverName}`).
///
/// Resolution priority:
/// 1. `contentUri` (new MXC format) → use [MxcDownloadService]
/// 2. `url` starting with `mxc://` → parse and use [MxcDownloadService]
/// 3. `url` as HTTPS → legacy HTTP GET
/// 4. `localPath` → read from local file (pending upload)
class ContentResolver {
  ContentResolver(this._downloadService, this._getAccessToken);

  final MxcDownloadService _downloadService;
  final Future<String?> Function() _getAccessToken;

  /// Resolve an image URL from message content, returning bytes.
  ///
  /// For MXC URIs, fetches a server-generated thumbnail at the specified
  /// dimensions for better performance. For HTTPS URLs, downloads the full
  /// image.
  Future<Uint8List?> resolveImageUrl(
    Map<String, dynamic> content, {
    int? width,
    int? height,
  }) async {
    final mxcUri = _extractMxcUri(content);
    if (mxcUri != null) {
      // Use thumbnail API if dimensions provided, else full content
      if (width != null && height != null) {
        return _downloadService.downloadThumbnail(
          mxcUri,
          width: width,
          height: height,
        );
      }
      return _downloadService.downloadContent(mxcUri);
    }

    // Legacy HTTPS URL
    final url = content['url'] as String?;
    if (url != null && url.startsWith('http')) {
      return _downloadLegacyUrl(url);
    }

    // Local file (pending upload)
    final localPath = content['localPath'] as String?;
    if (localPath != null) {
      return _readLocalFile(localPath);
    }

    return null;
  }

  /// Resolve a file download from message content, saving to [destPath].
  Future<File?> resolveFileDownload(
    Map<String, dynamic> content,
    String destPath,
  ) async {
    final mxcUri = _extractMxcUri(content);
    if (mxcUri != null) {
      return _downloadService.downloadContentToFile(mxcUri, destPath);
    }

    // Legacy HTTPS URL
    final url = content['url'] as String?;
    if (url != null && url.startsWith('http')) {
      final bytes = await _downloadLegacyUrl(url);
      if (bytes != null) {
        final file = File(destPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        return file;
      }
    }

    // Local file
    final localPath = content['localPath'] as String?;
    if (localPath != null) {
      final source = File(localPath);
      if (source.existsSync()) {
        return source.copy(destPath);
      }
    }

    return null;
  }

  /// Resolve a video thumbnail from message content.
  Future<Uint8List?> resolveVideoThumbnail(
    Map<String, dynamic> content, {
    int width = 256,
    int height = 256,
  }) async {
    // Try MXC thumbnail URI first
    final thumbnailUri = _extractThumbnailMxcUri(content);
    if (thumbnailUri != null) {
      return _downloadService.downloadContent(thumbnailUri);
    }

    // Try main content as thumbnail via server
    final mxcUri = _extractMxcUri(content);
    if (mxcUri != null) {
      return _downloadService.downloadThumbnail(
        mxcUri,
        width: width,
        height: height,
        method: ThumbnailMethod.CROP,
      );
    }

    // Legacy thumbnail URL
    final thumbnailUrl = content['thumbnailUrl'] as String?;
    if (thumbnailUrl != null && thumbnailUrl.startsWith('http')) {
      return _downloadLegacyUrl(thumbnailUrl);
    }

    // Local thumbnail
    final localThumbnailPath = content['localThumbnailPath'] as String?;
    if (localThumbnailPath != null) {
      return _readLocalFile(localThumbnailPath);
    }

    return null;
  }

  /// Resolve the display URL for a media item.
  ///
  /// Returns a URL string suitable for widgets that need a URL rather than
  /// bytes (e.g. `CachedNetworkImage`). For MXC URIs, returns null since
  /// those require the download service. For legacy URLs, returns the URL
  /// directly.
  String? resolveLegacyUrl(Map<String, dynamic> content) {
    // If it has an MXC URI, we can't use it directly as an HTTP URL
    if (_extractMxcUri(content) != null) return null;

    // Legacy HTTPS URL
    final url = content['url'] as String?;
    if (url != null && url.startsWith('http')) return url;

    return null;
  }

  /// Check whether content uses the new MXC format.
  static bool isMxcContent(Map<String, dynamic> content) {
    final contentUri = content['contentUri'] as String?;
    if (contentUri != null && MxcUri.isMxcUri(contentUri)) return true;

    final url = content['url'] as String?;
    if (url != null && MxcUri.isMxcUri(url)) return true;

    return false;
  }

  /// Extract an MXC URI from content, checking both new and legacy formats.
  MxcUri? _extractMxcUri(Map<String, dynamic> content) {
    // New format: explicit contentUri field
    final contentUri = content['contentUri'] as String?;
    if (contentUri != null && MxcUri.isMxcUri(contentUri)) {
      return MxcUri.tryParse(contentUri);
    }

    // Legacy format: url field might contain an MXC URI
    final url = content['url'] as String?;
    if (url != null && MxcUri.isMxcUri(url)) {
      return MxcUri.tryParse(url);
    }

    // New format: explicit serverName + mediaId fields
    final serverName = content['serverName'] as String?;
    final mediaId = content['mediaId'] as String?;
    if (serverName != null &&
        serverName.isNotEmpty &&
        mediaId != null &&
        mediaId.isNotEmpty) {
      return MxcUri.fromParts(serverName, mediaId);
    }

    return null;
  }

  /// Extract a thumbnail MXC URI from content.
  MxcUri? _extractThumbnailMxcUri(Map<String, dynamic> content) {
    final thumbnailUri = content['thumbnailContentUri'] as String?;
    if (thumbnailUri != null && MxcUri.isMxcUri(thumbnailUri)) {
      return MxcUri.tryParse(thumbnailUri);
    }

    final thumbnailUrl = content['thumbnailUrl'] as String?;
    if (thumbnailUrl != null && MxcUri.isMxcUri(thumbnailUrl)) {
      return MxcUri.tryParse(thumbnailUrl);
    }

    return null;
  }

  /// Download from a legacy HTTPS URL.
  Future<Uint8List?> _downloadLegacyUrl(String url) async {
    try {
      final token = await _getAccessToken();
      final response = await http.get(
        Uri.parse(url),
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Legacy URL download failed',
        error: e,
        stackTrace: stackTrace,
        data: {'url': url},
      );
      return null;
    }
  }

  /// Read bytes from a local file path.
  Future<Uint8List?> _readLocalFile(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return file.readAsBytes();
      }
      return null;
    } catch (e) {
      AppLogger.debug('Failed to read local file: $path');
      return null;
    }
  }
}

/// Provider for [ContentResolver].
final contentResolverProvider = Provider<ContentResolver>((ref) {
  final downloadService = ref.watch(mxcDownloadServiceProvider);
  final tokenManager = ref.watch(tokenManagerProvider);
  return ContentResolver(downloadService, () async => tokenManager.accessToken);
});
