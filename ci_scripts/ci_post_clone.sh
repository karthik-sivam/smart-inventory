#!/bin/sh
#
# Xcode Cloud — runs right after the repo is cloned.
# Rebuilds the two gitignored secret files from Xcode Cloud environment variables
# so the build has the API keys + Firebase config it needs.
#
# Set these in App Store Connect → your app → Xcode Cloud → Workflow →
# Environment (mark every one as "Secret"):
#   ANTHROPIC_API_KEY, SARVAM_API_KEY, AMPLITUDE_API_KEY
#   GOOGLE_SERVICE_INFO_PLIST_BASE64   (base64 of AITest/GoogleService-Info.plist)
#
set -e

# Xcode Cloud checks the repo out at $CI_PRIMARY_REPOSITORY_PATH
REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO"

echo "→ Reconstructing AITest/Secrets.plist"
cat > AITest/Secrets.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ANTHROPIC_API_KEY</key><string>${ANTHROPIC_API_KEY}</string>
	<key>SARVAM_API_KEY</key><string>${SARVAM_API_KEY}</string>
	<key>AMPLITUDE_API_KEY</key><string>${AMPLITUDE_API_KEY}</string>
</dict>
</plist>
PLIST

if [ -n "$GOOGLE_SERVICE_INFO_PLIST_BASE64" ]; then
	echo "→ Reconstructing AITest/GoogleService-Info.plist"
	echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > AITest/GoogleService-Info.plist
else
	echo "⚠️  GOOGLE_SERVICE_INFO_PLIST_BASE64 not set — Firebase config missing."
fi

# Sanity: keys present (do not print values)
if [ -z "$ANTHROPIC_API_KEY" ]; then echo "⚠️  ANTHROPIC_API_KEY is empty"; fi
if [ -z "$SARVAM_API_KEY" ]; then echo "⚠️  SARVAM_API_KEY is empty"; fi

echo "✅ Secrets reconstructed."
