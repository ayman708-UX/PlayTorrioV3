# Logging & Diagnostics Guide — PlayTorrioV3

This document outlines the logging strategy, error diagnostic protocols, and runtime auditing standards for **PlayTorrioV3**.

---

## 1. Log Levels

1. **DEBUG (`[DEBUG]`):** Fine-grained execution traces of JavaScript scrapers, internal REST/GraphQL API payloads, and widget lifecycle events.
2. **INFO (`[INFO]`):** Playback initialization events, core service boots (`AddonManager`, `DownloadService`, `MyListService`, `TraktAuthService`), and hub navigation transitions.
3. **WARNING (`[WARN]`):** Scraper timeouts, fallback subtitle queries, and transient network recovery events.
4. **ERROR (`[ERROR]`):** Unhandled native playback engine (`fvp`) exceptions, hardware codec decoding failures, and critical network drops.

---

## 2. Output & Log Sinks

- **Development Console (Flutter Debug Console / Terminal):**
  - Formatted with `HH:mm:ss.SSS` timestamps and component tags such as `[ScraperManager]`, `[PlayerCore]`, `[TraktSync]`, `[DownloadManager]`.
- **Debug / Profiling Mode:**
  - Shader frame metrics via `PerformanceLiquidLens` to audit GPU frame drops and jank.

---

## 3. Scraper Diagnostics (`assets/scrapers/`)

For debugging JS extractors or verifying resolved stream URLs:
- Use helper scripts located in the `TempJs/` directory for isolated testing via Node.js / Dart CLI.
- Inspect JS evaluator logs to capture request parameters, custom headers (*Referer*, *User-Agent*), and JSON output formats.

---

## ROADMAP -> CHANGELOG migration logs

- 2026-08-21: Consolidated completed ROADMAP items into docs/CHANGELOG.md under an [unreleased] section. Items moved include:
  - Streamlined Navigation (7 hubs)
  - Unified Collection Hub (My List, Watchlist, History, Downloads)
  - Dedicated Anime Hub
  - Rich Cast & Crew (TMDB headshots)
  - Debrid Integration (Real-Debrid, Torbox)
  - Player timeouts & Trakt scrobbling
  - Addons Management in Settings

These moves were automated as part of the HubPage refactor workflow.
