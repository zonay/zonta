# Audio Ducking and Consolidated Settings Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optionally fade the Mac's system audio down during a Zonta recording and back on release, and gather the everyday switches into a renamed Settings tab.

**Architecture:** Add a testable `AudioDucker` that reads/writes the default output device volume through CoreAudio with injectable closures, persist an off-by-default toggle outside the settings blob, hook duck/restore into `AppModel`'s recording lifecycle, and move the existing speech/cleanup switches into the renamed tab.

**Tech Stack:** Swift 6, AppKit / SwiftUI, CoreAudio + AudioToolbox, plain `swiftc` via `./build.sh`; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-19-audio-ducking-settings-tab-design.md`

## Global Constraints

- Bundle ID `com.zafer.zonta` and signing identity `Developer ID Application: ZAFER ONAY (TP7C938GZF)` must not change.
- The ducking toggle is stored under `audio.duck.v1` in `UserDefaults`, default `false`, outside the `settings.v4` blob.
- Fade is ~250 ms: 10 steps of 25 ms, eased linearly.
- `restore()` returns to the exact level captured at `duck()` time, even if the volume was changed externally during the hold.
- Ducking must be a no-op when the output volume cannot be read.
- No third-party dependencies.

## Review Focus

1. **Volume changed externally during a duck** — restore still ends at the captured level, not the changed one. Task 1 test `external change is overridden by restore`.
2. **Two overlapping holds or a rebind ending an active hold** — `duck()` is idempotent and a single original level is kept; restore still runs. Task 1 test `repeated duck keeps the first original`; Task 2 wiring in `end()` / `cancel()` / `handleError`.
3. **Ducking switched off mid-hold** — audio returns immediately and no further ducking occurs. Task 2 `setDuckAudioEnabled` step, manual check in Task 4.
4. **Output volume API unavailable** — no writes, no crash, no active state. Task 1 test `nil volume produces no writes`.
5. **Restore mid-fade** — cancelling a duck ramp and restoring starts from the current volume and still lands on the original, with no jump to zero. Task 1 tests `restore ends at captured original` and `repeated duck keeps the first original`.

---

### Task 1: AudioDucker and its ramp tests

**Files:**
- Create: `Zonta/AudioDucker.swift`
- Create: `Tests/AudioDuckerTests.swift`
- Modify: `build.sh` (link CoreAudio and AudioToolbox)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum` of nothing; `@MainActor final class AudioDucker`
  - `static let fadeDuration: Duration = .milliseconds(250)`
  - `static let steps: Int = 10`
  - `init(readVolume: @escaping () -> Float32?, writeVolume: @escaping (Float32) -> Void)`
  - `var isDucked: Bool { get }`
  - `func duck()`
  - `func restore()`
  - `static func systemVolume() -> Float32?`
  - `static func setSystemVolume(_ value: Float32)`

- [ ] **Step 1: Write the failing test file**

Create `Tests/AudioDuckerTests.swift` with exactly these cases:

```swift
import Foundation

@main
struct AudioDuckerTests {
    @MainActor
    static func main() async throws {
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.count == AudioDucker.steps, "duck writes one value per step")
            check(writes.last == 0, "duck ends at zero")
            check(d.isDucked, "duck marks active")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            writes.removeAll()
            d.restore()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.last == 0.8, "restore ends at captured original")
            check(!d.isDucked, "restore clears active state")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            current = 0.3
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            writes.removeAll()
            d.restore()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.last == 0.8, "repeated duck keeps the first original")
        }
        do {
            var current: Float32? = 0.8
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { current }, writeVolume: { v in writes.append(v); current = v })
            d.duck()
            try await Task.sleep(for: .milliseconds(400))
            current = 0.5
            d.restore()
            try await Task.sleep(for: .milliseconds(400))
            check(writes.last == 0.8, "restore wins over external volume change")
        }
        do {
            var writes: [Float32] = []
            let d = AudioDucker(readVolume: { nil }, writeVolume: { writes.append($0) })
            d.duck()
            try await Task.sleep(for: .milliseconds(100))
            check(writes.isEmpty, "nil volume produces no writes")
            check(!d.isDucked, "nil volume does not mark active")
            d.restore()
            check(writes.isEmpty, "restore without duck is a no-op")
        }
        print("all audio ducker tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAILED: \(label)") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -framework CoreAudio -framework AudioToolbox -o build/audio-ducker-tests Zonta/AudioDucker.swift Tests/AudioDuckerTests.swift`

