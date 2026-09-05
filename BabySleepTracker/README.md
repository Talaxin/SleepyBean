# SleepyBean — Baby Sleep Tracker

A native iOS app for tracking baby naps and night sleep, inspired by the UX patterns of **Nara Baby** and **Huckleberry**.

## What top apps do (and what we built)

| Feature | Nara Baby | Huckleberry | SleepyBean |
|---------|-----------|-------------|------------|
| One-tap start/stop sleep timer | ✅ | ✅ | ✅ |
| Live elapsed timer while sleeping | ✅ | ✅ | ✅ |
| Today's activity timeline | ✅ | ✅ | ✅ |
| Daily sleep totals | ✅ | ✅ | ✅ |
| Manual add/edit past entries | ✅ | ✅ | ✅ |
| Wake window / nap readiness | Basic | SweetSpot® (paid) | ✅ (free, age-based) |
| 7-day sleep chart | ✅ | ✅ (paid reports) | ✅ |
| Multiple baby profiles | ✅ | ✅ | ✅ |
| Account / cloud sync | ✅ | ✅ | Local only (privacy-first) |

## Requirements

- Xcode 16+
- iOS 17+ (SwiftData)
- iPhone or iPad

## Getting Started

1. Open `BabySleepTracker/BabySleepTracker.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on your device or simulator (⌘R)

## App Structure

```
BabySleepTracker/
├── BabySleepTrackerApp.swift    # App entry + SwiftData container
├── ContentView.swift            # Tab navigation
├── Models/
│   ├── BabyProfile.swift        # Baby name, birth date, age
│   └── SleepSession.swift       # Sleep sessions (nap/night)
├── Services/
│   ├── SleepFormatter.swift     # Duration/time formatting
│   └── WakeWindowCalculator.swift  # Age-based nap readiness
└── Views/
    ├── HomeView.swift           # Main timer + today's log
    ├── SleepTimerButton.swift   # Big start/stop button
    ├── WakeWindowCard.swift     # Nap readiness indicator
    ├── HistoryView.swift        # 7-day chart + past days
    ├── AddSleepView.swift       # Manual entry / edit
    └── SettingsView.swift       # Baby profile settings
```

## How to Use

1. **First launch** — Enter baby's name and birth date
2. **Start sleep** — Tap the big moon button, choose Nap or Night
3. **Wake up** — Tap again to stop the timer
4. **Missed a log?** — Tap + to manually add a past sleep session
5. **Check patterns** — History tab shows 7-day chart and daily breakdown
6. **Nap timing** — Wake window card shows when baby may be ready for next nap

## Tech Stack

- **SwiftUI** — Modern declarative UI
- **SwiftData** — On-device persistence (no account required)
- **iOS 17+** — Live Activities ready architecture

## Privacy

All data is stored locally on your device using SwiftData. No accounts, no cloud, no tracking.

## License

MIT
