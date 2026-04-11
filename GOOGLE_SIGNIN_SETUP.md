# Google Sign-In Setup Guide

## Prerequisites

1. **Firebase Project**: Ensure you have a Firebase project with Google Sign-In enabled
2. **GoogleService-Info.plist**: Make sure this file is added to your Xcode project
3. **Google Sign-In SDK**: The GoogleSignIn package should be added to your project

## Configuration Steps

### 1. Add Google Sign-In Package

If not already added, add the Google Sign-In Swift Package to your Xcode project:

1. In Xcode, go to **File** → **Add Package Dependencies**
2. Enter the URL: `https://github.com/google/GoogleSignIn-iOS`
3. Select the latest version and add it to your target

### 2. Configure URL Schemes

You need to add the Google Sign-In URL scheme to your app's URL schemes:

1. In Xcode, select your project in the navigator
2. Select your app target
3. Go to **Info** tab
4. Expand **URL Types** (if it doesn't exist, click the + button to add it)
5. Add a new URL Type with:
   - **Identifier**: `REVERSED_CLIENT_ID` (get this from GoogleService-Info.plist)
   - **URL Schemes**: The value of `REVERSED_CLIENT_ID` from GoogleService-Info.plist
   - **Role**: Editor

### 3. Get REVERSED_CLIENT_ID

1. Open your `GoogleService-Info.plist` file
2. Find the `REVERSED_CLIENT_ID` key
3. Copy its value (it looks like: `com.googleusercontent.apps.YOUR_CLIENT_ID`)

### 4. Add URL Scheme to Build Settings

Since this project doesn't use Info.plist, add the URL scheme to build settings:

1. In Xcode, select your project
2. Go to **Build Settings**
3. Search for "URL Types"
4. Add the URL scheme configuration

### 5. Alternative: Create Info.plist

If you prefer to use Info.plist, create one in your project root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>REVERSED_CLIENT_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>YOUR_REVERSED_CLIENT_ID_HERE</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

## Testing

1. **Simulator**: Google Sign-In will show an error in simulator - this is expected
2. **Real Device**: Test on a real device with a Google account
3. **Debug**: Check console logs for any configuration errors

## Troubleshooting

### Common Issues:

1. **"No valid 'aps-environment' entitlement string found"**
   - This is normal for development builds
   - Will work fine on real devices

2. **"Google Sign-In configuration error"**
   - Check that GoogleService-Info.plist is properly added
   - Verify CLIENT_ID and REVERSED_CLIENT_ID are correct

3. **"URL scheme not found"**
   - Ensure URL scheme is properly configured
   - Check that REVERSED_CLIENT_ID matches your Firebase project

### Debug Steps:

1. Check console logs for configuration messages
2. Verify GoogleService-Info.plist is in the app bundle
3. Test on real device (not simulator)
4. Ensure Firebase project has Google Sign-In enabled

## Security Notes

- Never commit GoogleService-Info.plist to public repositories
- Use different Firebase projects for development and production
- Regularly rotate your Firebase project keys 