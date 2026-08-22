#!/bin/sh
#
# Xcode Cloud — runs right before xcodebuild.
# Release-safety guards + build-number stamp. A failing guard aborts the build,
# so a bad build can never reach TestFlight / the App Store.
#
set -e

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO"

echo "── Release guards ──────────────────────────────"

# Guard 1: never ship with isPro hardcoded true (the #1 pre-ship rule).
# Matches the DECLARATION 'var isPro = true' only — runtime assignments are fine.
if grep -REn "var[[:space:]]+isPro[[:space:]]*=[[:space:]]*true" AITest/Models/SubscriptionManager.swift; then
	echo "❌ RELEASE BLOCKED: isPro is hardcoded to true. Revert to false before shipping."
	exit 1
fi
echo "✓ isPro is not hardcoded true"

# Guard 2: no free-trial language in SHIPPED user-facing text (the String Catalog).
# Only fails on affirmative trial wording, not "no free trial" comments in code.
if command -v python3 >/dev/null 2>&1 && [ -f AITest/Localizable.xcstrings ]; then
	TRIAL=$(python3 - <<'PY'
import json, re
d = json.load(open("AITest/Localizable.xcstrings", encoding="utf-8"))
bad = []
for k, e in d.get("strings", {}).items():
    s = e.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value") or k
    low = s.lower()
    if "trial" in low and not re.search(r"\bno\b|\bnot\b|\bnever\b|does not|without", low):
        bad.append(s)
print(len(bad))
for b in bad[:10]:
    print("   ", b)
PY
)
	COUNT=$(echo "$TRIAL" | head -1)
	if [ "${COUNT:-0}" -gt 0 ]; then
		echo "❌ RELEASE BLOCKED: user-facing 'trial' wording in catalog — Stoqly has no trial."
		echo "$TRIAL" | tail -n +2
		exit 1
	fi
	echo "✓ no free-trial wording in shipped strings"
fi

# Guard 3: every UI label literal is in the String Catalog (structural localization gate).
if command -v python3 >/dev/null 2>&1 && [ -f AITest/Localization/catalog_gap_check.py ]; then
	MISSING=$(python3 AITest/Localization/catalog_gap_check.py 2>/dev/null | grep -oE "MISSING from catalog: [0-9]+" | grep -oE "[0-9]+$" || echo 0)
	if [ "${MISSING:-0}" -gt 0 ]; then
		echo "❌ RELEASE BLOCKED: $MISSING UI strings are missing from the catalog."
		python3 AITest/Localization/catalog_gap_check.py || true
		exit 1
	fi
	echo "✓ localization catalog gate: 0 missing"
fi

# Stamp the build number from Xcode Cloud so uploads never collide.
if [ -n "$CI_BUILD_NUMBER" ] && [ -f AITest/Info.plist ]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" AITest/Info.plist 2>/dev/null \
		|| /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $CI_BUILD_NUMBER" AITest/Info.plist 2>/dev/null || true
	echo "✓ build number set to $CI_BUILD_NUMBER"
fi

echo "✅ All release guards passed."
