# Testing & QA — PlayTorrioV3

This document describes basic smoke tests and QA steps for the HubPage navigation refactor and Windows QA snapshot.

Windows snapshot

- Artifact (fork release): https://github.com/David7ce/PlayTorrioV3/releases/tag/v3.0.0-hub-snapshot-2026-08-21
- ZIP: playtorrio-windows-x64-2026-08-21.zip containing playtorrio.exe

Smoke test steps (Windows)

1. Unzip the release ZIP and run playtorrio.exe. If antivirus or SmartScreen prompts appear, allow it for testing.
2. Confirm app launches and the home screen (hero carousel) is visible.
3. Use the bottom dock to switch hubs (Movies & Series, Anime, Manga, Audiobooks, Music, Collection).
   - Confirm hub content updates for each selection.
   - Verify switching preserves previously viewed hub scroll positions (IndexedStack behavior).
4. Test Back behavior:
   - From a hub (e.g., Anime), press ESC or use the window's Close button — app should close only from Home (or behave consistently with platform expectations).
   - Open Settings from the dock and press Back/ESC — Settings should dismiss and return to the current hub.
5. Open a Details page (e.g., tap a movie) and press Back — should return to the previous hub view.
6. Run a quick playback flow (if sample sources are available) to verify player initialisation and Trakt scrobbling placeholders operate (no real credentials required unless configured).

Additional checks

- Run `flutter analyze` locally to ensure no analyzer errors remain.
- Run `flutter test` for any unit tests (if present) and verify no test regressions.
- Smoke test on other desktop platforms (macOS/Linux) where available.

Notes

- The binary in the release is built from branch `feat/navigation/hub-page-skeleton` on 2026-08-21.
- If issues are found, capture screenshots, console logs, and steps to reproduce and attach them to the PR.
