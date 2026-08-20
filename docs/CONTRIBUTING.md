# Contributing to PlayTorrio V3

Thanks for your interest in contributing. This document outlines the process.

## Getting Started

1. Fork the repository and clone your fork.
2. Run `flutter pub get` to install dependencies.
3. Run `flutter analyze` to verify no existing issues.
4. Make your changes on a feature branch.

## Adding a New VOD Scraper

PlayTorrio uses a plugin architecture for stream scrapers. To add a new source:

1. Create a new file in `lib/services/scraper/sites/`.
2. Extend the `StreamScraper` abstract class:

```dart
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

class MyScraper extends StreamScraper {
  @override
  String get name => 'MyScraper';

  @override
  Future<List<StreamSource>> scrape({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async {
    // Implement scraping logic here
    // Return list of StreamSource objects
  }
}
```

3. Register your scraper in `lib/services/stream/stream_service.dart` inside `_registerScrapers()`.
4. Add a corresponding JS file in `assets/scrapers/` and an entry in `assets/scrapers/sources.json`.

## Adding a New Subtitle Provider

1. Create a file in `lib/services/subtitles/providers/`.
2. Implement the `SubtitleProvider` abstract class.
3. Register in `lib/services/subtitles/subtitle_service.dart`.

## Code Style

- Follow the existing patterns in the codebase (singleton services, static utility classes).
- Prefer `const` constructors where possible.
- Use `final` over `var` when a variable is not reassigned.
- Handle errors gracefully — a single failing scraper should never crash the app.
- Cache network responses where appropriate using the existing LRU pattern.

## Before Submitting

- Run `flutter analyze` and fix all warnings.
- Run `flutter test` to verify existing tests pass.
- If you added a scraper or provider, test it against a known-good title.
- Do not commit API keys or tokens. Use the `secrets.example.dart` pattern.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
