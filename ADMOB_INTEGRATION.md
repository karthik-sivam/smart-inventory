# Google AdMob Integration Guide

## Overview
This project has been integrated with Google AdMob to display real advertisements instead of mock ads.

## Configuration

### Ad Unit IDs
The app currently uses **test ad unit IDs** for development:

- **Banner Ads**: `ca-app-pub-3940256099942544/2934735716`
- **Interstitial Ads**: `ca-app-pub-3940256099942544/4411468910`
- **Reward Ads**: `ca-app-pub-3940256099942544/1712485313`
- **App ID**: `ca-app-pub-3940256099942544~1458002511`

### Production Setup
To use real ads in production:

1. **Create AdMob Account**: Sign up at [admob.google.com](https://admob.google.com)
2. **Create App**: Add your app to AdMob console
3. **Create Ad Units**: Create banner, interstitial, and reward ad units
4. **Replace Test IDs**: Update the ad unit IDs in `AdManager.swift`

## Features

### Ad Types
- **Banner Ads**: Displayed at bottom of screen
- **Interstitial Ads**: Full-screen ads shown after actions
- **Reward Ads**: Video ads that unlock premium features

### Smart Ad Triggers
- **Frequency Control**: Shows ads every 3 completed actions
- **Time Limits**: Minimum 5 minutes between ads
- **Context-Aware**: Different ad types for different actions

### Ad Events
- `storageCreated` → Interstitial Ad
- `itemAdded` → Interstitial Ad
- `inventoryCountCompleted` → Reward Ad
- `settingsChanged` → Banner Ad
- `itemUpdated` → Banner Ad
- `storageUpdated` → Banner Ad

## Testing

### Debug Mode
Use the test buttons in Settings to manually trigger ads:
- Test Interstitial Ad
- Test Banner Ad
- Test Reward Ad

### Test Devices
Add your device ID to test ads:
```swift
// Add to AdManager initialization
GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = ["YOUR_DEVICE_ID"]
```

## Privacy & Compliance

### Required Permissions
- **User Tracking**: Added `NSUserTrackingUsageDescription` for personalized ads
- **App Tracking Transparency**: Implemented for iOS 14.5+

### GDPR Compliance
- Users can opt out of personalized ads
- AdMob handles GDPR compliance automatically

## Troubleshooting

### Common Issues
1. **Ads Not Loading**: Check internet connection and ad unit IDs
2. **Test Ads Not Showing**: Ensure using test ad unit IDs
3. **Build Errors**: Verify GoogleMobileAds package is properly linked

### Debug Logs
Check console for AdMob debug messages:
- "AdMob initialized successfully"
- "Interstitial ad failed to load: [error]"
- "Ad dismissed"

## Revenue Optimization

### Best Practices
1. **Ad Placement**: Strategic placement without disrupting UX
2. **Frequency Capping**: Prevent ad fatigue
3. **User Experience**: Balance monetization with user satisfaction
4. **A/B Testing**: Test different ad placements and frequencies

### Performance Metrics
Monitor in AdMob Console:
- Fill Rate
- Click-Through Rate (CTR)
- Revenue per User (RPU)
- User Engagement

## Support
- [AdMob Documentation](https://developers.google.com/admob/ios/quick-start)
- [AdMob Help Center](https://support.google.com/admob/)
- [Google Mobile Ads SDK](https://github.com/googleads/swift-package-manager-google-mobile-ads) 