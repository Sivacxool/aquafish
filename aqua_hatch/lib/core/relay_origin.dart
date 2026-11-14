const defaultRelayOrigin =
    'https://aquahatch-relay.aquahatch-relay.workers.dev';

Uri? parseRelayOrigin(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  const label = r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?';
  if (!RegExp(
    '^$label\\.$label'
    r'\.workers\.dev$',
  ).hasMatch(uri.host)) {
    return null;
  }
  return Uri(scheme: 'https', host: uri.host);
}
