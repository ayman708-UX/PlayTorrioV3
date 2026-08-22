/// Tracks the currently active search scope so that search results are limited
/// to the section the user is currently browsing.
///
/// Each hub/section registers its content type (e.g. 'movie', 'series',
/// 'anime', 'audiobook', 'manga') when it becomes active. The [SearchPage]
/// reads the current scope and passes it to the addon search so results are
/// scoped accordingly.
abstract final class SearchScope {
  static String? _contentType;
  static String? _label;

  /// Sets the active search scope. Pass `null` to search everything.
  static void set(String? contentType, {String? label}) {
    _contentType = contentType;
    _label = label;
  }

  /// The content type to scope search to, or null for "all".
  static String? get contentType => _contentType;

  /// A human-readable label describing the current scope (e.g. "Movies").
  static String? get label => _label;
}
