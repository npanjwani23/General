# Latch

A personal app blocker for iPhone. Tap a paired NFC sticker to lock the apps and sites you chose. The only way back in is to tap the sticker again, or burn one of 5 lifetime emergency unlocks.

Everything runs on the phone. No server, no account, no network calls.

## What you need

- Apple Developer Program membership ($99/yr). Free Apple IDs cannot sign Family Controls or NFC.
- Mac with Xcode 15 or newer.
- iPhone on iOS 16 or newer. The simulator cannot do NFC or app blocking.
- NTAG215 or NTAG213 NFC stickers. Use on-metal tags if the sticker goes on a metal surface.

## Build and install

```sh
brew install xcodegen
cd Latch
xcodegen
open Latch.xcodeproj
```

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your 10-character team ID, then rerun `xcodegen`. It applies to both targets: the app (`Latch`) and the schedule extension (`LatchMonitor`).
2. If Apple says a bundle ID is taken, change both `PRODUCT_BUNDLE_IDENTIFIER`s in `project.yml` (keep the extension's as the app's plus `.monitor`), and change the app group `group.app.latch.personal` in both `.entitlements` files and in `Shared/SharedStore.swift` to match.
3. In Xcode, Signing & Capabilities should show Family Controls, NFC Tag Reading and App Groups on the app, and Family Controls plus App Groups on `LatchMonitor`. Automatic signing creates the app group the first time.
4. Plug in the iPhone, turn on Developer Mode (Settings, Privacy & Security), select it as the run destination, and press Run.

Installs from Xcode last one year, then need a reinstall.

### Simulator

`xcodebuild ... CODE_SIGNING_ALLOWED=NO` builds for the simulator. It runs the UI, but Screen Time access, app blocking and schedules only work on a signed device build, and an unsigned build cannot keep paired tags across launches (no Keychain access). A fake tag (`04A1B2C3D4E5F6`) stands in for NFC scans.

## First run

Settings opens on its own the first time:

1. Allow Screen Time access.
2. Choose the apps, categories and sites to block (this fills your first mode).
3. Pair a sticker.

Then tap the bottom button and hold the phone to the sticker to lock.

## Using it

- **Lock:** tap the button and scan your tag, or press and hold the button for 3 seconds to lock without the tag.
- **Unlock:** tag only (or one of 5 lifetime emergency unlocks). Easy to start, strict to stop.
- **Modes:** up to 10 named block lists (Deep Work, No Social…). The active mode is what a tap or hold locks. Modes can't be edited, switched or deleted while locked.
- **Schedules:** Settings, Schedules. Lock a mode between two times on chosen days, including overnight (overnight windows must start by 11:30 PM and end at 12:15 AM or later). A schedule unlocks when its window ends, but only if it started that lock. Unlocking early with your tag ends that window; it does not lock again until the next one.
- **Time locked:** tap the "today" pill for today, the last 7 days and the daily average.

## How it holds

- Blocks are enforced by iOS (ManagedSettings), so they survive force-quitting Latch and rebooting.
- While locked, iOS refuses to delete apps, so Latch cannot be removed to escape.
- Tags, modes and schedules can only be changed while unlocked. Settings is hidden while locked.
- The emergency counter and paired tags are stored in the Keychain, so reinstalling does not reset them.
- Schedules run in a separate Screen Time extension that iOS wakes at each window edge, so they work with Latch closed.
- Known hole: Screen Time access for Latch can be switched off in iOS Settings. For hard mode, have someone else set your Screen Time passcode.

## Layout

```
project.yml                      XcodeGen project spec (app + LatchMonitor extension)
Latch/
  LatchApp.swift                 App entry, light/dark flip on lock
  Models/AppState.swift          Lock, modes, schedules, tags, stats
  Services/ScreenTimeService     Screen Time permission
  Services/ScheduleRegistrar     Registers schedule windows with iOS
  Services/NFCService            Tag scanning (CoreNFC; fake tag in simulator)
  Services/TagStore              Paired tags and emergency counter (Keychain)
  Support/Haptics                Lock, unlock and error haptics
  Views/HomeView                 The one screen: timer, mode, button
  Views/LockControl              Tap-or-hold button
  Views/ModesView                Modes list and editor
  Views/SchedulesView            Schedules list and editor
  Views/SetupView                Settings and first-run checklist
  Views/StatsView                Time locked today and this week
Shared/                          Compiled into the app and the extension
  Mode, Schedule, LockLog        Models and lock history
  SharedStore                    App-group storage and lock state
  Shields                        Applies and clears the iOS shields
  ScheduleEngine                 What happens when a window opens or closes
LatchMonitor/
  LatchMonitor.swift             DeviceActivity extension, hands off to ScheduleEngine
```
