# Validation

Date: 2026-10-20. Host: Apple M5, 32 GB RAM, macOS 26.5.2, Xcode Swift 6.3.3. Target: arm64 macOS 15+.

## Deterministic checks

Final make check passed after the automatic-decoding and recording-interruption adjustments: six tests, shell/config/package checks, arm64 release build and strict ad-hoc signature verification. A repeated build exposed read-only copied notices; installing them with mode 0644 fixed repeat builds. Dynamic linkage was inspected and uses only macOS system frameworks/libraries.

Coverage: preserve absent/incomplete word-timing text and unassigned speech; round-trip edits/names/alignment evidence; private file permissions; JSON without internal evidence; path traversal rejection; Markdown without empty markup.

## Actual inference

Synthetic 44.4-second mono WAV generated locally with Alva (Swedish) and Daniel (English), alternating two turns twice. This is a pipeline fixture, not a natural-meeting accuracy benchmark.

- Tiny + SpeakerKit: 17 segments, two speakers, 4.36 seconds after model preparation.
- Both languages appeared, with transcription errors in tiny. Synthetic voices received separate labels.
- Downloads and first loads succeeded without a supplied Hugging Face token.
- Initial Turbo with explicit automatic language detection/prefill: two speaker IDs, but English turns were incorrectly rendered as Swedish. This configuration was rejected.
- Final Turbo Automatic behavior leaves the language prompt to the decoder instead of forcing the detected language. On the same fixture, Swedish and English text were both retained, with two speaker IDs and 14 segments.
- The final Turbo + SpeakerKit run completed under sandbox-exec with outbound networking denied and with no --prepare flag. This validates use of existing model/tokenizer files without a network connection for this fixture.
- That network-denied run took 107.62 seconds including model loading; the initial Turbo run took 8.95 seconds. Different Core ML cache/sandbox conditions make these unsuitable as a decoding-speed comparison. Tiny's 4.36-second measurement also includes loading after preparation. These are development-host observations, not M1 benchmarks.

## UI and packaging

- Initial arm64 release built and passed strict ad-hoc signature verification.
- Native model setup sheet visually inspected.
- Physical microphone capture and real meeting accuracy not independently validated. No private audio is part of the automated fixture.

## Limits

M1/8 GB performance is not established. Speaker inference retains decoded 16 kHz audio in memory. Cancellation inside third-party Core ML operations may take time to return. Developer ID/notarized distribution is not established.


## Summary feature validation — 2026-10-21

- `make check` passed with 12 tests, including all six existing transcription/storage tests. Summary coverage includes legacy decoding, saved summary round-trip/export, freshness after speaker-name edits, Unicode byte-bounded chunking with full tail preservation, staged processing of every source section, API URL validation, request shape/authentication/token-limit configuration, and rejection of truncated/refused replies.
- Real URLSession HTTP round-trip against a loopback-only synthetic server succeeded. Capture showed system/user text messages, the configured model, no audio, and no audio filename. Only a synthetic test credential was used; credential values were not written to capture logs.
- The same server returned an HTTP 302. The client rejected it, and capture confirmed no follow-up request to the redirect target.
- Local summary probe reported the real unavailable state: Apple Intelligence is disabled on this Mac. The system model reports English and Swedish support. No local generation quality claim is made, and no system setting was changed.
- Native summary pane was visually checked in a separate QA bundle with a synthetic-only project library and separate preference domain. Local/API controls, preset/language choices, destination disclosure and empty state were visible. No private recording was sent during agent validation. Keychain code compiled; a real-provider/key round-trip was not performed by the agent.
- Release app 0.2.0 passed strict ad-hoc signature verification. FoundationModels is weak-linked, preserving the macOS 15 deployment target for transcription/API summaries. Runtime behaviour on macOS 15 has not been physically tested.

Hosted endpoint compatibility and summary quality still need validation with the chosen provider/model. Native generation needs Apple Intelligence enabled and ready. Both backends produce lossy summaries that require review; transcript/export preservation checks are separate from model accuracy.


## Summary interface cleanup — 2026-10-21

- `make check` passed with 13 tests, release packaging and strict ad-hoc signature verification for app 0.2.1. Added coverage verifies legacy custom settings remain intact, explicit OpenAI defaults, settings round-trip, and preservation of preset/language/instructions.
- Visually inspected the compact summary pane and native Settings window in a separate preview bundle with a synthetic library and preference domain. Preset, language, action, collapsed instructions and destination were visible; provider/model/key and advanced options were in Settings.
- No hosted-provider generation or real credential validation was performed by the agent for this interface change. Existing inference/quality limitations above still apply.
