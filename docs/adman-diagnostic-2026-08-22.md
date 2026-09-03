# AdMob “no ads visible” diagnostic

**Date:** 2026-08-22 (inspected 2026-08-23)
**Branch:** `iOS-F4` (code inspection only — no AdMob configuration changed)
**Method:** static read of `AdManager.swift`, callsites, `Info.plist`, ATT, StoreKit gating, SPM packages
**Constraint:** unit IDs redacted to `ca-app-pub-XXX/YYY` in this document

This ticket instruments Amplitude so production can prove/disprove the hypotheses below within ~48 hours of shipping. **Do not change AdMob config until the CEO reviews this report.**

---

## 1. AdMob unit IDs in use

| Slot | Kind in code | Test vs production |
|---|---|---|
| App ID (`GADApplicationIdentifier` in Info.plist) | `ca-app-pub-XXX~YYY` | **Production** publisher app ID (not Google’s sample `~1458002511`) |
| Banner (`AdManager.bannerAdUnitID`) | `ca-app-pub-XXX/YYY` | **Production** unit |
| Interstitial (`AdManager.interstitialAdUnitID`) | `ca-app-pub-XXX/YYY` | **Production** unit |
| Rewarded | none | **Not implemented** — `ADMOB_INTEGRATION.md` still lists Google’s test rewarded unit, but `AdManager` has no rewarded loader, no unit property, and Settings has no “Test Reward Ad” |

Google sample (test) units exist as `testBannerUnitID` / `testInterstitialUnitID` (`ca-app-pub-3940256099942544/…`).

**Which ID actually loads:**

- Interstitial: `isLiveBuild` → DEBUG uses Google **test** interstitial; Release uses the **production** interstitial.
- Banner: `BannerAdView` is always constructed with `adManager.bannerAdUnitID` (the **production** banner). DEBUG does **not** swap to `testBannerUnitID`. This is a live/test mismatch vs interstitial.

**Implication:** DEBUG device builds request **real** banner inventory. Combined with an empty test-device list (see §4), AdMob may serve nothing, limited ads, or policy-limited traffic. Release uses production banner + production interstitial (consistent). Simulator never calls the GMA SDK at all (`#if targetEnvironment(simulator)`).

---

## 2. SDK initialization and delegate

**Initialized on app launch?** Indirectly. `AdManager.init` does **not** call `GADMobileAds.sharedInstance().start`. Comment: initialization is deferred until ATT is resolved.

**Call chain:**

1. `SmartInventoryApp.body` `.task` → `TrackingPermissionManager.requestPermissionIfNeeded()`
2. `InventoryAppView.body` `.task` → same method again (idempotent if ATT already determined)
3. After ATT is authorized / denied / already determined → `AdManager.initializeAfterTrackingDecision()`
4. That method reads `GADApplicationIdentifier`, then `GADMobileAds.sharedInstance().start { status in … }` and preloads an interstitial

**Delegates set:**

| Object | Delegate | Set? |
|---|---|---|
| `GADMobileAds` start completion | adapter status logged only | Yes (not a request delegate) |
| `GADInterstitialAd.fullScreenContentDelegate` | `AdManager` (`GADFullScreenContentDelegate`) | Yes, after each successful load |
| `GADBannerView.delegate` | **was unset** (iOS-F4 now sets `BannerAdView.Coordinator`) | Instrumentation only — does not change which unit is requested |

On **simulator**, `initializeAfterTrackingDecision` sets `isInitialized = true` and returns without starting GMA. `recordCompletion` is a no-op on simulator. No real ads can appear in Simulator by design.

---

## 3. App Tracking Transparency (ATT)

**Requested?** Yes.

**When:**

- `NSUserTrackingUsageDescription` is set via Xcode build setting `INFOPLIST_KEY_NSUserTrackingUsageDescription` (not duplicated in `Info.plist`; `GENERATE_INFOPLIST_FILE = YES`).
- `requestPermissionIfNeeded()` sleeps **0.8s**, then presents `ATTrackingManager.requestTrackingAuthorization()`.
- First-launch onboarding (`OnboardingView` fullScreenCover) is **not** a gate. ATT can fire while onboarding is on screen, as soon as `ContentView` has appeared.
- Already-determined statuses skip the prompt and still init AdMob.

**If ATT is denied:** code still initializes AdMob and comments that non-personalized ads should serve. That is correct for *policy*, but **iOS 14.5+ programmatic fill is often near-zero without IDFA**, especially in small geos / new units. This remains a leading production hypothesis for “Release build, free user, device, still no ads.”

