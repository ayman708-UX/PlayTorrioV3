# Project Roadmap — PlayTorrioV3

This document outlines the strategic roadmap for UI/UX redesign, navigation simplification, modular refactoring, streaming capabilities, and core functional enhancements for **PlayTorrioV3**.

---

## 🎯 Primary Goals

1. **Streamlined Navigation:** [COMPLETED] Reduced bottom dock clutter down to 7 dedicated persistent hubs (`Movies & Series`, `Anime`, `Manga`, `Audiobooks`, `Music`, `Collection`, `Settings`).
2. **Unified "Collection" Hub:** [COMPLETED] Consolidated My List, Watchlist, Playback History (Continue Watching), and Offline Downloads manager.
3. **Dedicated "Anime" Hub:** [COMPLETED] Placed Anime into its own dedicated hub directly next to Movies & Series.
4. **Rich Visual Cast & Crew:** [COMPLETED] Displayed high-resolution TMDB headshots for actors and directors with character role mapping and direct filmography search.
5. **Debrid Service Integration (Real-Debrid / Torbox):** [COMPLETED] Added Debrid provider manager in Settings for high-speed cloud stream resolving.
6. **Robust Video Player & Timeout Protection:** [COMPLETED] 15s initialization timeout with friendly quota/server errors, auto-progress tracking, and resume support.
7. **Automated Scrobbling (Trakt.tv):** [COMPLETED] Real-time scrobbler reporting periodic playback progress and completion triggers to Trakt.tv.
8. **Addons Management in Settings:** [COMPLETED] Centralized scraper and plugin configuration inside the settings view.

---

## 📅 Implementation Status

| Phase | Milestone | Status | Key Deliverables |
| :--- | :--- | :--- | :--- |
| **Phase 1** | UI & Dock Simplification | ✅ **Completed** | 7-item persistent `LiquidDock` (`AppDock`), dedicated Anime hub, Addons & Settings in dock. |
| **Phase 2** | Collection Hub & History | ✅ **Completed** | `CollectionPage` with My List, Watchlist, History (Continue Watching), and Offline Downloads. |
| **Phase 3** | Cast & Crew Enrichment | ✅ **Completed** | `CastMember` & `CrewMember` models, TMDB profile images, Direction section, tap-to-discover. |
| **Phase 4** | Cloud Debrid Services | ✅ **Completed** | `DebridService` with Real-Debrid & Torbox token verification in Settings. |
| **Phase 5** | Player Engine & Scrobbling | ✅ **Completed** | Auto-progress recording, 15s connect timeout safety, Trakt automatic scrobbler. |
| **Phase 6** | Advanced Player Gestures | ⏳ **Pending** | Swipes for volume/brightness and auto-next episode countdown during credits. |

---

## 📌 Module Breakdown & Progress Details

### 1. LiquidDock & Main Navigation [COMPLETED]
* ✅ **Layout:** 7 dedicated persistent hubs:
  - 🎬 **Movies & Series:** VOD movies and series catalogs.
  - 🎭 **Anime:** Dedicated AniList hub with airing schedules and genre filters.
  - 📖 **Manga:** Manga/comic reader and library.
  - 🎧 **Audiobooks:** Curated audiobook scraper and player.
  - 🎵 **Music:** Octave music streaming and playlists.
  - 📂 **Collection:** User lists, Watchlist, History, and Offline Downloads.
  - ⚙️ **Settings:** Addons, Debrid, Trakt, and shader settings.
* ✅ **Persistent Dock:** `AppDock` keeps bottom navigation visible and accessible from all pages without disappearing.

### 2. Collection Hub (`lib/pages/collection/`) [COMPLETED]
* ✅ **Tab 1 - My List / Favorites:** Filter by Movie/Series/Anime, sort by recent/title/year, sync with Trakt.
* ✅ **Tab 2 - Watchlist:** Integrated watchlist tracking for saved media.
* ✅ **Tab 3 - History:** Granular resume points and progress bars for in-progress and completed items.
* ✅ **Tab 4 - Downloads:** Offline download manager (`DownloadService`) supporting queue tracking and status monitoring.

### 3. Cast & Directors with Images (`lib/pages/details/`) [COMPLETED]
* ✅ `CastMember` model parsing TMDB profile URLs and character roles.
* ✅ Dedicated `Direction` section with director avatar and tap-to-discover filmography search.
* ✅ Button updated to `"Add to Collection"` / `"In Collection"`.

### 4. Debrid Providers (`lib/services/debrid/`) [COMPLETED]
* ✅ Support for **Real-Debrid** and **Torbox** account verification and persistent token storage.
* ✅ Seamless connection management inside `SettingsPage`.

### 5. Video Player & Scrobbling (`lib/pages/player/`, `lib/services/trakt/`) [COMPLETED]
* ✅ 15-second initialization timeout guard preventing video loading lockups.
* ✅ Automatic periodic progress sync and playback resumption from history.
* ✅ Automated Trakt.tv scrobbling during playback and on completion.

---

## 🔮 Pending Future Enhancements

1. **In-Player Gestures:** Vertical swipes for volume and brightness, horizontal swipe for scrubbing.
2. **Auto-Next Episode Dialog:** Automatic prompt countdown in the final credits to jump to next chapter.
