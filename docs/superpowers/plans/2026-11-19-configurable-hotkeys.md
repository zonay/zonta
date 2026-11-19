# Configurable Hotkeys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users assign Chat / Dictate / Translate / Off to Globe, Right ⌘ and Right ⌥, with double-tap → new thread following the Chat key.

**Architecture:** Add a small Codable binding model, generalize `Hotkey.swift` from three hardcoded callback sets to one key-parameterized event interface, dispatch through the current mapping in `AppModel`, and expose the mapping in a new Settings tab. Existing settings blobs stay valid through per-field decode fallbacks.

**Tech Stack:** Swift 6, AppKit / SwiftUI, Carbon HIToolbox, CoreGraphics event taps. Plain `swiftc` build via `./build.sh`; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-19-configurable-hotkeys-design.md`

## Global Constraints

- Bundle ID `com.zafer.zonta` and signing identity `Developer ID Application: ZAFER ONAY (TP7C938GZF)` must not change — TCC grants must survive the rebuild.
- Existing `settings.v4` blobs must decode with default hotkeys; a bad stored value must not discard the rest of the settings.
- Hold delay stays 250 ms; the CGEvent tap must still cancel a pending/active hold when another non-modifier key is pressed (Option+e must never start a recording).
- Double-tap window is `NSEvent.doubleClickInterval`.
- Globe presses start/stop immediately; Right Command/Option presses use the 250 ms pending hold. Preserve this asymmetry.
- No third-party dependencies; everything must compile with the existing `./build.sh`.

## Review Focus

1. **Old `settings.v4` blob with no `hotkeys` key** — must load with default bindings and keep every other field. Test in Task 1 (old-blob assertion).
2. **Unknown action string stored in a binding** — must fall back per-key without throwing or wiping the whole blob. Test in Task 1 (unknown-value assertion).
3. **Two keys assigned the same action (e.g. both Chat)** — both must work, and double-tap must fire on both. Test in Task 1 (`keys(for:)` assertion) plus Task 5 manual check.
4. **A key set to Off** — pressing/releasing it must do nothing and leave no stuck recording. Manual check in Task 5.
5. **Rebinding while a recording is active or right after a double-tap** — stale pending/anchor state must be cleared so the next press behaves normally. Logic in Task 2 (`configure` reset), manual check in Task 5.

---

### Task 1: Binding model and persistence

**Files:**
- Create: `Zonta/HotkeyBindings.swift`
- Modify: `Zonta/Settings.swift` (memberwise init, `defaults`, `CodingKeys`, `init(from:)`)
- Create: `Tests/HotkeyBindingsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum HotkeyKey: Hashable { case globe, rightCommand, rightOption }`
  - `enum HotkeyAction: String, Codable, CaseIterable, Identifiable { case chat, dictate, translate, off }` with `var id: String { rawValue }` and `var label: String`
  - `struct HotkeyBindings: Codable, Equatable { var globe: HotkeyAction; var rightCommand: HotkeyAction; var rightOption: HotkeyAction; static let defaults: HotkeyBindings; func action(for key: HotkeyKey) -> HotkeyAction; func keys(for action: HotkeyAction) -> Set<HotkeyKey> }`
  - `Settings.hotkeys: HotkeyBindings`

- [ ] **Step 1: Write the failing test file**

Create `Tests/HotkeyBindingsTests.swift` with these assertions (keep them exactly):

```swift
import Foundation

