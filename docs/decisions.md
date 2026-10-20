# Initial decisions and open questions

Date: 2026-10-20

## Requested

- Create a separate repository under `~/src/`.
- Explore a local macOS transcription app based on the supplied proposal.
- Use Disk Assessment as a reference for the outset and ask questions before settling implementation choices.

## Provisional

- Working name and directory: Transcribe, `~/src/transcribe`.
- Native SwiftUI interface; carry over Disk Assessment's standalone utility approach and simple build workflow.
- Evaluate the open-source WhisperKit and SpeakerKit libraries from the Argmax Swift SDK.

## Open

1. First usable scope: file import/transcription/export, speaker identification, microphone recording and review features.
2. Whether similarity to Disk Assessment includes its WebKit interface technology or only its packaging, focus and workflow.
3. Target Mac hardware/macOS, personal use versus sharing, and final name.
4. Representative audio, typical recording duration, language mix and acceptable speaker/transcription quality.
5. Project storage, model download behavior and distribution details once the first scope is agreed.

## Validation before implementation commitment

- Pin an SDK release and check the selected products' platform/toolchain requirements.
- Confirm model availability, download/access conditions, licensing and offline cache behavior.
- Run a small end-to-end audio prototype; record accuracy observations, elapsed time and memory on target hardware.
- Compare speaker alignment against audio, including turns inside transcription segments and overlaps.

## Current source check

The Argmax repository currently documents WhisperKit and SpeakerKit as separate products in one Swift package, with macOS 14+ and Xcode 16+ prerequisites. This confirms a plausible integration path, not local build compatibility or inference quality.

Source: https://github.com/argmaxinc/argmax-oss-swift (checked 2026-10-20).
