# Smart Inventory — Xcode Setup Guide

Complete step-by-step guide to configure Xcode before building and submitting to the App Store.
Do these steps in order. Each section is self-contained.

---

## Step 1 — Add Firebase Packages (Firestore + Crashlytics)

Your project already has `firebase-ios-sdk` as a Swift Package. You just need to link the extra targets.

1. In Xcode, select your **AITest target** (click "AITest" in the project navigator, then select the AITest target in the editor)
2. Go to **Build Phases** → **Link Binary With Libraries** → press **+**
3. Add these frameworks (search by name):
   - `FirebaseFirestore`
   - `FirebaseCrashlytics`
   - `FirebaseAnalytics`

> **Tip:** If you don't see them, go to **File → Add Package Dependencies** and make sure `firebase-ios-sdk` is already listed.

---

## Step 2 — Info.plist Keys (CRITICAL)

Xcode 15+ manages Info.plist through the Target's **Info** tab rather than a file.

1. Select the **AITest target** → **Info** tab
2. Under **Custom iOS Target Properties**, add these keys:

| Key | Type | Value |
|-----|------|-------|
| `GADApplicationIdentifier` | String | `ca-app-pub-9489340523484530~5027045442` |
| `NSUserTrackingUsageDescription` | String | `Smart Inventory uses your advertising ID to show you relevant ads that support the free version of this app.` |
| `NSCameraUsageDescription` | String | `Smart Inventory uses your camera to scan product barcodes for quick inventory entry.` |
| `SKAdNetworkItems` | Array | *(see sub-step below)* |

**Adding SKAdNetworkItems (required for AdMob iOS 14+):**

Add an Array key `SKAdNetworkItems` with one Dictionary item containing:
- `SKAdNetworkIdentifier` = `cstr6suwn9.skadnetwork`
- Also add Google's full list from: https://developers.google.com/admob/ios/privacy

> **Why:** Apple requires `SKAdNetworkItems` for AdMob to correctly attribute installs without tracking data.

---

## Step 3 — Crashlytics Run Script Build Phase

Firebase Crashlytics requires a build script to upload dSYM files for readable crash reports.

1. Select **AITest target** → **Build Phases**
2. Press **+** → **New Run Script Phase**
3. Drag the new phase **below** "Link Binary With Libraries"
4. Paste this script:

```bash
"${BUILD_DIR%Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
```

5. Under **Input Files**, add:
```
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)
```

6. Name the phase: `Firebase Crashlytics`

> **Why:** Without this, crash logs on App Store Connect will show memory addresses instead of file names and line numbers.

---

## Step 4 — In-App Purchase Capability

1. Select **AITest target** → **Signing & Capabilities**
2. Press **+** → search for **In-App Purchase** → Add it

---

## Step 5 — Push Notifications Capability (Phase 2)

Skip this for v1. Add before enabling FCM low-stock alerts:

1. **Signing & Capabilities** → **+** → **Push Notifications**
2. **+** → **Background Modes** → check **Remote notifications**

---

## Step 6 — StoreKit Configuration (Local Testing)

To test subscriptions without waiting for App Store Connect approval:

1. **File → New File → StoreKit Configuration File** → name it `SmartInventory.storekit`
2. Add these products:

**Subscriptions:**
- Group: `Smart Inventory Pro`
  - `com.shambhavi.smartinventory.pro.monthly` — $4.99/month
  - `com.shambhavi.smartinventory.pro.annual` — $39.99/year

**Non-Consumables:**
- `com.shambhavi.smartinventory.removeads` — $2.99

3. Enable it: **Scheme** → **Edit Scheme** → **Run** → **Options** → **StoreKit Configuration** → select `SmartInventory.storekit`

---

## Step 7 — Firestore Security Rules

