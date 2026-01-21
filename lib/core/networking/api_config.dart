/// API endpoint configuration for AntInvestor services
///
/// Each service has its own dedicated endpoint for optimal routing
/// and load balancing.
class ApiConfig {
  const ApiConfig._();
  // Service endpoints
  static const String chatBaseUrl = 'https://chat.antinvestor.com';
  static const String gatewayBaseUrl = 'https://gateway.antinvestor.com';
  static const String devicesBaseUrl = 'https://devices.antinvestor.com';
  static const String filesBaseUrl = 'https://files.antinvestor.com';
  static const String profileBaseUrl = 'https://profile.antinvestor.com';

  // OAuth2 configuration
  static const String oauth2IssuerUrl = 'https://oauth2.antinvestor.com';
  static const String oauth2ClientId = '9bsv0s0hijjg02qk7l1g';

  // Connection settings optimized for low-resource devices
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration idleTimeout = Duration(seconds: 120);

  // Retry configuration
  static const int maxRetryAttempts = 3;
  static const Duration initialRetryDelay = Duration(seconds: 1);
  static const Duration maxRetryDelay = Duration(seconds: 30);

  // Batch sizes for low-resource optimization
  static const int defaultPageSize = 20;
  static const int maxPageSize = 50;

  // Cache configuration
  static const Duration cacheMaxAge = Duration(hours: 1);
  static const int maxCacheEntries = 100;
}
