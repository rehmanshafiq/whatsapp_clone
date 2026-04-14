/// Derives a user-visible document name when the API omits [file_name] / [body]
/// (common for the sender's own uploads). Cloudinary-style paths often use
/// `{uuid}_{timestamp}_{sanitizedBaseName}` without a file extension in the URL.
String? deriveDocumentFileNameFromAttachmentUrl(String url) {
  if (url.isEmpty) return null;
  final path = Uri.tryParse(url)?.path ?? url;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  var last = Uri.decodeComponent(segments.last);
  if (last.isEmpty) return null;
  if (last.contains('.')) return last;

  final stripped = RegExp(
    r'^[0-9a-fA-F-]+_\d+_(.+)$',
    caseSensitive: false,
  ).firstMatch(last);
  if (stripped != null) {
    final rest = stripped.group(1);
    if (rest != null && rest.isNotEmpty) {
      return _humanizeDocumentSlug(rest);
    }
  }
  return _humanizeDocumentSlug(last);
}

String _humanizeDocumentSlug(String slug) {
  var t = slug.replaceAll('_', ' ').replaceAll(RegExp(r'-+'), ' ');
  t = t.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  return t.trim();
}