Go to [Firebase Console](https://console.firebase.google.com) → **Firestore Database** → **Rules** and paste:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Then click **Publish**.

> **IMPORTANT:** Without these rules, your Firestore database is wide open. Do this before any real users sign up.

---

## Step 8 — Enable Firestore in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com) → **first-own-ios-app**
2. Left sidebar → **Firestore Database** → **Create database**
3. Choose **Start in production mode** (rules from Step 7 cover security)
4. Select your region (choose closest to your target market — e.g., `us-central1` for US/global)
5. Click **Enable**

---

## Step 9 — App Store Connect Setup

### Create In-App Purchases:
1. [App Store Connect](https://appstoreconnect.apple.com) → **Your App** → **Monetisation** → **Subscriptions**
2. Create Subscription Group: `Smart Inventory Pro`
3. Add products matching Step 6 above
4. **In-App Purchases** → Add `com.shambhavi.smartinventory.removeads` (Non-Consumable, $2.99)

### Privacy Nutrition Labels:
Go to **App Privacy** section and declare:
- **Advertising Data** → Used to Track: YES (if personalized ads enabled)
- **Identifiers** → Device ID: Used to Track
- Leave everything else unchecked (you don't collect health, financial, location data)

### Host your Privacy Policy:
Upload `privacy.html` to any public URL (GitHub Pages is free and easy):
1. Create a GitHub repo → upload `privacy.html` → enable GitHub Pages
2. Use that URL in App Store Connect → **App Information** → **Privacy Policy URL**

---

## Step 10 — AdMob Test Device Setup

When you build to a real device for the first time:

1. Run the app on your physical iPhone
2. In Xcode console, look for a log line like:
   ```
   To get test ads on this device, call: GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ "ABC123..." ]
   ```
3. Copy that device ID hash
4. In `AdManager.swift` → `initializeAfterTrackingDecision()` → add it:
   ```swift
   GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
       GADSimulatorID,
       "YOUR_DEVICE_HASH_HERE"   // ← paste here
   ]
   ```

This prevents your real AdMob account from being flagged for invalid traffic during development.

---

## Step 11 — Firebase Analytics (Enable)

Analytics is currently disabled in `GoogleService-Info.plist`. To enable:

1. Open `GoogleService-Info.plist`
2. Change `IS_ANALYTICS_ENABLED` from `false` to `true`
3. In Firebase Console → **Analytics** → enable it for your project

Then add these key events in your views (optional — basic pageview tracking works automatically):
```swift
Analytics.logEvent("item_created", parameters: ["storage": storageName])
Analytics.logEvent("inventory_counted", parameters: ["variance": variance])
Analytics.logEvent("export_completed", parameters: ["format": "csv"])
```

---

## Step 12 — App Name Change (Recommended)

The Xcode project is named `AITest` which is a placeholder. Before App Store submission:

1. Select **AITest target** → **General** → **Display Name**: change to `Smart Inventory`
2. Select the **Project** (top of navigator) → rename from `AITest` to `SmartInventory`
   - Right-click → Rename
3. The bundle ID `com.shambhavi.smartinventory` is already correct ✓

---

## Pre-Submission Checklist

- [ ] Step 1: Firebase frameworks linked (Firestore, Crashlytics, Analytics)
- [ ] Step 2: All Info.plist keys added (GAD, ATT, Camera)
- [ ] Step 3: Crashlytics Run Script added
- [ ] Step 4: In-App Purchase capability added
- [ ] Step 5: Firestore security rules published
- [ ] Step 6: Firestore database created in Firebase Console
- [ ] Step 7: In-App Purchase products created in App Store Connect
- [ ] Step 8: Privacy Nutrition Labels filled in App Store Connect
- [ ] Step 9: Privacy Policy URL set (hosted publicly)
- [ ] Step 10: App icons for all sizes (1024x1024 for App Store)
- [ ] Step 11: App Store screenshots (6.7", 6.1" required; iPad optional)
- [ ] Step 12: TestFlight — distribute to 5-10 testers before submission
- [ ] Step 13: App Store description and keywords written
- [ ] Step 14: Age Rating selected (4+)
- [ ] Step 15: Support URL set

---

## Version Control — .gitignore Additions

Add these to your `.gitignore` to keep sensitive files out of source control:

```gitignore
# Firebase (contains API keys — use environment variables in CI)
GoogleService-Info.plist

# Xcode
*.xcuserstate
DerivedData/
*.xcworkspace/xcuserdata/
*.xccheckout
xcuserdata/

# CocoaPods / SPM caches
.build/
Pods/

# macOS
.DS_Store
**/.DS_Store

# StoreKit local config (may contain test purchase state)
*.storekit
```

> **Note:** After adding `GoogleService-Info.plist` to `.gitignore`, use Xcode Cloud secrets or GitHub Actions secrets to inject it during CI builds.

---

## Questions?

If you get stuck on any step, describe the error message and which step you're on. Common issues:

- **"No such module 'FirebaseFirestore'"** → Step 1 not done (link the framework)
- **Crashlytics crash logs unreadable** → Step 3 script not added, or archive dSYMs not uploaded
- **AdMob shows no ads** → Step 2 (`GADApplicationIdentifier`) missing from Info.plist
- **ATT alert not showing** → `NSUserTrackingUsageDescription` missing from Info.plist
- **StoreKit purchase fails** → Products not created in App Store Connect (Step 9) or scheme config not set (Step 6)