**Next step if Amplitude shows `ad_requested` + `ad_failed_to_load` error_code=1 (no fill) concentrated on ATT-denied users:** prompt ATT **after** onboarding completes (higher grant rate), and keep the current “init AdMob only after the ATT callback” ordering.

---

## 4. Test-device UDIDs / `testDeviceIdentifiers`

```swift
#if DEBUG
GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
    // "YOUR_DEVICE_HASH_HERE"
]
#endif
```

**No hashed device IDs are registered in code.** `addTestDevice(_:)` exists but is not called from `AppDelegate`.

- Empty list + DEBUG **test** interstitial IDs → Simulator/test interstitial inventory (when not on simulator-stub path).
- Empty list + DEBUG **production** banner ID → the device is a **real** requester of the live banner unit. AdMob console “test devices” do not apply unless IDs are added here or in the console.
- If the CEO later pastes a hash into this array **and** uses production units, that device gets Google test creatives, which look like “fake ads” or “I never see my real ads.”

**Next step:** after shipping iOS-F4, read `ad_requested.unit_id` in Amplitude. If DEBUG users request the production banner unit, decide (CEO) whether DEBUG should use `testBannerUnitID` like interstitial already does. Do not add device hashes until that decision.

---

## 5. SKAdNetworkItems

**Present:** yes, 64 identifiers in `AITest/Info.plist`, including Google’s `cstr6suwn9.skadnetwork`.

**Up to date vs Google’s current recommended list (developers.google.com/admob/ios/privacy/strategies, fetched 2026-08-23):** Google’s published snippet is **50** IDs ending at `3qcr597p9d.skadnetwork`. Stoqly includes that entire set **plus 14 extras** (older buyers). Missing Google IDs: **none** relative to that page.

**Not a likely cause of zero fill.** Updating the extra IDs is housekeeping, not a fix. No plist change in this ticket.

---

## 6. Facebook Audience Network / mediation

| Piece | Status |
|---|---|
| `FacebookCore` SPM | **Yes** — Meta **App Events + AEM** (install campaigns), initialized in `AppDelegate` |
| Facebook Audience Network adapter | **No** — not in Package.swift / pbxproj |
| Other GMA mediation adapters (Unity, AppLovin, etc.) | **No** |
| `GADMobileAds.start` adapter log | Will only list the Google adapter |

Facebook SKAdNetwork IDs (`v9wttpbfk9`, `n38lu8286q`) are in the plist for SKAN attribution of Meta *campaigns*, not FAN bidding.

**Waterfall is Google only.** FAN not being initialized is expected and is **not** a bug. It can still mean lower fill than a mediated stack; that is a product/AdMob-console decision, not a missing `FBAudienceNetwork` init call.

---

## 7. Decision tree — what actually mounts or hides ads

Two different flags (easy to confuse):

- `SubscriptionManager.shouldShowAds` → `!isPro && !hasRemovedAds` (**entitlement**)
- `AdManager.shouldShowAd` → one-shot **trigger** after N actions / min interval (**pacing**)

```
App launch
  └─ ATT prompt (0.8s after first UI)
       └─ initializeAfterTrackingDecision()
            ├─ Simulator → isInitialized=true, no GMA, no preload
            └─ Device → GADMobileAds.start → preloadInterstitial()
                 └─ iOS-F4: ad_requested(format=interstitial, source_screen=app_launch)

Authenticated shell (InventoryAppView)
  └─ RealAdIntegrationView wraps MainAppContent (Dashboard / Items / …)
       │
       ├─ Persistent banner?
       │    ONLY IF adManager.shouldShowAd && currentAdType == .banner
       │    Dashboard.swift / ItemListView.swift do NOT embed BannerAdView.
       │    Banner type is chosen only for itemUpdated / storageUpdated.
       │
       └─ Interstitial overlay?
            ONLY IF shouldShowAd && currentAdType == .interstitial
            Types: storageCreated, itemAdded, inventoryCountCompleted,
                   exportCompleted, barcodeScanned, bulkImportCompleted

recordCompletion(event)
  ├─ Simulator → return (never increments, never shows)
  ├─ !isInitialized → return
  └─ else completionCount++
       └─ show only if count >= 2 AND 5 minutes since lastAdShown

Entitlement
  ├─ shouldShowAds is NOT checked in recordCompletion
  ├─ shouldShowAds is NOT checked in RealAdIntegrationView
  └─ disableAds() is called when Pro / Remove Ads entitlements refresh
       (resets shouldShowAd=false, completionCount=0)
       A later recordCompletion can set shouldShowAd=true again for a Pro user
       until the next refreshPurchaseStatus(). Display gate is leaky.

Settings
  └─ shouldShowAds only gates the DEBUG “Ad Tracking Settings” row
       not the live banner.
```

