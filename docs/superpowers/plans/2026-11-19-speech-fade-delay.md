# Graceful Speech Interruption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fade Zonta's spoken answer out gracefully when a new recording starts, and wait ~1.5 s before speaking the answer that follows an interrupted one.

**Architecture:** Add a testable `SpeechFade` ramp for `AVAudioPlayer.volume`, wire it into `Speak` with cancellation of in-flight fades on new playback, and have `AppModel` flag interruptions so `enqueueSpeech` inserts a cancellation-aware delay only for answers that followed an interruption.

**Tech Stack:** Swift 6, AVFoundation `AVAudioPlayer`, plain `swiftc` via `./build.sh`; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-19-speech-fade-delay-design.md`

## Global Constraints

- Bundle ID `com.zafer.zonta` and signing team `TP7C938GZF` must not change.
- Fade duration ~250 ms in 10 steps of 25 ms, ending exactly at 0.
- The next-answer wait is exactly 1.5 s and applies only after an interrupted answer.
- No new permissions, private APIs or dependencies.
- A new playback must cancel an in-flight fade; a cancelled job must never speak.
- Works with the system-audio ducking toggle either on or off.

## Review Focus

1. **New playback starts during an in-flight fade** — the fade must not attenuate the new answer. `Speak.fadeOutAndStop` holds a cancellable task and `play()` cancels it; proxy test `cancelling a run stops further writes`.
2. **Job cancelled during the 1.5 s wait** — no speech occurs. `enqueueSpeech` uses `try await Task.sleep` so cancellation propagates.
3. **Ducking disabled** — the app's own answer still fades. `begin()` calls the fade unconditionally.
4. **Normal reply with no interruption** — no delay. Task 2 test `normal answer has no wait`.
5. **Fade completes at zero and stops the player** — Task 1 tests `levels end at zero` and `run writes the final zero`.

---

### Task 1: Testable speech fade ramp

**Files:**
- Create: `Zonta/SpeechFade.swift`
- Create: `Tests/SpeechFadeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@MainActor final class SpeechFade`
  - `static let steps: Int = 10`
  - `static let duration: Duration = .milliseconds(250)`
  - `init(write: @escaping (Float) -> Void)`
  - `static func levels(from: Float, steps: Int = SpeechFade.steps) -> [Float]`
  - `func run(from: Float) async`

- [ ] **Step 1: Write the failing test file**

Create `Tests/SpeechFadeTests.swift`:

```swift
import Foundation

