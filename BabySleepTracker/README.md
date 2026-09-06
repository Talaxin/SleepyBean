# SleepyBean

Native iOS baby tracker for sleep and feeding. Built with SwiftUI and SwiftData.

## Features

- One-tap nap and awake timers with live lock screen updates
- Daytime and nighttime tracking modes
- Wake window guidance by age
- Feeding log with last side (left, right, or bottle)
- Today's timeline, daily stats, and 7-day history
- Multiple baby profiles
- iCloud sync across your devices (Xcode + developer account)
- Partner sharing — invite a spouse to edit the same baby
- On-device storage for sideload installs — no account required

## Install with Feather

Add this source in Feather → **Sources** → **Add Source**:

```
https://raw.githubusercontent.com/Talaxin/SleepyBean/main/feather/app-repo.json
```

Pushes to `main` publish a new release IPA and update the manifest automatically.

Feather builds are local-only. iCloud sync and partner sharing require building from Xcode with a paid Apple Developer account.

## Requirements

- Xcode 16+
- iOS 17+
- iPhone or iPad

## Getting Started (Xcode + Developer Account)

1. Open `BabySleepTracker/BabySleepTracker.xcodeproj` in Xcode
2. Select your development team in **Signing & Capabilities**
3. Enable **iCloud** capability with **CloudKit** and container `iCloud.com.sleepybean.loveyourbaby`
4. Enable **Background Modes** → **Remote notifications** (for CloudKit sync)
5. Build and run on your device (⌘R)

On first launch with iCloud signed in, sleep and feeding data syncs automatically across your devices.

### Partner sharing

1. Open **Settings** → **Family Sharing**
2. Tap **Share with partner**
3. Invite your partner by email or link
4. They accept the invite and see the same baby profile, naps, and feeds

Both people can log and edit data in real time. Each person needs SleepyBean installed from Xcode (or App Store when published) with their own Apple ID.

## How to Use

1. **First launch** — Enter baby's name and birth date
2. **Daytime** — Big button tracks naps; small button switches to nighttime mode
3. **Nighttime** — Big button tracks awake periods
4. **Feeding** — Tap Left, Right, or Bottle to log a feed
5. **History** — Review sleep patterns over the past week

## Privacy

- **Feather/sideload builds:** Data stays on your device. Optional JSON backup to iCloud Drive.
- **Xcode builds:** Data syncs to your private iCloud via CloudKit. Partner sharing uses Apple's CloudKit sharing — only invited people can access the shared baby.

## License

MIT