**Dashboard / ItemList:** there is no always-on banner. A free user opening those tabs on a fresh session will see **zero ad UI** until they complete two paced actions **and** the chosen type is banner (edit item / edit storage) or interstitial (add item, etc.). `ADMOB_INTEGRATION.md` is stale (says every 3 actions, reward ads, banners on settings) and does not match the code.

iOS-F4 adds `noteBannerOpportunity(sourceScreen:)` on Dashboard and ItemList `onAppear`:

- Always fires `ad_requested` (with `suppressed:true` when Pro / Remove Ads)
- Does **not** mount a banner (no config change)

---

## Most likely cause (ranked)

1. **Banners are not mounted on Dashboard or ItemList.** Highest confidence (code-certain). Users looking at those screens will report “no ads” even when AdMob is healthy. Interstitials are also gated on 2 actions + 5 minutes and skipped entirely on Simulator.
   - *Next step:* CEO decides whether to add a persistent `BannerAdView` when `shouldShowAds` (product change). Do not do this until Amplitude shows `ad_requested` from those screens without matching `ad_impression`.

2. **Simulator / DEBUG stub.** Highest confidence for any “I ran it in Xcode Simulator” report. GMA is compiled out; `recordCompletion` returns immediately.
   - *Next step:* reproduce on a physical device with a **free** StoreKit sandbox account. Ignore Simulator placeholders.

3. **DEBUG banner uses the production unit ID** while interstitial uses Google test units. High confidence as a DEBUG-device fill problem.
   - *Next step:* in Amplitude, filter `format=banner` vs `interstitial` and compare `unit_id` prefixes. If CEO wants test banners in DEBUG, swap `BannerAdView` to `testBannerUnitID` when `!isLiveBuild` (config change — wait for approval).

4. **ATT denied / not determined at first ad request → no-fill.** Medium–high for Release on device. Code inits AdMob after ATT returns, which is correct; denial still starves programmatic demand.
   - *Next step:* if `ad_failed_to_load.error_code == 1` dominates for users who denied tracking, move the ATT prompt to post-onboarding and keep “init AdMob after the user responds.”

5. **Entitlement thinks the user is Pro / Remove Ads.** Medium. `isPro` defaults false (iOS-A1); `hasRemovedAds` follows Pro or the remove-ads IAP. Manual Firestore `manualProUntil` also disables ads. `ad_requested.suppressed=true` will confirm this without guessing.
   - *Next step:* Amplitude breakdown of `suppressed` and `is_pro`. If suppressed≈100% of “no ads” complaints, it is not an AdMob fill bug.

6. **Leaky display gate is the opposite problem (ads for Pro).** Low relevance to “no ads,” documented so we do not “fix” gating in this ticket.
   - *Next step:* if `ad_impression` appears with `is_pro=true` or `suppressed=true`, tighten `RealAdIntegrationView` / `recordCompletion` to honor `shouldShowAds` (separate ticket).

7. **Empty `testDeviceIdentifiers` + expecting Google test creatives on a DEBUG device using the live banner unit.** Medium for “I never see the test banner.”
   - *Next step:* only add a device hash after deciding test vs live units for DEBUG banners.

8. **No rewarded ads at all.** N/A to banners, but if someone tests “rewarded” from the outdated `ADMOB_INTEGRATION.md`, nothing will show.
   - *Next step:* ignore rewarded until a product ticket adds a unit and a loader.

9. **Missing FAN / mediation.** Low for “zero ads”; more relevant to CPM/fill optimization after Google-only fill is proven.
   - *Next step:* AdMob console mediation setup is a CEO/business decision; do not add SDKs here.

10. **SKAdNetwork / GADApplicationIdentifier missing.** Very low — both are present; identifier is production.

11. **Ads paced out.** After one interstitial/banner, `minTimeBetweenAds = 300s`. Users tapping around for a minute will not see another.
    - *Next step:* `ad_requested` timestamps in Amplitude; if requests themselves are missing, pacing or mount logic is the cause, not fill.

---

## How iOS-F4 proves this in production (no config change)

| Hypothesis | Amplitude signature (48h) |
|---|---|
| Screens never request a banner | `ad_requested` from Dashboard/ItemList with no later `ad_impression` |
| Entitlement gated | `ad_requested.suppressed=true` |
| No fill / ATT | `ad_failed_to_load` with `error_code=1` (and ATT status from device logs / future `permission_result`) |
| Network | `error_code=2` or `is_offline=true` |
| Load works, UI hidden | `ad_loaded` without `ad_impression` |
| Click path healthy | `ad_impression` → `ad_clicked` |

**No production AdMob unit, ATT timing, test-device list, SKAdNetwork, or mediation changes were made in iOS-F4.**
