# Configurable Hotkeys — Design

**Date:** 2026-11-19
**Status:** Approved

## Intent

The three hold-to-talk keys (Globe, Right Command, Right Option) are currently hard-wired to fixed functions. Let the user assign a function to each key so the app fits their muscle memory and keyboard instead of forcing one layout.

## Goals

- One assignment per physical key, chosen from Chat / Dictate / Translate / Off.
- Double-tap → new chat thread follows whichever key currently holds Chat (chosen by the user in brainstorming).
- Assignments apply immediately when settings are saved, and persist across restarts.
- Existing saved settings and macOS permission grants keep working.

## Non-goals

- Arbitrary key or key-combination recording.
- Left-side modifier keys.
- Changing what the actions themselves do.

## Constraints

- Keep the 250 ms hold delay and the CGEvent "another key followed → cancel" logic; Option+e must never start a recording.
- Double-tap detection uses `NSEvent.doubleClickInterval`.
- New settings fields must decode with defaults so existing `settings.v4` blobs still load without losing user data.
- Settings saves must not drop `ChatSession` or the standalone `SpeechOutput` / `CleanupOutput` toggles.
- Rebuilds must keep bundle ID `com.zafer.zonta` and signing team `TP7C938GZF` so TCC grants do not reset.

## Approaches

- **A (chosen):** Generalize `Hotkey.swift` into one key→action model. All key logic in one place; rebinding needs no new trigger code.
- **B:** Keep the three hardcoded trigger paths and add a router in `AppModel`. Smaller diff, but the hardcoding remains and adding a key later means editing three places.
- **C:** General shortcut recorder. Much bigger, and hold-a-modifier-to-talk is not a normal shortcut — it would collide with system shortcuts.

## Decided design

- New `Zonta/HotkeyBindings.swift`: `HotkeyKey` (globe, rightCommand, rightOption), `HotkeyAction` (chat, dictate, translate, off), and a Codable `HotkeyBindings` struct with defaults, lookup helpers, and per-key fallbacks for missing or unknown stored values.
- `Hotkey.swift`: single key-parameterized event interface (`onDown/onUp/onCancel/onDoubleTap(key:)`) plus `configure(doubleTapKeys:)`. Globe stays immediate; Right Command/Option keep the hold delay and cancel-on-other-key behavior. Double-tap detection attaches to the configured keys.
- `Settings.swift`: add `hotkeys: HotkeyBindings` with defaults and per-field decode fallbacks.
- `ZontaApp.swift`: one dispatch path that looks up the action for a key; `update(settings)` re-applies bindings live.
- `SettingsView.swift`: new "Shortcuts" tab with one picker per key; header text generated from the mapping.

```
Shortcuts
┌──────────────────────────────────────┐
│ Globe            [ Chat          ▾ ] │
│ Right ⌘          [ Dictate       ▾ ] │
│ Right ⌥          [ Translate     ▾ ] │
├──────────────────────────────────────┤
│ Double-tap the Chat key to start a   │
│ new thread. Changes apply at once.   │
└──────────────────────────────────────┘
```

## Left to the builder

Implement, build with `./build.sh`, install and verify with `run.sh` (plus the `~/Applications` copy), and manually check each assignment, the double-tap-follows-chat behavior, Off, and persistence across restart.
