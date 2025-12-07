# Bundle IDs for Intent App

This document lists all bundle IDs that need to be registered in the Apple Developer Portal for Xcode Cloud to work.

## Bundle IDs to Register

### 1. Main Application
- **Bundle ID**: `oh.Intent`
- **Name**: Intent
- **Description**: Mindful phone usage app
- **Capabilities Required**:
  - Family Controls
  - App Groups (`group.oh.Intent`)

### 2. Widget Extension
- **Bundle ID**: `oh.Intent.IntentWidget`
- **Name**: Intent Widget
- **Description**: Intent widget extension
- **Capabilities Required**:
  - App Groups (`group.oh.Intent`)

### 3. Shield Configuration Extension
- **Bundle ID**: `oh.Intent.IntentShieldConfiguration`
- **Name**: Intent Shield Configuration
- **Description**: Shield configuration extension for blocking apps
- **Capabilities Required**:
  - Family Controls
  - App Groups (`group.oh.Intent`)

### 4. Shield Action Extension
- **Bundle ID**: `oh.Intent.IntentShieldAction`
- **Name**: Intent Shield Action
- **Description**: Shield action extension for app blocking UI
- **Capabilities Required**:
  - Family Controls
  - App Groups (`group.oh.Intent`)

### 5. Device Activity Monitor Extension
- **Bundle ID**: `oh.Intent.IntentDeviceActivityMonitor`
- **Name**: Intent Device Activity Monitor
- **Description**: Device activity monitor extension
- **Capabilities Required**:
  - Family Controls
  - App Groups (`group.oh.Intent`)

## App Group

Make sure this App Group is also registered:
- **Identifier**: `group.oh.Intent`
- **Description**: Shared data for Intent app and extensions

## Steps to Register

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Click the **+** button to add a new identifier
3. Select **App IDs** and click **Continue**
4. Select **App** and click **Continue**
5. Enter the Bundle ID and Description
6. Select the required Capabilities
7. Click **Continue** and then **Register**
8. Repeat for all 5 bundle IDs above

## After Registration

Once all bundle IDs are registered:
1. Revoke any "Distribution Managed (Xcode Cloud)" certificates
2. Push a new commit to trigger Xcode Cloud
3. Xcode Cloud will generate new provisioning profiles for all bundle IDs
