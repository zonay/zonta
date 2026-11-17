# Zonta — Voice Input and Voice Assistant for macOS

Zonta is a macOS menu-bar application that provides hold-to-talk dictation,
spoken question answering and translation. Audio capture, insertion and
playback occur on the local workstation; speech recognition, language
processing and speech synthesis are delegated to administrator-configured
OpenAI-compatible HTTP services.

The application contains no bundled models and no credentials. All service
endpoints, API keys, models and prompts are supplied at configuration time.

## Contents

1. [Overview](#1-overview)
2. [Capabilities](#2-capabilities)
3. [Architecture](#3-architecture)
4. [System requirements](#4-system-requirements)
5. [Installation and build](#5-installation-and-build)
6. [Configuration](#6-configuration)
7. [Contributing](#7-contributing)
8. [License](#8-license)

---

## 1. Overview

Zonta is operated with three hold-to-talk modifiers. A modifier must be held
briefly before it is recognized; a short tap is discarded. This prevents
incidental input from starting a recording, and prevents Option-based
accented-character entry from being interpreted as a command.

| Modifier | Operation | Output |
| --- | --- | --- |
| Globe (`fn` on legacy keyboards) | Spoken question answering | Synthesized speech; the answer is also retained in a review panel |
| Right Command | Dictation | Cleaned transcript inserted at the text cursor |
| Right Option | Translation | Translated transcript inserted at the text cursor |

Left Command and left Option are not intercepted. Standard keyboard shortcuts
and accented-character entry therefore remain unaffected.

## 2. Capabilities

- **Hold-to-talk input.** Recognition begins only after a 250 ms hold threshold
  and requires at least 0.6 s of captured audio. A subsequent keystroke during
  the hold cancels the pending operation.
- **Context-preserving insertion.** The application records the process that
  was frontmost when the modifier was pressed. Text is inserted through that
  process's native Edit → Paste command (identified by its ⌘V command
  character, so localized menus are supported), with a direct Accessibility
  text-insertion fallback. Text is also written to the clipboard.
- **Independent language services.** Cleanup, chat and translation each have
  their own endpoint, credential, model and prompt. They may be hosted on
  different servers.
- **Conversational voice chat.** When the chat endpoint is a session-preserving
  agent gateway, Zonta maintains conversation continuity by round-tripping the
  `X-Hermes-Session-Id` header. A plain chat-completions endpoint requires no
  session state.
- **Asynchronous execution.** Transcription, language processing and speech
  playback run in independent serial queues. A slow language-model request does
  not block dictation, and a new recording does not wait for a previous job.
- **Operational visibility.** A settings window reports current state and the
  last error. An application log and a live job queue support diagnosis, and
  a review panel retains recent spoken answers.

## 3. Architecture

```
                         local workstation                    configured services
┌───────────────────────────────────────────────────┐   ┌──────────────────────┐
│ modifiers → recorder → 16 kHz mono PCM WAV        │   │ transcription service│
│                          │                        │──►│ /audio/transcriptions│
│                          ▼                        │   ├──────────────────────┤
│            transcription → language processing ───┼──►│ chat-completions     │
│                          │                        │   │ endpoint(s)          │
│              ┌───────────┴───────────┐            │   ├──────────────────────┤
│              ▼                       ▼            │──►│ speech synthesis     │
│      clipboard + insert       speech playback     │   │ /audio/speech        │
└───────────────────────────────────────────────────┘   └──────────────────────┘
```

All outbound HTTP requests are issued through `/usr/bin/curl`. Local Network
Privacy can report a blocked application socket as a missing Internet
connection; the system `curl` is not subject to that restriction.

## 4. System requirements

| Requirement | Detail |
| --- | --- |
| Operating system | macOS 14 or later |
| Build toolchain | Xcode command-line tools (`swiftc`); no Xcode project is required |
| Permissions | Microphone, Accessibility, Local Network |
| Services | OpenAI-compatible transcription, chat-completions and audio-speech endpoints |
| Runtime dependencies | None; the application uses frameworks supplied by macOS |

## 5. Installation and build

### 5.1 Building from source

```bash
git clone <repository-url>
cd zonta
./run.sh
```

`build.sh` compiles the Swift sources into `build/Zonta.app`, generates the
application icon and signs the bundle. `run.sh` invokes `build.sh` and launches
the result. Build artifacts under `build/` are excluded from version control.

A one-pixel window is presented at launch because the application must be a
regular foreground app rather than a background agent. It may be closed
immediately; the menu-bar item remains available.

### 5.2 Code signing

A stable signing identity is recommended. Without one, an ad-hoc signature is
used, and macOS treats each rebuild as a new application, requiring the
permissions to be granted again.

```bash
./build.sh                                   # ad-hoc signature
./build.sh 'Developer ID Application: ...'   # explicit identity
SIGN_IDENTITY='Apple Development: ...' ./build.sh
```

The identity must exist in the login keychain. An ad-hoc build is suitable for
local development only.

### 5.3 Distributable bundle

```bash
./package.sh 'Developer ID Application: ...'
```

The command writes the following to `~/Desktop/Zonta/`:

| Artifact | Purpose |
| --- | --- |
| `Zonta.app` | Signed application bundle |
| `Zonta.zip` | Archive preserving the signature, for transfer |
| `Install to Applications.command` | Copies the bundle to Applications and opens it |
| `Read Me First.md` | End-user installation guide |

A Developer ID signature is required for distribution to other workstations;
an Apple Development certificate is not trusted outside the development
machine. Notarization is optional. Set `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` and
`NOTARY_PASSWORD` to submit the archive, staple the ticket and suppress the
Gatekeeper override prompt.

## 6. Configuration

### 6.1 Settings interface

Click the menu-bar item to open Settings. Right-click it for a context menu
providing the review panel, application log, Settings, a speech output toggle
and Quit. Changes are persisted automatically. **Reset to defaults** restores
default values and clears the current chat conversation.

| Tab | Configuration |
| --- | --- |
| Dictation | Transcription endpoint, credential, model, language |
| Cleanup | Cleanup language model, credential, prompt, reasoning controls |
| Chat | Conversational endpoint, credential, prompt, session identifier |
| Translate | Translation endpoint, credential, prompt, reasoning controls |
| Speech | Speech endpoint, credential, model, voice, language, spoken-output toggle |

Each tab provides a connectivity test. The cleanup, chat and translation
configurations are independent and may reference different hosts.

### 6.2 Service endpoints

The shipped values are placeholders using loopback addresses. They must be
replaced with the addresses of the deployed services before use. No API keys
are included in the source distribution; credentials are entered by the
administrator through Settings.

| Service | Endpoint | Default model |
| --- | --- | --- |
| Transcription | `http://localhost:6667/v1` | `whisper-large-v3-turbo` |
| Cleanup | `http://localhost:1235/v1` | `google/gemma-4-12b-qat` |
| Chat | `http://localhost:8642/v1` | `hermes-agent` |
| Translation | `http://localhost:1235/v1` | `google/gemma-4-12b-qat` |
| Speech | `http://localhost:7788/v1` | `supertonic-3` |

| Service | Request | Notes |
| --- | --- | --- |
| Transcription | `POST /v1/audio/transcriptions` | Multipart `file`, `model`, `response_format=json`, optional `language` |
| Language model | `POST /v1/chat/completions` | Temperature `0.2`; zero-reasoning controls enabled by default |
| Speech | `POST /v1/audio/speech` | `model`, `input`, `voice`, `response_format=wav`, optional `lang` |

The voice identifier is passed to the speech service verbatim. Administrators
must supply a name supported by their speech service.

### 6.3 Prompts

| Prompt | Function |
| --- | --- |
| Cleanup | System message that normalizes punctuation, capitalization and recognition errors without adding content or answering the text |
| Chat | System message governing spoken answers; concise plain language is required because the response is synthesized |
| Translate | System message specifying the target language; the dictated text is supplied as the user message |

An empty cleanup prompt disables cleanup and inserts the raw transcription.
An empty chat or translation prompt selects a built-in fallback.

### 6.4 Conversation continuity

Session-preserving chat gateways store the conversation on the server and
continue it only when the client returns the issued session identifier.
Zonta generates a `zonta-<uuid>` identifier for the first question, transmits
it in `X-Hermes-Session-Id` on subsequent turns, and adopts any rotated
identifier returned in the response. A `409 permission_denied` response causes
the identifier to be discarded and the request to be retried with a new one.
The Chat tab displays the active identifier and provides a **New conversation**
control.

## 7. Contributing

Issues and pull requests are welcome. Changes should preserve the existing
module boundaries in `Zonta/`, and build scripts must remain usable without
organization-specific signing identities. By contributing, you agree that your
contribution is licensed under Apache License 2.0.

## 8. License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
