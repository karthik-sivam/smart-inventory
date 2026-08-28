# Stoqly Event Taxonomy

Owner: data-analyst. Engineers implement `StoqlyEvent` in `AnalyticsManager.swift` exactly as named here.

## Standard properties (every event)

Attached in `AnalyticsManager.track` so callers cannot forget them.

| Property | Type | Values | Notes |
|---|---|---|---|
| `app_version` | string | marketing version, e.g. `"1.4"` | `CFBundleShortVersionString` |
| `platform` | string | `"ios"` | Android uses `"android"` |
| `is_offline` | bool | | `NWPathMonitor` snapshot at fire time |
| `device_class` | string | `"phone"` \| `"tablet"` \| `"other"` | `UIDevice.userInterfaceIdiom` |
| `session_id` | string | Amplitude session id, else a process UUID | stringified `Int64` from Amplitude |

Do not put PII (email, name, IDFA) on event properties. `is_pro` is allowed (entitlement, not identity).

## AdMob lifecycle (iOS-F4)

Format enum: `banner` | `interstitial` | `rewarded`.

`unit_id` is the AdMob unit actually used for the request (needed to diagnose test vs live fill). Dashboards should treat it as an opaque token.

### `ad_requested`

Fires when: a `GADRequest` is about to be issued, **or** Dashboard/ItemList appear (banner opportunity), **or** the entitlement gate would have blocked a request.

| Property | Type | Notes |
|---|---|---|
| `unit_id` | string | AdMob unit |
| `format` | string | `banner` \| `interstitial` \| `rewarded` |
| `source_screen` | string | `Dashboard`, `ItemList`, `settings_debug`, `item_updated`, `app_launch`, … |
| `is_pro` | bool | `SubscriptionManager.isPro` at fire time |
| `suppressed` | bool | `true` when `isPro` **or** `hasRemovedAds` (`shouldShowAds == false`) |

When `suppressed=true`, no `ad_loaded` / `ad_failed_to_load` is required. That pair means “ads would have loaded but were gated.”

### `ad_loaded`

Fires when: `GADBannerViewDelegate.bannerViewDidReceiveAd` or interstitial `GADInterstitialAd.load` succeeds.

| Property | Type |
|---|---|
| `unit_id` | string |
| `format` | string |
| `latency_ms` | int |

### `ad_failed_to_load`

Fires when: banner `didFailToReceiveAdWithError`, interstitial load error, or interstitial failed to present. Simulator DEBUG probe uses `error_domain=simulator`, `error_code=-1`.

| Property | Type |
|---|---|
| `unit_id` | string |
| `format` | string |
| `error_code` | int | GAD / NSError code (1 = no fill) |
| `error_domain` | string |
| `error_localized` | string | truncated system description; not PII |

### `ad_impression`

Fires when: `bannerViewDidRecordImpression` or `adDidRecordImpression`.

| Property | Type |
|---|---|
| `unit_id` | string |
| `format` | string |
| `source_screen` | string |

### `ad_clicked`

Fires when: `bannerViewDidRecordClick` or `adDidRecordClick`.

| Property | Type |
|---|---|
| `unit_id` | string |
| `format` | string |
| `source_screen` | string |

### `ad_dismissed`

Fires when: banner full-screen overlay dismisses or interstitial `adDidDismissFullScreenContent`.

| Property | Type |
|---|---|
| `unit_id` | string |
| `format` | string |
| `dwell_ms` | int | 0 if present timestamp missing |

## Metrics these enable

- Banner opportunity → request: count `ad_requested` where `format=banner` and `source_screen in (Dashboard, ItemList)`
- Entitlement suppression rate: `ad_requested` where `suppressed=true` / all `ad_requested`
- Fill rate: `ad_loaded` / (`ad_loaded` + `ad_failed_to_load`) where `error_domain != simulator`
- No-fill: `ad_failed_to_load` where `error_code=1`
- ATT / fill interaction: join with `permission_result` (`type=tracking`) once that event is wired on ATT; until then segment by user properties if available
- Click-through: `ad_clicked` / `ad_impression`

## QA checks