@main
struct HotkeyBindingsTests {
    static func main() throws {
        check(HotkeyBindings.defaults.globe == .chat, "default globe")
        check(HotkeyBindings.defaults.rightCommand == .dictate, "default right command")
        check(HotkeyBindings.defaults.rightOption == .translate, "default right option")

        let b = HotkeyBindings(globe: .translate, rightCommand: .off, rightOption: .chat)
        check(b.action(for: .globe) == .translate, "action(for: .globe)")
        check(b.action(for: .rightCommand) == .off, "action(for: .rightCommand)")
        check(b.keys(for: .chat) == [.rightOption], "keys(for: .chat)")
        check(b.keys(for: .off) == [.rightCommand], "keys(for: .off)")

        let round = try JSONDecoder().decode(
            HotkeyBindings.self, from: JSONEncoder().encode(b)
        )
        check(round == b, "encode/decode round trip")

        let partial = try JSONDecoder().decode(
            HotkeyBindings.self,
            from: Data(#"{"globe":"dictate"}"#.utf8)
        )
        check(partial.globe == .dictate, "partial JSON: explicit key")
        check(partial.rightCommand == .dictate, "partial JSON: fallback right command")
        check(partial.rightOption == .translate, "partial JSON: fallback right option")

        let unknown = try JSONDecoder().decode(
            HotkeyBindings.self,
            from: Data(#"{"globe":"bananas","rightCommand":"chat"}"#.utf8)
        )
        check(unknown.globe == .chat, "unknown value falls back to default")
        check(unknown.rightCommand == .chat, "unknown value keeps the other key")

        let oldBlob = Data(#"{"whisperModel":"my-model","chatLLM":{"baseURL":"http://x/v1","apiKey":"k","model":"m"}}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: oldBlob)
        check(settings.hotkeys == .defaults, "old Settings blob gets default hotkeys")
        check(settings.whisperModel == "my-model", "old Settings blob keeps other fields")

        print("all hotkey binding tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAILED: \(label)") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mkdir -p build && swiftc -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests`

Expected: compile failure — `HotkeyBindings`, `HotkeyAction` and `Settings.hotkeys` do not exist yet.

- [ ] **Step 3: Implement `Zonta/HotkeyBindings.swift`**

Use exactly the signatures from Interfaces. `HotkeyAction` is a raw-value `String` enum so `label` returns the display names "Chat", "Dictate", "Translate", "Off". `HotkeyBindings.defaults` is `{ .chat, .dictate, .translate }`.

`init(from:)` decodes each field as `String?` with `decodeIfPresent`, maps through `HotkeyAction(rawValue:) ?? <that key's default>`, so missing keys and unknown strings both fall back without throwing. `keys(for:)` returns every key whose action matches (so duplicate assignments are supported).

- [ ] **Step 4: Add `hotkeys` to `Settings`**

In `Zonta/Settings.swift`: add `var hotkeys: HotkeyBindings` and a matching parameter to the explicit memberwise `init`; set it in `Settings.defaults`; add `case hotkeys` to `CodingKeys`; in `init(from:)` add `hotkeys = try c.decodeIfPresent(HotkeyBindings.self, forKey: .hotkeys) ?? d.hotkeys`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `swiftc -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests`

Expected: `all hotkey binding tests passed`.

- [ ] **Step 6: Commit**

```bash
git add Zonta/HotkeyBindings.swift Zonta/Settings.swift Tests/HotkeyBindingsTests.swift
git commit -m "feat: add persisted hotkey binding model"
```

### Task 2: Generalize the hotkey engine

**Files:**
- Modify: `Zonta/Hotkey.swift`
- Modify: `Tests/HotkeyBindingsTests.swift` (compile-time interface check only)

**Interfaces:**
- Consumes: `HotkeyKey` from Task 1.
- Produces:
  - `Hotkey.onDown: ((HotkeyKey) -> Void)?`
  - `Hotkey.onUp: ((HotkeyKey) -> Void)?`
  - `Hotkey.onCancel: ((HotkeyKey) -> Void)?`
  - `Hotkey.onDoubleTap: ((HotkeyKey) -> Void)?`
  - `Hotkey.configure(doubleTapKeys: Set<HotkeyKey>)`
  - existing `start()` / `stop()` signatures unchanged.

- [ ] **Step 1: Add the compile-time interface check to the test file**

Append this function (never called — it exists to make the interface a compile-time contract) to `HotkeyBindingsTests`:

```swift
@MainActor
private func compileTimeHotkeyInterface(_ hotkey: Hotkey) {
    hotkey.onDown = { (_: HotkeyKey) in }
    hotkey.onUp = { (_: HotkeyKey) in }
    hotkey.onCancel = { (_: HotkeyKey) in }
    hotkey.onDoubleTap = { (_: HotkeyKey) in }
    hotkey.configure(doubleTapKeys: [.globe])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -framework AppKit -framework CoreGraphics -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests`

Expected: compile failure — `Hotkey` has no `onDown`, `configure(doubleTapKeys:)`, etc.

- [ ] **Step 3: Replace the callback interface and state**

In `Zonta/Hotkey.swift`: replace the nine action-specific closures with the four key-parameterized closures from Interfaces; add `configure(doubleTapKeys:)`. Replace `lastGlobeDown`, `suppressGlobeUp`, `globeHeld`, `Side`, `pending` and `active` with per-key state: `lastPress: [HotkeyKey: Date]`, `suppressed: Set<HotkeyKey>`, `pressed: Set<HotkeyKey>`, `pending: HotkeyKey?`, `active: HotkeyKey?`. Keep `pendingTask` and `holdDelay = .milliseconds(250)`.

- [ ] **Step 4: Generalize press/release handling**

In `handle(_:)`: detect Globe via `event.modifierFlags.contains(.function)` and Right Command/Option via `event.keyCode` plus `.command`/`.option` flags. On a press edge, if the key is in `doubleTapKeys` and `lastPress[key]` is within `NSEvent.doubleClickInterval`, clear that anchor, insert the key into `suppressed`, cancel any pending hold for it, fire `onDoubleTap(key)`, and return. Otherwise record `lastPress[key]`, then fire `onDown(key)` for Globe or call `beginHold(key)` for the other two.

On a release edge, if the key is in `suppressed`, remove it and return. Otherwise fire `onUp(key)` for Globe or call `release(key)` for the other two.

- [ ] **Step 5: Generalize the hold state machine**

`beginHold(_:)`, `release(_:)`, `abort()` and `handleTap(_:)` take `HotkeyKey` instead of `Side`; `beginHold` calls `onDown(key)` when the 250 ms delay elapses, `release` calls `onUp(key)`, `abort` calls `onCancel(key)`. Keep the existing guard that ignores non-modifier key codes in `handleTap`. `configure(doubleTapKeys:)` resets `lastPress`, `suppressed`, `pressed`, `pending`, `active`, cancels `pendingTask`, and stores the new key set.

- [ ] **Step 6: Run the test and the app build**

Run: `swiftc -framework AppKit -framework CoreGraphics -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests`

Expected: `all hotkey binding tests passed`.

Then run: `./build.sh`

Expected: compiles successfully; only the known `installTap` deprecation warning; line `==> stable identity verified: com.zafer.zonta / team TP7C938GZF` present.

- [ ] **Step 7: Commit**

```bash
git add Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift
git commit -m "feat: generalize hotkey engine to key-based events"
```

### Task 3: Dispatch through the current binding

**Files:**
- Modify: `Zonta/ZontaApp.swift` (`boot()` lines 78-87, `update(_:)` line 384)

**Interfaces:**
- Consumes: `Hotkey` interface from Task 2; `Settings.hotkeys`, `HotkeyBindings.action(for:)` and `keys(for:)` from Task 1.
- Produces: nothing.

- [ ] **Step 1: Replace hardcoded wiring in `boot()`**

Delete the nine `hotkey.onGlobe...` / `onRightCommand...` / `onRightOption...` assignments. Install four closures instead: `onDown` calls `handleHotkeyDown(key)`, `onUp` calls `end()`, `onCancel` calls `cancel()`, `onDoubleTap` calls `newChatThread()`. Call `applyHotkeyBindings()` before `hotkey.start()`.

- [ ] **Step 2: Add dispatch and reconfigure helpers**

Add `private func applyHotkeyBindings()` that computes `settings.hotkeys.keys(for: .chat)` and calls `hotkey.configure(doubleTapKeys:)` with that set. Add `private func handleHotkeyDown(_ key: HotkeyKey)` that switches on `settings.hotkeys.action(for: key)`: `.chat` / `.dictate` / `.translate` call `begin(...)`, `.off` does nothing.

- [ ] **Step 3: Reconfigure on settings change**

In `update(_:)`, after `self.settings = settings`, call `applyHotkeyBindings()` so a saved reassignment takes effect immediately without a restart.

- [ ] **Step 4: Verify the build**

Run: `./build.sh`

Expected: compiles; stable identity line present.

- [ ] **Step 5: Commit**

```bash
git add Zonta/ZontaApp.swift
git commit -m "feat: dispatch hotkeys through saved bindings"
```

### Task 4: Shortcuts settings tab

**Files:**
- Modify: `Zonta/SettingsView.swift` (`Tab` enum, `body` switch, `header`, new `shortcutFields`)

**Interfaces:**
- Consumes: `Settings.hotkeys`, `HotkeyAction.allCases` and `label`.
- Produces: nothing.

- [ ] **Step 1: Add the tab**

Add `case shortcuts = "Shortcuts"` to `Tab`, return `"keyboard"` from `symbol`, and add `case .shortcuts: shortcutFields` to the `Form` switch.

- [ ] **Step 2: Implement `shortcutFields`**

Three `Picker`s bound to `$settings.hotkeys.globe`, `$settings.hotkeys.rightCommand` and `$settings.hotkeys.rightOption`, each listing `HotkeyAction.allCases` with `Text(action.label).tag(action)`. Label rows "Globe", "Right ⌘", "Right ⌥". Footer text: "Double-tap the Chat key to start a new thread. Choose Off to disable a key. Changes apply as soon as you save."

- [ ] **Step 3: Make the header dynamic**

Replace the hardcoded `"Globe ask · Right ⌘ dictate · Right ⌥ translate"` with a computed string built from `settings.hotkeys`: one `"<key> <action label>"` segment per key, omitting `.off`; when every key is Off show `"All hotkeys off"`.

- [ ] **Step 4: Verify the build**

Run: `./build.sh`

Expected: compiles; stable identity line present.

- [ ] **Step 5: Commit**

```bash
git add Zonta/SettingsView.swift
git commit -m "feat: add Shortcuts settings tab"
```

### Task 5: Install and verify end to end

**Files:** none (runs the existing build/install scripts).

- [ ] **Step 1: Run the automated checks**

Run: `swiftc -framework AppKit -framework CoreGraphics -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests && ./build.sh`

Expected: tests print `all hotkey binding tests passed`; build clean with only the `installTap` warning and the stable identity line.

- [ ] **Step 2: Install to both app locations with backups**

Timestamped backups are kept as siblings; `ditto` preserves the signature; clear quarantine; verify each signature; relaunch from `/Applications`.

```bash
set -euo pipefail
cd /Users/zafer/projects/zonta
TS="$(date +%Y%m%d-%H%M%S)"
pkill -x Zonta 2>/dev/null || true
sleep 1
for DEST in "/Applications/Zonta.app" "$HOME/Applications/Zonta.app"; do
  if [[ -d "$DEST" ]]; then
    ditto "$DEST" "${DEST}.bak-${TS}"
    rm -rf "$DEST"
  fi
  ditto build/Zonta.app "$DEST"
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  codesign --verify --deep --strict "$DEST"
done
open /Applications/Zonta.app
```

Expected: both copies signed by `Developer ID Application: ZAFER ONAY (TP7C938GZF)`; app launches.

- [ ] **Step 3: Verify the default mapping still works**

With untouched settings: hold Globe → voice chat + spoken answer; double-tap Globe → new chat thread; hold Right ⌘ → dictate and paste; hold Right ⌥ → translate and paste. Type Option+e in a text field and confirm no recording starts.

- [ ] **Step 4: Verify reassignment, double-tap follow, Off and duplicates**

In Settings → Shortcuts: assign Chat to Right ⌘. Confirm double-tapping Right ⌘ starts a new thread and Globe no longer chats. Set Globe to Off and confirm pressing it does nothing and leaves no stuck "Listening…" state. Assign Chat to a second key as well and confirm both keys work and both support double-tap.

- [ ] **Step 5: Verify live apply and persistence**

Confirm a change made in Settings takes effect without restarting and the header line updates. Quit and relaunch Zonta; confirm the mapping persisted. Confirm no new microphone/accessibility/notification permission prompt appeared.

- [ ] **Step 6: Confirm clean tree**

Run: `git status --short`

Expected: empty (docs and all source changes committed).
