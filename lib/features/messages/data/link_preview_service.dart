import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../core/networking/api_config.dart';
import '../../../core/networking/client.dart';
import '../domain/link_preview.dart';

/// Service for fetching OpenGraph link previews
///
/// Fetches metadata from URLs to display rich previews in messages.
/// Supports caching, timeout handling, and graceful degradation.
class LinkPreviewService {
  LinkPreviewService(this._getAccessToken);

  final Future<String?> Function() _getAccessToken;

  /// In-memory cache for link previews (LRU with TTL)
  final Map<String, _CachedPreview> _cache = {};
  static const int _maxCacheSize = 100;
  static const Duration _cacheTtl = Duration(hours: 1);
  static const Duration _fetchTimeout = Duration(seconds: 5);

  /// Fetch link preview for a URL
  ///
  /// Returns cached result if available, otherwise fetches from server.
  /// Returns null if fetch fails or URL is invalid.
  Future<LinkPreview?> fetchPreview(String url) async {
    // Validate URL
    if (!_isValidUrl(url)) {
      return null;
    }

    // Check cache first
    final cached = _getCached(url);
    if (cached != null) {
      return cached;
    }

    try {
      final preview = await _fetchFromServer(url).timeout(_fetchTimeout);
      if (preview != null) {
        _addToCache(url, preview);
      }
      return preview;
    } on TimeoutException {
      AppLogger.warning('Link preview fetch timed out', data: {'url': url});
      return null;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to fetch link preview',
        error: e,
        stackTrace: stackTrace,
        data: {'url': url},
      );
      return null;
    }
  }

  /// Extract URLs from text message
  static List<String> extractUrls(String text) {
    final urlPattern = RegExp(
      r'https?://[^\s<>\[\]{}|\\^`"]+',
      caseSensitive: false,
    );

    return urlPattern
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where(_isValidUrl)
        .toList();
  }

  /// Check if URL is valid and should have preview fetched
  static bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) {
        return false;
      }
      // Skip certain file types that don't have OpenGraph
      final path = uri.path.toLowerCase();
      if (path.endsWith('.pdf') ||
          path.endsWith('.zip') ||
          path.endsWith('.tar') ||
          path.endsWith('.gz') ||
          path.endsWith('.exe') ||
          path.endsWith('.dmg')) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<LinkPreview?> _fetchFromServer(String url) async {
    final token = await _getAccessToken();

    // Use files service for URL preview endpoint
    final uri = Uri.parse(
      '${ApiConfig.filesBaseUrl}/v1/preview',
    ).replace(queryParameters: {'url': url});

    final response = await http.get(
      uri,
      headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return LinkPreview.fromJson(json);
    }

    // Fallback: Try to fetch directly and parse OpenGraph tags
    return _fetchDirectly(url);
  }

  /// Fallback method to fetch OpenGraph tags directly from the URL
  Future<LinkPreview?> _fetchDirectly(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (compatible; LinkPreviewBot/1.0; +https://antinvestor.com)',
            },
          )
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        return null;
      }

      final html = response.body;
      return _parseOpenGraphTags(url, html);
    } catch (e) {
      AppLogger.debug('Direct fetch failed for $url: $e');
      return null;
    }
  }

  /// Parse OpenGraph tags from HTML
  LinkPreview? _parseOpenGraphTags(String url, String html) {
    String? title;
    String? description;
    String? imageUrl;
    String? siteName;
    String? favicon;

    // Parse og:title
    final titleMatch = RegExp(
      '''<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    title = titleMatch?.group(1);

    // Fallback to <title> tag
    if (title == null || title.isEmpty) {
      final htmlTitleMatch = RegExp(
        '<title[^>]*>([^<]*)</title>',
        caseSensitive: false,
      ).firstMatch(html);
      title = htmlTitleMatch?.group(1)?.trim();
    }

    // Parse og:description
    final descMatch = RegExp(
      '''<meta[^>]*property=["']og:description["'][^>]*content=["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    description = descMatch?.group(1);

    // Fallback to meta description
    if (description == null || description.isEmpty) {
      final metaDescMatch = RegExp(
        '''<meta[^>]*name=["']description["'][^>]*content=["']([^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      description = metaDescMatch?.group(1);
    }

    // Parse og:image
    final imageMatch = RegExp(
      '''<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    imageUrl = imageMatch?.group(1);

    // Parse og:site_name
    final siteMatch = RegExp(
      '''<meta[^>]*property=["']og:site_name["'][^>]*content=["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    siteName = siteMatch?.group(1);

    // Parse favicon
    final faviconMatch = RegExp(
      '''<link[^>]*rel=["'](?:shortcut )?icon["'][^>]*href=["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    favicon = faviconMatch?.group(1);

    // Resolve relative URLs
    final baseUri = Uri.parse(url);
    if (imageUrl != null && !imageUrl.startsWith('http')) {
      imageUrl = baseUri.resolve(imageUrl).toString();
    }
    if (favicon != null && !favicon.startsWith('http')) {
      favicon = baseUri.resolve(favicon).toString();
    }

    // Need at least a title to return a preview
    if (title == null || title.isEmpty) {
      return null;
    }

    return LinkPreview(
      url: url,
      title: _decodeHtmlEntities(title),
      description: description != null
          ? _decodeHtmlEntities(description)
          : null,
      imageUrl: imageUrl,
      siteName: siteName ?? baseUri.host,
      favicon: favicon,
    );
  }

  /// Decode common HTML entities
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/');
  }

  LinkPreview? _getCached(String url) {
    final cached = _cache[url];
    if (cached == null) return null;

    // Check if expired
    if (DateTime.now().difference(cached.timestamp) > _cacheTtl) {
      _cache.remove(url);
      return null;
    }

    return cached.preview;
  }

  void _addToCache(String url, LinkPreview preview) {
    // Evict oldest entries if cache is full
    if (_cache.length >= _maxCacheSize) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b,
      );
      _cache.remove(oldest.key);
    }

    _cache[url] = _CachedPreview(preview: preview, timestamp: DateTime.now());
  }

  /// Clear cache (useful for testing or memory pressure)
  void clearCache() {
    _cache.clear();
  }
}

class _CachedPreview {
  _CachedPreview({required this.preview, required this.timestamp});
  final LinkPreview preview;
  final DateTime timestamp;
}

// Provider
final linkPreviewServiceProvider = Provider<LinkPreviewService>((ref) {
  final tokenManager = ref.watch(tokenManagerProvider);
  return LinkPreviewService(() async => tokenManager.accessToken);
});

/// Provider to fetch link preview for a specific URL
final linkPreviewProvider = FutureProvider.family<LinkPreview?, String>((
  ref,
  url,
) async {
  final service = ref.watch(linkPreviewServiceProvider);
  return service.fetchPreview(url);
});

/// Provider to extract and fetch previews for all URLs in a message
final messageLinksPreviewProvider =
    FutureProvider.family<List<LinkPreview>, String>((ref, text) async {
      final service = ref.watch(linkPreviewServiceProvider);
      final urls = LinkPreviewService.extractUrls(text);

      if (urls.isEmpty) {
        return [];
      }

      // Only fetch preview for the first URL to avoid overwhelming the UI
      final preview = await service.fetchPreview(urls.first);
      return preview != null ? [preview] : [];
    });
