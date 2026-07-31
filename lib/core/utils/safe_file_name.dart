import 'package:path/path.dart' as path;

String safeFileName(String input) {
  final base = path.basename(input.replaceAll('\\', '/')).trim();
  final sanitized = base
      .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\.{2,}'), '.')
      .replaceAll(RegExp(r'\s+'), ' ');
  final withoutLeadingDots = sanitized.replaceFirst(RegExp(r'^\.+'), '');
  if (withoutLeadingDots.isEmpty) return 'arquivo';
  return withoutLeadingDots.length > 180
      ? withoutLeadingDots.substring(withoutLeadingDots.length - 180)
      : withoutLeadingDots;
}
