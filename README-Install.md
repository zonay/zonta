# Zonta — Installation and Quick Start

Zonta is a macOS menu-bar application for dictation, spoken question answering
and translation. Speech recognition, language processing and speech synthesis
are performed by services configured by the administrator; the local
workstation handles only audio capture, text insertion and playback.

## 1. Installation

1. Move `Zonta.app` to the Applications folder. The supplied
   `Install to Applications.command` performs this step and opens the
   application.
2. On first launch, grant the three requested permissions:
   - **Microphone** — audio capture during dictation.
   - **Accessibility** — modifier monitoring, text field detection and text
     insertion.
   - **Local Network** — communication with the configured services.
3. Quit and reopen the application after granting the permissions.

If macOS reports that the application cannot be opened, right-click it and
select **Open**. The bundle is signed but not notarized, so Gatekeeper requests
this confirmation once per workstation.

## 2. Service configuration

Zonta does not include models or credentials. Click the menu-bar item, then
configure the five service tabs — Dictation, Cleanup, Chat, Translate and
Speech — with the endpoints, credentials and models used in your environment.
The shipped addresses are loopback placeholders and must be replaced. Each tab
provides a connectivity test.

## 3. Operation

| Modifier | Operation |
| --- | --- |
| Globe (`fn` on legacy keyboards) | Ask a question aloud; the answer is spoken and retained in the review panel |
| Right Command | Dictate; the text is inserted at the cursor |
| Right Option | Dictate; the translation is inserted at the cursor |

Hold the modifier briefly before speaking; a short tap is ignored. Left Command
and left Option are not intercepted, so standard shortcuts and accented
characters continue to work.

If the chat service preserves conversations, the following question retains
the context of the previous one. The Chat tab displays the active session
identifier and provides a **New conversation** control.

## 4. Interface

Click the menu-bar item to open Settings. Right-click it for a context menu
providing the review panel, application log, Settings, a speech output toggle
and Quit. The settings window displays the current state, the last error and a
**Quit Zonta** control.

## 5. Requirements

macOS 14 or later. No additional runtime software is required.

## 6. Package contents

| File | Purpose |
| --- | --- |
| `Zonta.app` | Signed application bundle |
| `Zonta.zip` | Archive preserving the signature, for transfer |
| `Install to Applications.command` | Copies the application to Applications and opens it |
| `Read Me First.md` | This document |

## 7. License

Licensed under Apache License 2.0. Refer to the LICENSE file in the source
repository.
