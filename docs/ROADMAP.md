# Project Roadmap — PlayTorrioV3

This document outlines the strategic roadmap for UI/UX redesign, navigation simplification, modular refactoring, streaming capabilities, and core functional enhancements for **PlayTorrioV3**.

---

## 🎯 Primary Goals

1. **Streamlined Navigation:** [COMPLETED] Reduced bottom dock clutter down to 5 essential persistent hubs.
2. **Unified "Collection" Hub:** [COMPLETED] Consolidated My List, Watchlist, Playback History, and Offline Downloads manager.
3. **"Media" Hub:** [COMPLETED] Evolved the home screen into a unified Media Hub with native Anime integration.
4. **Rich Visual Cast & Crew:** [COMPLETED] Displayed high-resolution TMDB headshots for actors and directors with character role mapping.
5. **Debrid Service Integration (Real-Debrid / Torbox):** [COMPLETED] Added Debrid provider manager in Settings for high-speed cloud stream resolving.
6. **Advanced Video Player:** Auto-Next/Binge watching, audio track & subtitle switcher, `libass` anime subtitle styling, and gesture controls.
7. **Dual Scrobbling (Trakt + AniList):** Automatic progress tracking for movies/series (Trakt) and anime (AniList).
8. **Addons Management in Settings:** [COMPLETED] Centralized scraper and plugin configuration inside the settings view.

---

## 📅 Implementation Status

| Phase | Milestone | Status | Key Deliverables |
| :--- | :--- | :--- | :--- |
| **Phase 1** | UI & Dock Simplification | ✅ **Completed** | 5-item `LiquidDock`, persistent across all hubs (`AppDock`), Addons moved to Settings. |
| **Phase 2** | Collection & Media Hub | ✅ **Completed** | `CollectionPage` with My List, Watchlist, and Offline Downloads; Media Hub with Anime chip. |
| **Phase 3** | Cast & Crew Enrichment | ✅ **Completed** | `CastMember` & `CrewMember` models, TMDB profile images, Direction section, tap-to-discover. |
| **Phase 4** | Cloud Debrid Services | ✅ **Completed** | `DebridService` with Real-Debrid & Torbox token verification in Settings. |
| **Phase 5** | Player Engine & Scrobbling | ⏳ **In Progress** | Player gesture controls, track selectors, and Trakt/AniList automatic scrobblers. |

---

## 📌 Module Breakdown & Progress Details

### 1. LiquidDock & Main Navigation [COMPLETED]
* ✅ **Simplified Layout:** 5 primary persistent hubs:
  - 🎬 **Media:** Unified hub for Movies, TV Series, and Anime.
  - 📖 **Manga:** Manga/comic reader and library.
  - 🎧 **Audiobooks:** Curated audiobook scraper and player.
  - 🎵 **Music:** Octave music streaming and playlists.
  - 📂 **Collection:** User lists, Watchlist, and Offline Downloads.
* ✅ **Persistent Dock:** `AppDock` keeps bottom navigation visible and accessible from all pages without disappearing.

### 2. Collection Hub (`lib/pages/collection/`) [COMPLETED]
* ✅ **Tab 1 - My List / Favorites:** Filter by Movie/Series/Anime, sort by recent/title/year, sync with Trakt.
* ✅ **Tab 2 - Watchlist:** Integrated watchlist tracking for saved media.
* ✅ **Tab 3 - Downloads:** Offline download manager (`DownloadService`) supporting queue tracking and status monitoring.

### 3. Media Hub & Anime Integration [COMPLETED]
* ✅ Top bar quick launch chip in `HomePage` providing direct fluid access to `AnimePage`.

### 4. Cast & Directors with Images (`lib/pages/details/`) [COMPLETED]
* ✅ `CastMember` model parsing TMDB profile URLs and character roles.
* ✅ Dedicated `Direction` section with director avatar and tap-to-discover filmography search.
* ✅ Smooth fallback to initial badges with animated color pairs.

### 5. Debrid Providers (`lib/services/debrid/`) [COMPLETED]
* ✅ Support for **Real-Debrid** and **Torbox** account verification and persistent token storage.
* ✅ Seamless connection management inside `SettingsPage`.

### 6. Video Player Enhancements (`lib/pages/player/`) [PLANNED]
* Touch & mouse gesture controls for brightness, volume, and seeking.
* Auto-next episode prompt during credits.
* Embedded MKV/MP4 audio track and subtitle selector.

### 7. Automated Scrobbling (`Trakt` & `AniList`) [PLANNED]
* Trakt background scrobbler at 80-90% playback progress.
* AniList episode watch-count synchronization.
