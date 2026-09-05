# SleepyBean

Native iOS baby sleep tracker (SwiftUI + SwiftData). Track naps and night sleep with one tap.

## Download the IPA

1. Open [Actions](../../actions/workflows/build-ipa.yml) in this repo
2. Run **Build SleepyBean IPA** (or push to `main`)
3. Download **SleepyBean-ipa** from the workflow run artifacts

## Local development

Open `BabySleepTracker/BabySleepTracker.xcodeproj` in Xcode 16+ (iOS 17+).

```bash
cd BabySleepTracker
bash scripts/build-unsigned-ipa.sh
# → build/SleepyBean.ipa
```

See [BabySleepTracker/README.md](BabySleepTracker/README.md) for full app details.
