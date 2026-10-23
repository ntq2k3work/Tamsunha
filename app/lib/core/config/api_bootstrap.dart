final class ApiBootstrap {
  const ApiBootstrap._(this.baseUrl);

  factory ApiBootstrap.fromEnvironment() => ApiBootstrap._(
        const String.fromEnvironment('API_BASE_URL').trim().replaceAll(RegExp(r'/$'), ''),
      );

  final String baseUrl;

  bool get isConfigured {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    return uri.scheme == 'https' ||
        (uri.scheme == 'http' &&
            (uri.host == 'localhost' || uri.host == '127.0.0.1' ||
                uri.host == '10.0.2.2' || _isPrivateLan(uri.host)));
  }

  static bool _isPrivateLan(String host) =>
      host.startsWith('192.168.') || host.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host);
}