1. Free account, simulator, open Dashboard: console shows `📊 [iOS-F4] Amplitude event: ad_requested` then `ad_failed_to_load` with `error_domain=simulator`.
2. Pro or Remove Ads account, open Dashboard: `ad_requested` with `suppressed=true`; no follow-up load/fail required.
3. Device DEBUG, Settings → Test Banner Ad: `ad_requested` then `ad_loaded` or `ad_failed_to_load` from the real SDK.
4. Interstitial after 2 workflow actions / 5 min: `ad_requested` (`format=interstitial`) → loaded/failed → impression/dismissed if shown.

TODO(iOS-F4): remove the DEBUG `📊 [iOS-F4]` print in `AnalyticsManager.track` after CEO confirms Amplitude is receiving these events.

## AI request terminals (iOS-D1b)

Every LLM call fires exactly one `ai_request_started` **after** paywall/usage gates, then exactly one of `ai_request_succeeded` / `ai_request_empty` / `ai_request_failed`. Do not log prompts, transcripts, OCR, or answer text on these events. `ai_help_question_asked` still logs a truncated question; that is unchanged and must not be copied onto the new events.

Existing `smart_count_completed` / `smart_count_failed` / `smart_sales_completed` / `bulk_import_*` / `ai_help_question_asked` stay. D1b adds `smart_sales_failed` as the Smart Sales counterpart of `smart_count_failed`.

Wired `feature` slugs: `voice_count`, `photo_count`, `sheet_count`, `voice_sales`, `photo_sales`, `sheet_sales`, `ask_ai_help`.

Not wired (no LLM caller): `identify_product` (photo add/edit uses `photo_count`); `sheet_import` (Bulk Import is local CSV/XLSX parse — keep `bulk_import_completed` / `bulk_import_failed` only).

Helper: `AIRequestClock` in `AITest/Services/AIRequestClock.swift`. `AIInventoryError.noItemsFound` → `ai_request_empty`, not failed. Default `provider` is `"claude"`. `error_class`: `network` | `parse_error` | `server_error` | `rate_limited` | `unknown`.

| Event | Properties | When |
|---|---|---|
| `ai_request_started` | `feature` (req), `mode?`, `input_size_kb?` | Clock `init` after the usage/paywall gate |
| `ai_request_succeeded` | `feature`, `mode?`, `item_count`, `duration_ms`, `provider` | Parsed/saved items, or a non-empty help answer (`item_count=1`) |
| `ai_request_empty` | `feature`, `mode?`, `duration_ms`, `reason` | Zero items / empty answer / no mapping suggestions |
| `ai_request_failed` | `feature`, `mode?`, `stage`, `error_class`, `reason`, `duration_ms?` | Network, parse, save, or receive error |
| `smart_sales_failed` | `mode`, `reason` | Smart Sales parse/save companion (`voice`/`photo`/`text`/`csv`/`pdf`/`batch`). Does not replace `ai_request_failed`. CSV empty-file and JPEG encode failures fire this without `ai_request_started` because no LLM ran. |

Standard `app_version` / `platform` / `is_offline` / `device_class` / `session_id` are attached centrally.

Amplitude project 832993: all five events are official under **AI / Smart Count**.

## Sync / export / reorder email (iOS-D1d)

Session pair on `pullFromCloud` and background `flushPending`. Do not log emails, mailto bodies, or file contents.

`context` on pull/flush: `cold_launch` | `foreground` | `manual` | `background_task`.

Per-document `pushItem` / `pushStorage` failures still emit `sync_failed` with `context=write` and no `sync_started` (existing write-path signal; retries stay diagnosable).

| Event | Properties | When |
|---|---|---|
| `sync_started` | `context` | After auth; pull or background flush begins |
| `sync_completed` | `context`, `docs_updated`, `duration_ms` | Pull fetched N docs, or flush pushed storage+item counts |
| `sync_failed` | `context`, `error_class`, `reason`, `duration_ms?` | Pull error (`duration_ms` set) or write error (`duration_ms` omitted). `error_class`: `network` \| `rate_limited` \| `auth` \| `server_error` \| `unknown` |
| `export_failed` | `format`, `reason` | Pair with existing `export_completed`. `format`: `csv` \| `pdf`. Reasons: `pdf_render_failed`, `documents_directory_unavailable`, or write error description |
| `reorder_email_failed` | `reason` | Pair with existing `reorder_email_sent`. Fires when `UIApplication.open(mailto:)` returns false (`cannot_open_mailto`) |

Not signed in: `pullFromCloud` returns 0 with no started/failed (callers already guard auth).
