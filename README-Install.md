# Zonta — Installation

Zonta is a macOS menu-bar application for dictation, spoken question answering
and translation. It uses services configured by the administrator for speech
recognition, language processing and speech synthesis.

## Install

1. Move `Zonta.app` to Applications. `Install to Applications.command` does
   this and opens the app.
2. On first launch, allow microphone, accessibility and local network access.
3. Quit and reopen the app after granting permissions.

The bundle is Developer ID signed. If it is not notarized, macOS requires
right-click → Open once per Mac.

## Configure

Click the menu-bar item to open Settings. The Settings tab holds the key
assignments and the speech, cleanup and ducking switches. The other tabs hold
the endpoints, keys, models and prompts for dictation, cleanup, chat,
translation and speech.

The shipped addresses are loopback placeholders. Replace them with the
addresses of your services. Each service tab has a connectivity test.

## Use

Hold a key for 250 ms before speaking. A short tap is ignored, and pressing
another key during the hold cancels it.

| Key | Default action |
| --- | --- |
| Globe (`fn` on older keyboards) | Chat |
| Right Command | Dictate |
| Right Option | Translate |

Each key can be changed to Chat, Dictate, Translate or Off in Settings →
Settings. Double-tapping the Chat key starts a new chat thread.

With ducking on, system audio fades down during a recording and returns to its
previous level on release. If an answer is playing when a recording starts,
that answer fades out and the next answer waits 1.5 seconds.

Right-click the menu-bar item for the review panel, application log and the
speech and cleanup toggles.

## Requirements

macOS 14 or later. No additional runtime software.

## Package contents

| File | Purpose |
| --- | --- |
| `Zonta.app` | Signed application bundle |
| `Zonta.zip` | Signature-preserving archive |
| `Install to Applications.command` | Copies the app to Applications and opens it |
| `Read Me First.md` | This document |

## License

Apache License 2.0. See the LICENSE file in the source repository.
