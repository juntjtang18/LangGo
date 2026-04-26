# Data Layer Cache Notes

This document records the current cache behavior that has been added on top of the remote-first `DataService` layer.

## Current Cache Components

Generic cache infrastructure lives under `LangGo/DataService/Cache/`:

- `CacheService.swift`
- `CacheMutation.swift`
- `MemoryCacheStore.swift`
- `DiskCacheStore.swift`
- `CacheIndexStore.swift`

Collection-specific cache policy wrappers currently include:

- `ArticleCache.swift`
- `FlashcardCache.swift`
- `SettingsCache.swift`
- `UserProfileCache.swift`
- `MyUserPointsCache.swift`
- `PointGroupCache.swift`

## My User Points Cache

`/api/my-user-points` is now cached through `MyUserPointsCache`.

Implementation files:

- `LangGo/DataService/Cache/MyUserPointsCache.swift`
- `LangGo/DataService/AuthService.swift`
- `LangGo/DataService/StrapiService.swift`

Behavior:

- cache key is locale-aware: `myUserPoints.locale.<locale>`
- TTL is `60s`
- reads go through cache first
- login, signup, and account deletion invalidate the cache

## Vocabook Total Vocabulary Card

`VocabookView.totalVocabularyCard` now shows the cached `word_add` delta from `/api/my-user-points`.

Implementation file:

- `LangGo/Vocabook/VocabookView.swift`

Display:

- main value: total vocabulary count from `/api/flashcard-stat`
- delta: `+<word_add>` from `/api/my-user-points`

This keeps the card aligned with the Home points/words behavior while still using the Vocabook statistics source for the total word count.

## Point Group Cache

`/api/my-point-group` and `/api/point-groups/:id/leaderboard` are now cached through `PointGroupCache` and owned by `PointGroupService`.

Implementation files:

- `LangGo/DataService/Cache/PointGroupCache.swift`
- `LangGo/DataService/PointGroupService.swift`
- `LangGo/Home/HomeView.swift`

Behavior:

- cache keys are user-aware and locale-aware
- `/api/my-point-group` seeds both:
  - the home banner summary
  - the leaderboard sheet cache for the current group
- stale cached values can render immediately while the service refreshes in the background
- login, signup, account deletion, word creation, and flashcard review invalidate point-group cache

## Patch-On-Write For New Words

When a new word is saved through:

- `LangGo/DataService/WordService.swift`

the flow is now:

1. `POST /api/word-definitions`
2. if the write succeeds:
   - invalidate flashcard caches
   - patch cached `my-user-points`
3. if the write fails:
   - do not change local cache

Patched fields:

- `word_count += 1`
- `word_add += 1`

This avoids forcing `/api/my-user-points` to refetch immediately after every successful word creation.

## Locale Patch Scope

The patch is applied to cached entries for the known active locales:

- `nil` / default
- `UserDefaults["selectedLanguage"]`
- `UserSessionManager.shared.currentUser?.user_profile?.baseLanguage`

This is intentional:

- it updates the cache entries the app is most likely to read next
- it avoids a blind invalidation
- it avoids unnecessary network traffic

If a locale-specific cache entry does not already exist, it is not synthesized during patching.

## Design Rule

Current policy is:

- direct entity-like values that are cheap and safe to patch:
  - patch cache after successful write
- derived or complex aggregates:
  - invalidate cache after successful write

Example:

- `my-user-points.word_add` after adding a word:
  - patch
- `flashcard-stat` after adding a word:
  - invalidate

This keeps the implementation low-maintenance while reducing redundant reads from Strapi.
