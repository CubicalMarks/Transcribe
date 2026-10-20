# Transcribe

A planned lightweight, local macOS transcription app. Working name: **Transcribe**.

## Status

Repository initialized for requirements and engine validation. No application or build targets exist yet.
The supplied [original proposal](docs/original-proposal.md) is preserved as a design input; its technical and licensing claims are not acceptance criteria or verified behavior.

## Proposed direction

- A standalone Mac app with a focused interface and a simple local build/run workflow, in the spirit of Disk Assessment.
- SwiftUI and AVFoundation, with WhisperKit and optional SpeakerKit evaluated for local inference.
- Audio stays on the Mac for processing; model downloads require an initial network connection.
- Validate transcription and speaker attribution on representative Swedish/English audio before building out the interface.

See [the initial decisions and open questions](docs/decisions.md). Scope, hardware targets and distribution are awaiting clarification.
