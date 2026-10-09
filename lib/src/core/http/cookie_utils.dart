String buildCookieHeader(List<String> setCookieHeaders) {
  final jar = <String, String>{};
  for (final raw in setCookieHeaders) {
    final firstPart = raw.split(';').first.trim();
    final eq = firstPart.indexOf('=');
    if (eq <= 0) continue;
    final name = firstPart.substring(0, eq).trim();
    final value = firstPart.substring(eq + 1).trim();
    if (name.isEmpty) continue;
    jar[name] = value;
  }
  return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

String mergeCookieHeader(
  String existingCookieHeader,
  List<String> setCookieHeaders,
) {
  final jar = <String, String>{};

  for (final part in existingCookieHeader.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    final name = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1).trim();
    if (name.isEmpty || value.isEmpty) continue;
    jar[name] = value;
  }

  for (final raw in setCookieHeaders) {
    final firstPart = raw.split(';').first.trim();
    final eq = firstPart.indexOf('=');
    if (eq <= 0) continue;
    final name = firstPart.substring(0, eq).trim();
    final value = firstPart.substring(eq + 1).trim();
    if (name.isEmpty || value.isEmpty) continue;
    jar[name] = value;
  }

  return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
}