@main
struct SpeechFadeTests {
    @MainActor
    static func main() async throws {
        let levels = SpeechFade.levels(from: 1)
        check(levels.count == SpeechFade.steps, "one level per step")
        check(levels.last == 0, "levels end at zero")
        check(levels == levels.sorted(by: >=), "levels decrease monotonically")
        check(SpeechFade.levels(from: 0.5).first! == 0.45, "first step starts at the current level")

        do {
            var writes: [Float] = []
            let fade = SpeechFade { writes.append($0) }
            await fade.run(from: 1)
            check(writes.count == SpeechFade.steps, "run writes one value per step")
            check(writes.last == 0, "run writes the final zero")
        }
        do {
            var writes: [Float] = []
            let fade = SpeechFade { writes.append($0) }
            let task = Task { @MainActor in await fade.run(from: 1) }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            let countAtCancel = writes.count
            try await Task.sleep(for: .milliseconds(250))
            check(writes.count == countAtCancel, "cancelling a run stops further writes")
        }
        print("all speech fade tests passed")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        if !condition() { fatalError("FAILED: \(label)") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -o build/speech-fade-tests Zonta/SpeechFade.swift Tests/SpeechFadeTests.swift`

Expected: compile failure — `SpeechFade` does not exist.

- [ ] **Step 3: Implement `Zonta/SpeechFade.swift`**

Use exactly the signatures from Interfaces. `levels` returns `steps` values computed as `from * (1 - Float(i) / Float(steps))` for `i` in `1...steps`. `run(from:)` iterates those levels, waits 25 ms before each write, and returns early if `Task.isCancelled`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swiftc -o build/speech-fade-tests Zonta/SpeechFade.swift Tests/SpeechFadeTests.swift && build/speech-fade-tests`

Expected: `all speech fade tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Zonta/SpeechFade.swift Tests/SpeechFadeTests.swift
git commit -m "feat: add testable speech volume fade ramp"
```

### Task 2: Speak integration and timing rule

**Files:**
- Modify: `Zonta/Speak.swift`
- Modify: `Tests/SpeechFadeTests.swift` (timing assertions)

**Interfaces:**
- Consumes: `SpeechFade` from Task 1.
- Produces:
  - `enum SpeechTiming { static func waitBeforeAnswer(interrupted: Bool) -> Duration }`
  - `Speak.isPlaying: Bool` (`@MainActor`)
  - `Speak.fadeOutAndStop()` (`@MainActor`)
  - existing `Speak.say`, `Speak.stop`, `Speak.play` signatures unchanged.

- [ ] **Step 1: Add the failing timing assertions**

In `Tests/SpeechFadeTests.swift`, right after the `levels` checks in `main()`, add:

```swift
        check(SpeechTiming.waitBeforeAnswer(interrupted: true) == .seconds(1.5), "interrupted answer waits 1.5s")
        check(SpeechTiming.waitBeforeAnswer(interrupted: false) == .zero, "normal answer has no wait")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -o build/speech-fade-tests Zonta/SpeechFade.swift Zonta/Speak.swift Tests/SpeechFadeTests.swift -framework AVFoundation`

Expected: compile failure — `SpeechTiming` does not exist.

- [ ] **Step 3: Implement `SpeechTiming` and the fade in `Speak.swift`**

`SpeechTiming.waitBeforeAnswer(interrupted:)` returns `.seconds(1.5)` when true, otherwise `.zero`. Add `@MainActor static var isPlaying: Bool { player?.isPlaying ?? false }`, a `private static var fadeTask: Task<Void, Never>?`, and `fadeOutAndStop()` which captures the current player volume, cancels any existing fade task, and starts a `@MainActor` Task that awaits `SpeechFade.run(from:)` then performs the existing hard stop only if the task was not cancelled. Keep `stop()` as an immediate cancel-and-stop that also cancels `fadeTask`. In `play(_:)`, call the cancel-and-stop path before installing the new player, so an in-flight fade cannot attenuate new speech.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swiftc -o build/speech-fade-tests Zonta/SpeechFade.swift Zonta/Speak.swift Tests/SpeechFadeTests.swift -framework AVFoundation && build/speech-fade-tests`

Expected: `all speech fade tests passed`.

- [ ] **Step 5: Commit**

```bash
git add Zonta/Speak.swift Tests/SpeechFadeTests.swift
git commit -m "feat: fade spoken answers and add interruption timing rule"
```

### Task 3: AppModel interruption handling

**Files:**
- Modify: `Zonta/ZontaApp.swift`

**Interfaces:**
- Consumes: `Speak.isPlaying`, `Speak.fadeOutAndStop()`, `Speak.stop()`, `SpeechTiming`.
- Produces: nothing.

- [ ] **Step 1: Fade instead of hard-stopping an active answer**

In `begin(_:)`, keep the existing `queue.hasActive(.speech)` check and speech-lane cancellation. Replace the direct `Speak.stop()` with: if `Speak.isPlaying` then call `Speak.fadeOutAndStop()` and set a new private `interruptedSpeech` flag to `true`; otherwise call `Speak.stop()`.

- [ ] **Step 2: Delay only the answer that followed an interruption**

In `enqueueSpeech(_:settings:)`, before calling `Speak.say`, capture and clear `interruptedSpeech`, then if it was true call `try await Task.sleep(for: SpeechTiming.waitBeforeAnswer(interrupted: true))`. Cancellation must propagate out of the job rather than playing speech.

- [ ] **Step 3: Verify the build**

Run: `./build.sh`

Expected: compiles; stable identity line present.

- [ ] **Step 4: Commit**

```bash
git add Zonta/ZontaApp.swift
git commit -m "feat: delay the answer that follows an interrupted speech"
```

### Task 4: Install and verify

**Files:** none.

- [ ] **Step 1: Run every automated check**

Run: `swiftc -o build/speech-fade-tests Zonta/SpeechFade.swift Zonta/Speak.swift Tests/SpeechFadeTests.swift -framework AVFoundation && build/speech-fade-tests && swiftc -framework CoreAudio -framework AudioToolbox -o build/audio-ducker-tests Zonta/AudioDucker.swift Tests/AudioDuckerTests.swift && build/audio-ducker-tests && swiftc -framework AppKit -framework CoreGraphics -o build/hotkey-bindings-tests Zonta/HotkeyBindings.swift Zonta/Settings.swift Zonta/Hotkey.swift Tests/HotkeyBindingsTests.swift && build/hotkey-bindings-tests && ./build.sh`

Expected: all three test binaries print their success lines; clean build with stable identity line.

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

- [ ] **Step 3: Verify manually (user)**

Ask a question, hear the answer start, then immediately start a new recording: the answer should fade out rather than cut, and the next answer should begin about 1.5 s later. Repeat with ducking off. Confirm a normal follow-up answer has no added pause.

- [ ] **Step 4: Confirm clean tree**

Run: `git status --short`

Expected: empty.
