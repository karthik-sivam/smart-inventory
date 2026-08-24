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
