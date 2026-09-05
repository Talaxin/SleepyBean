# SleepyBean

Native iOS baby tracker for sleep and feeding. Built with SwiftUI and SwiftData.

## Features

- One-tap nap and awake timers with live lock screen updates
- Daytime and nighttime tracking modes
- Wake window guidance by age
- Feeding log with last side (left, right, or bottle)
- Today's timeline, daily stats, and 7-day history
- Multiple baby profiles
- On-device storage — no account required

## Install with Feather

Add this source in Feather → **Sources** → **Add Source**:

```
https://raw.githubusercontent.com/Talaxin/SleepyBean/main/feather/app-repo.json
```

Pushes to `main` publish a new release IPA and update the manifest automatically.

## Requirements

- Xcode 16+
- iOS 17+
- iPhone or iPad

## Getting Started

1. Open `BabySleepTracker/BabySleepTracker.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on your device or simulator (⌘R)

## How to Use

1. **First launch** — Enter baby's name and birth date
2. **Daytime** — Big button tracks naps; small button switches to nighttime mode
3. **Nighttime** — Big button tracks awake periods
4. **Feeding** — Tap Left, Right, or Bottle to log a feed
5. **History** — Review sleep patterns over the past week

## Privacy

All data is stored locally on your device. No accounts, no cloud, no tracking.

## License

MIT
