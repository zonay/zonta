# Audio Ducking and Consolidated Settings Tab — Design

**Date:** 2026-11-19
**Status:** Approved

## Intent

Optionally dip the Mac's system audio while Zonta is recording, so music does not bleed into the microphone, and gather the everyday switches into one tab instead of scattering them.

## Goals

- A ~250 ms eased fade-down when a recording actually starts, and an eased return to the exact original volume on release or cancel.
- The fade is optional and defaults off.
- Rename "Shortcuts" to "Settings"; that tab holds the three key pickers plus speech on/off, cleanup on/off and the new ducking toggle.
- The server and prompt fields stay in their existing tabs.

## Non-goals

- Per-app audio or the Process Tap API.
- Arbitrary shortcut recording.
- A separate preferences window.
- Changing what Chat, Dictate or Translate do.

## Constraints

- Keep bundle ID `com.zafer.zonta` and signing team `TP7C938GZF`; no new TCC prompts.
- The ducking toggle lives outside the `Settings` blob, like `SpeechOutput` and `CleanupOutput`, so flipping it cannot drop the chat session.
- Fade uses the default output device's main volume; a ~250 ms ramp in 10 steps of 25 ms.
- Restore must also run on error and when a rebind ends an active hold.
- No third-party dependencies; plain `swiftc` build via `./build.sh`.

## Approaches

- **CoreAudio master-volume ramp (chosen).** Read and write the default output device volume with `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData` and ease it in steps. Reliable across apps and devices.
- **AppleScript `set volume`.** Ruled out: slow, needs scripting permission, and cannot fade.
- **Per-app volume / Process Tap.** Ruled out by the user.
- **Settings tab rename (chosen)** over a separate preferences window, which would cost more for no gain.

## Decided design

- New `Zonta/AudioDucker.swift`: `@MainActor`, injectable `readVolume` / `writeVolume` closures for testability, `duck()`, `restore()`, `isDucked`. `duck()` captures the current level and ramps to 0; `restore()` ramps from the current level back to the captured value. Both are idempotent and cancellation-safe.
- `Settings.swift`: `AudioDuckOutput.enabled`, default `false`, key `audio.duck.v1`.
- `ZontaApp.swift`: duck after `recorder.start()` succeeds in `begin(_:)`; restore in `end()`, `cancel()` and `handleError`; restore immediately if the toggle is switched off mid-duck.
- `SettingsView.swift`: tab renamed to "Settings"; move the speech and cleanup toggles into it, add the ducking toggle, keep the dynamic hotkey summary in the header.
- `build.sh`: link `CoreAudio` and `AudioToolbox`.

```
Settings
┌──────────────────────────────────────┐
│ Globe            [ Chat          ▾ ] │
│ Right ⌘          [ Dictate       ▾ ] │
│ Right ⌥          [ Translate     ▾ ] │
├──────────────────────────────────────┤
│ ☑ Speak answers out loud             │
│ ☑ Clean up dictated text             │
│ ☐ Duck other audio while recording   │
├──────────────────────────────────────┤
│ Double-tap the Chat key to start a   │
│ new thread. Changes apply at once.   │
└──────────────────────────────────────┘
```

## Left to the builder

Implement, test the ramp and the toggle, build and install to both app locations, and hand the user a hands-on audio check (music playing while holding a key, then confirming the exact volume returns).
