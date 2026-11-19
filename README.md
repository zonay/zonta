# Zonta

Zonta is a macOS menu-bar application for hold-to-talk dictation, spoken
question answering and translation. Audio capture and text insertion happen on
the local Mac. Speech recognition, language processing and speech synthesis are
sent to configured OpenAI-compatible HTTP services.

No models or credentials are bundled. All endpoints, keys, models and prompts
are entered in Settings.

## Requirements

- macOS 14 or later
- Xcode command-line tools (`swiftc`) for building; no Xcode project is needed
- Permissions: microphone, accessibility, local network
- Reachability of the configured services

## Build and install

```bash
git clone https://github.com/zonay/zonta.git
cd zonta
./run.sh
```

`build.sh` compiles `Zonta/*.swift` into `build/Zonta.app`, generates the icon
and signs the bundle. `run.sh` builds, installs to `/Applications/Zonta.app`
and launches it. Build output under `build/` is ignored by git.

Use a stable signing identity so macOS keeps the granted permissions across
rebuilds:

```bash
./build.sh
./build.sh 'Developer ID Application: ...'
SIGN_IDENTITY='Apple Development: ...' ./build.sh
```

An ad-hoc build is for local development only; macOS treats each rebuild as a
new app and re-asks for permissions.

For a distributable package:

```bash
./package.sh 'Developer ID Application: ...'
```

This writes to `~/Desktop/Zonta/`: `Zonta.app`, `Zonta.zip`,
`Install to Applications.command` and `Read Me First.md`. Set
`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and `NOTARY_PASSWORD` to notarize the
archive. Without notarization, Gatekeeper requires a right-click → Open once
per Mac.

## Operation

Three physical keys are assignable. Hold a key for 250 ms before speaking; a
short tap is ignored, and pressing another key during the hold cancels it.
Left Command and left Option are not intercepted.

| Key | Default action |
| --- | --- |
| Globe (`fn` on older keyboards) | Chat |
| Right Command | Dictate |
| Right Option | Translate |

Each key can be set to Chat, Dictate, Translate or Off in Settings → Settings.
Double-tapping the key currently assigned to Chat starts a new chat thread
without recording.

Actions:

- **Chat** — transcribes the recording, sends it to the chat endpoint and
  speaks the reply. Answers are also kept in the review panel.
- **Dictate** — transcribes and inserts the text at the cursor, with optional
  cleanup.
- **Translate** — transcribes, translates and inserts the result.

When ducking is enabled, system audio eases down while a recording is in
progress and eases back to its previous level on release. If an answer is
playing when a new recording starts, that answer fades out and the next answer
waits 1.5 seconds before speaking.

## Settings

Click the menu-bar item to open Settings. Right-click it for the review panel,
application log, speech and cleanup toggles, Settings and Quit.

| Tab | Contents |
| --- | --- |
| Settings | Key assignments, speech toggle, cleanup toggle, ducking toggle |
| Dictation | Transcription endpoint, key, model, language, prompt |
| Cleanup | Cleanup endpoint, key, model, prompt |
| Chat | Chat endpoint, key, model, prompt, conversation id, new conversation |
| Translate | Translation endpoint, key, model, prompt |
| Speech | Speech endpoint, key, model, voice, language |

Each service tab has a connectivity test. Changes save automatically.
**Reset to defaults** restores defaults and clears the chat conversation.

Default endpoints are loopback placeholders and must be replaced:

| Service | Endpoint | Model |
| --- | --- | --- |
| Transcription | `http://localhost:6667/v1` | `whisper-large-v3-turbo` |
| Cleanup | `http://localhost:1235/v1` | `google/gemma-4-12b-qat` |
| Chat | `http://localhost:8642/v1` | `hermes-agent` |
| Translate | `http://localhost:1235/v1` | `google/gemma-4-12b-qat` |
| Speech | `http://localhost:7788/v1` | `supertonic-3` |

Requests use `/audio/transcriptions`, `/chat/completions` and `/audio/speech`.
Outbound HTTP goes through `/usr/bin/curl` so Local Network privacy does not
block it.

For session-preserving chat gateways, Zonta sends `X-Hermes-Session-Id` on each
turn and adopts the returned id. A `409 permission_denied` response clears the
id and retries with a new one.

## License

Apache License 2.0. See [LICENSE](LICENSE).
