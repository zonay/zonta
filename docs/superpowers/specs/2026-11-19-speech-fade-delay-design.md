# Graceful Speech Interruption — Design

**Date:** 2026-11-19
**Status:** Approved

## Intent

When a new hold-to-talk recording starts while Zonta is speaking an answer, stop that answer gracefully instead of cutting it off, and give the next answer a short pause before it speaks so the two cannot collide.

## Goals

- Fade Zonta's own `AVAudioPlayer` volume from its current level to 0 over ~250 ms, then stop the player.
- When a new answer follows an interrupted one, wait ~1.5 s before speaking it.
- Normal replies, with no interruption, stay immediate.
- Works whether the system-audio ducking toggle is on or off.

## Non-goals

- Changing system-wide volume behavior (already handled by `AudioDucker`).
- Fading audio from other apps.
- A delay before every spoken answer.
- Changing TTS synthesis or the speech panel.

## Constraints

- Bundle ID `com.zafer.zonta` and signing team `TP7C938GZF` unchanged.
- No new permissions, private APIs or dependencies.
- Fade math and the configured delay must be unit-testable without real audio hardware.
- A new playback must cancel an in-flight fade so it cannot attenuate the new answer.
- The 1.5 s wait must be cancellation-aware so a cancelled job never speaks.

## Approaches

- **App-level `AVAudioPlayer.volume` fade (chosen).** Independent of system output; only Zonta's answer fades, other apps' music is unaffected. Composes with the existing system ducker.
- **Reuse system duck only.** Ruled out: it only fades while a key is held, and with ducking off the answer is still hard-cut.
- **Hard stop with a fixed silence.** Ruled out: it is the abrupt behavior being replaced.

## Decided design

- New `Zonta/SpeechFade.swift`: pure `levels(from:steps:)` ramp ending exactly at 0, plus an async `run(from:)` with injectable write closure so the ramp is testable.
- `Speak.swift`: expose `isPlaying`, hold a fade task, add `fadeOutAndStop()` and keep `stop()` as an immediate cancel-and-stop. `play()` cancels any in-flight fade before starting new audio. Add `SpeechTiming.waitBeforeAnswer(interrupted:)` returning 1.5 s only when an answer was interrupted.
- `ZontaApp.swift`: in `begin()`, fade the playing answer and set an `interruptedSpeech` flag instead of calling `Speak.stop()` outright; in `enqueueSpeech`, await the configured delay when that flag is set, then clear it before speaking.

## Left to the builder

Unit tests for the ramp and the delay value, build and install to both app locations, and a hands-on check: play an answer, start a new recording mid-answer, confirm the fade and the delayed next answer.
