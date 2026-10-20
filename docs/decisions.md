# Decisions

Updated: 2026-10-20

## Agreed with the user

- Name: Transcribe; repository `~/src/transcribe`.
- Target hardware: M1 and newer Macs.
- Include microphone recording and speaker identification from the first usable version, alongside file import, review and export.
- Carry over Disk Assessment's standalone app, simple build/run workflow and focused interface. Use native SwiftUI here.
- Support Swedish and English, potentially mixed; offer a language list.

## Implementation choices

- macOS 15 minimum and Swift 6.2+ development toolchain, enabling modern SwiftUI and the SDK's default quantized speaker models.
- Argmax OSS Swift v1.1.1; only WhisperKit and SpeakerKit linked.
- Compressed Whisper large-v3 Turbo (`large-v3-v20240930_626MB`) for the app. Tiny only for the development probe.
- Explicit model/tokenizer preparation from Hugging Face with local caches. No bundled weights or audio uploads.
- Original audio, editable segments, speaker names and engine-private alignment evidence in Application Support.
- SDK word alignment where it preserves source text; whole-segment fallback when word evidence is absent or incomplete. Keep edits when adding speakers later.
- Save transcription before diarization. Preserve saved work on cancellation/failure.
- Automatic decoding avoids a forced detected-language prompt: the latter incorrectly converted English turns to Swedish in our synthetic Turbo fixture. An explicit language selection still prefills that language.
- Optional expected speaker count; names apply within a recording. Clear names when re-clustering because IDs are not stable identities.
- Default microphone recorded to AAC/M4A, then transcribed after stopping. No system audio, streaming or cross-meeting recognition in v0.1.
- Local ad-hoc signed bundle and make build/run/check workflow. Developer ID signing/notarization remain distribution work.

## Remaining validation

- Natural mixed-language meetings and overlapping voices.
- M1 performance and long recordings, especially 8 GB machines.
- Physical microphone permission/recording lifecycle and playback on target Macs.
- Broader distribution requirements.

## Primary sources

- https://github.com/argmaxinc/argmax-oss-swift/tree/v1.1.1
- https://huggingface.co/argmaxinc/whisperkit-coreml
- https://huggingface.co/argmaxinc/speakerkit-coreml

Sources checked 2026-10-20. Upstream prerequisites vary across README sections and package manifests; our minimum versions above are explicit choices. Actual checks are recorded in validation.md.
