class BackendConfig {
  final Uri baseUri;

  const BackendConfig({required this.baseUri});

  static BackendConfig? fromEnvironment() {
    const raw = String.fromEnvironment("BACKEND_BASE_URL");
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return BackendConfig(baseUri: uri);
  }
}
