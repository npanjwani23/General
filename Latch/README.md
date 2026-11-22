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

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your 10-character team ID, then rerun `xcodegen`. (Or pick the team in Xcode under Signing & Capabilities.)
2. If Apple says the bundle ID is taken, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
3. Plug in the iPhone, turn on Developer Mode (Settings, Privacy & Security), select it as the run destination, and press Run.

Installs from Xcode last one year, then need a reinstall.

## First run

1. Allow Screen Time access.
2. Choose the apps, categories, and sites to block.
3. Pair a sticker.
4. Tap the big button and hold the phone to the sticker to lock.

## How it holds

- Blocks are enforced by iOS (ManagedSettings), so they survive force-quitting Latch and rebooting.
- While locked, iOS refuses to delete apps, so Latch cannot be removed to escape.
- Tags can only be paired or removed while unlocked.
- The emergency counter is stored in the Keychain, so reinstalling does not reset it.
- Known hole: Screen Time access for Latch can be switched off in iOS Settings. For hard mode, have someone else set your Screen Time passcode.

## Layout

```
project.yml                    XcodeGen project spec
Latch/
  LatchApp.swift               App entry
  Models/AppState.swift        Lock state, setup state, persistence
  Services/ScreenTimeService   Authorization and shields
  Services/NFCService          Tag scanning (CoreNFC)
  Services/TagStore            Paired tags and emergency counter (Keychain)
  Views/HomeView               Lock button and setup
  Views/TagsView               Pair and remove tags
```