Expected: compile failure — `AudioDucker` does not exist.

- [ ] **Step 3: Implement `Zonta/AudioDucker.swift`**

Use exactly the signatures from Interfaces. `duck()` is a no-op when `isDucked` or when `readVolume()` is `nil` or `0`; otherwise store that value as `original` and ramp from it to `0`. `restore()` is a no-op unless `isDucked`; clear `original`, then ramp from `readVolume() ?? 0` to the captured value. Each ramp cancels the previous `rampTask` and writes `AudioDucker.steps` values, 25 ms apart, with the final write exactly equal to the target.

`systemVolume()` reads `kAudioHardwarePropertyDefaultOutputDevice` from `kAudioObjectSystemObject`, then `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` on the output scope with `kAudioObjectPropertyElementMain`; `setSystemVolume(_:)` writes that same address on the default device. Return `nil` on any CoreAudio failure.

- [ ] **Step 4: Add the frameworks to `build.sh`**

In the main `swiftc` compile line, add `-framework CoreAudio -framework AudioToolbox` alongside the existing frameworks.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swiftc -framework CoreAudio -framework AudioToolbox -o build/audio-ducker-tests Zonta/AudioDucker.swift Tests/AudioDuckerTests.swift && build/audio-ducker-tests`

Expected: `all audio ducker tests passed`.

- [ ] **Step 6: Commit**

```bash
git add Zonta/AudioDucker.swift Tests/AudioDuckerTests.swift build.sh
git commit -m "feat: add testable CoreAudio volume ducker"
```

### Task 2: Toggle and recording-lifecycle wiring

**Files:**
- Modify: `Zonta/Settings.swift`
- Modify: `Zonta/ZontaApp.swift`
- Modify: `Tests/HotkeyBindingsTests.swift` (one assertion for the toggle default)

**Interfaces:**
- Consumes: `AudioDucker` from Task 1.
- Produces:
  - `enum AudioDuckOutput { static var enabled: Bool }`
  - `AppModel.duckAudioEnabled: Bool`
  - `AppModel.setDuckAudioEnabled(_ enabled: Bool)`

- [ ] **Step 1: Add the failing default assertion**

In `Tests/HotkeyBindingsTests.swift`, immediately after the first `check(` line in `main()`, add:

```swift
        check(AudioDuckOutput.enabled == false, "audio duck defaults off")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -framework AppKit -framework CoreGraphics -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift`

Expected: compile failure — `AudioDuckOutput` does not exist.

- [ ] **Step 3: Implement `AudioDuckOutput` in `Settings.swift`**

Follow the `SpeechOutput` pattern exactly: private key `"audio.duck.v1"`, `UserDefaults.standard.object(forKey:) as? Bool ?? false` getter, `set` setter.

- [ ] **Step 4: Wire the ducker into `AppModel`**

Add `@Published var duckAudioEnabled: Bool = AudioDuckOutput.enabled`, `private let ducker = AudioDucker()`, and `setDuckAudioEnabled(_:)` which updates the flag, persists it, and calls `ducker.restore()` immediately when switching off while ducked.

In `begin(_:)`, after `try recorder.start()` succeeds and before returning, call `if duckAudioEnabled { ducker.duck() }`. In `end()`, call `ducker.restore()` once the recorder has stopped and before the minimum-duration early return. In `cancel()` and `handleError(_:)`, call `ducker.restore()`.

- [ ] **Step 5: Run both test binaries and the app build**

Run: `swiftc -framework AppKit -framework CoreGraphics -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests && ./build.sh`

Expected: `all hotkey binding tests passed`; build succeeds with only the known `installTap` warning and the stable identity line.

- [ ] **Step 6: Commit**

```bash
git add Zonta/Settings.swift Zonta/ZontaApp.swift Tests/HotkeyBindingsTests.swift
git commit -m "feat: duck system audio during recordings"
```

### Task 3: Consolidated Settings tab

**Files:**
- Modify: `Zonta/SettingsView.swift`

**Interfaces:**
- Consumes: `AppModel.speechEnabled`, `AppModel.cleanupEnabled`, `AppModel.duckAudioEnabled`, their setters, `Settings.hotkeys`.
- Produces: nothing.

- [ ] **Step 1: Rename the tab**

Change `case shortcuts = "Shortcuts"` to `case settings = "Settings"` in `Tab`, keep the `"keyboard"` symbol, and change the `Form` switch case to `case .settings: settingsFields`.

- [ ] **Step 2: Build `settingsFields`**

Rename `shortcutFields` to `settingsFields`. Keep the three key pickers in their own section. Add a second section headed "Switches" with three `Toggle`s: "Speak answers out loud" bound to `model.speechEnabled` via `model.setSpeechEnabled`, "Clean up dictated text" bound to `model.cleanupEnabled` via `model.setCleanupEnabled`, and "Duck other audio while recording" bound to `model.duckAudioEnabled` via `model.setDuckAudioEnabled`. Keep the existing footer about double-tap and Off.

- [ ] **Step 3: Remove the moved toggles from their old tabs**

Delete the speech toggle section from `speechFields` and the cleanup toggle section from `cleanupFields`, leaving their server, prompt and test sections intact.

- [ ] **Step 4: Verify the build**

Run: `./build.sh`

Expected: compiles; stable identity line present.

- [ ] **Step 5: Commit**

```bash
git add Zonta/SettingsView.swift
git commit -m "feat: consolidate everyday switches in Settings tab"
```

### Task 4: Install and verify end to end

**Files:** none.

- [ ] **Step 1: Run every automated check**

Run: `swiftc -framework CoreAudio -framework AudioToolbox -o build/audio-ducker-tests Zonta/AudioDucker.swift Tests/AudioDuckerTests.swift && build/audio-ducker-tests && swiftc -framework AppKit -framework CoreGraphics -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests && ./build.sh`

Expected: `all audio ducker tests passed`, `all hotkey binding tests passed`, clean build with stable identity line.

- [ ] **Step 2: Install to both app locations with backups**

```bash
set -euo pipefail
TS="$(date +%Y%m%d-%H%M%S)"
pkill -x Zonta 2>/dev/null || true
sleep 1
for DEST in "/Applications/Zonta.app" "$HOME/Applications/Zonta.app"; do
  [[ -d "$DEST" ]] && { ditto "$DEST" "${DEST}.bak-${TS}"; rm -rf "$DEST"; }
  ditto /Users/zafer/.local/share/opencode/worktree/c85cd6/configurable-hotkeys/build/Zonta.app "$DEST"
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  codesign --verify --deep --strict "$DEST"
done
open /Applications/Zonta.app
```

Expected: both copies signed by the stable Developer ID; app running.

- [ ] **Step 3: Verify the Settings tab**

Open Settings and confirm the tab is named "Settings", the three key pickers are present, the three switches are present, and the old Speech and Cleanup tabs no longer duplicate the switches.

- [ ] **Step 4: Verify ducking behavior manually (user)**

With music playing and the toggle off, hold a bound key and confirm the volume does not change. Turn the toggle on, hold a key, confirm the music eases down over about a quarter second, and on release confirm it eases back to exactly the previous level. Repeat with a short tap and with the Chat key rebound to another button.

- [ ] **Step 5: Confirm clean tree**

Run: `git status --short`

Expected: empty.
