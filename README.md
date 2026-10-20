# Transcribe

A focused macOS app for local transcription and speaker identification. Built with SwiftUI, AVFoundation, WhisperKit and SpeakerKit. Import audio, record the microphone, review editable transcripts alongside playback, and export Markdown, plain text or JSON.

## Build and run

Requirements: Apple Silicon (M1 or newer), macOS 15+, and Xcode with Swift 6.2+ for development. Source checks additionally use Python 3. The built app needs no Python, Node, ffmpeg, Homebrew or external transcription executable.

```sh
make check
open dist/Transcribe.app
```

`make build` creates an arm64 release app with an icon, microphone permission metadata, dependency notices and an ad-hoc signature. `make run` builds and opens it. This is a local build, not a Developer ID signed/notarized distribution.

## Usage

1. Open **Models**, then **Download & Prepare**. Downloads include compressed Whisper large-v3 Turbo, its tokenizer and optional SpeakerKit models from Hugging Face. First-time Core ML preparation can take several minutes. Prepared files are reused offline.
2. Open/drop audio, or choose **Record**. Imports are copied into the library. AVFoundation supports common M4A, AAC, MP3 and WAV files. Recording uses the default microphone and supports pause/resume. **Stop & Save** keeps audio; **Stop & Transcribe** saves it and starts processing, or opens model setup if needed.
3. Choose **Automatic**, **Swedish**, **English**, or another supported language from the list. Automatic is the starting point for mixed recordings; language switches need review. Choosing a language guides transcription, not translation.
4. Optionally enable **Identify speakers**, with automatic detection or an expected count. Transcription is saved before speaker identification. Speakers can also be identified later without repeating transcription.
5. Play/scrub audio or click a timestamp. Edit text, assign an existing speaker label and rename speakers. Changes save locally. **Export** provides copy, TXT, Markdown and JSON.

Cancellation keeps saved audio and the last saved transcript; controls remain busy until the engine returns. Rerunning transcription asks before replacing edits. Rerunning speakers preserves edited text but clears names because cluster IDs may change. Labels are estimates within one recording, not recognition of named people across recordings.

## Local data

Stored under `~/Library/Application Support/Transcribe/`:

```text
Projects/<UUID>/audio.<extension>    Original imported/recorded audio
Projects/<UUID>/transcript.json     Text, names and alignment evidence
Models/                            Weights, tokenizer and installation records
```

**Show Local Library** in the app menu opens projects; **Models → Show Local Storage** opens the parent folder. Audio is saved before inference. No audio or transcripts are uploaded; there is no telemetry, subscription or cloud inference. First-time model/tokenizer preparation needs internet. JSON exports omit internal alignment evidence.

Microphone permission is requested when you choose Record. System/call audio and live transcription are outside v0.1. Recordings are unencrypted local files. Private audio, transcripts, weights and exports must stay out of Git; build output and named local-data directories are ignored, but exports elsewhere need care before staging.

## Development

| Command | Purpose |
| --- | --- |
| `make build` | Build/sign `dist/Transcribe.app` |
| `make run` | Build and open the app |
| `make lint` | Shell/config/package syntax and source whitespace |
| `make test` | Preservation, storage and export tests; no model downloads |
| `make check` | Lint, release packaging and tests |
| `make probe` | Headless inference validation command usage |

Actual inference with a separate library/cache:

```sh
swift run transcribe-probe --audio /path/to/audio.m4a \
  --root /tmp/transcribe-validation --prepare --speakers --language auto
```

`--prepare` enables model downloads; omit it to reuse installed models. `--model tiny` selects a development model. The app uses compressed Turbo. Probe output contains transcript text; use synthetic audio or an explicitly approved fixture. See [validation](docs/validation.md) for checked behavior and limits.

```text
Sources/Transcribe/             Window, recording, playback and app lifecycle
Sources/TranscribeCore/         Transcript/storage and inference interfaces
Sources/TranscribeProbe/        Real-model validation command
Tests/TranscribeCoreTests/      Deterministic preservation tests
resources/                     Bundle metadata, entitlements and attribution
scripts/                       Build/signing, icon generation and checks
```

Argmax OSS Swift is pinned at v1.1.1; Package.resolved locks dependency resolution. Only WhisperKit and SpeakerKit are linked; no server or TTS product. Transcription decodes incrementally with one worker. Speaker inference uses two workers and currently loads 16 kHz mono audio in memory. Long recordings need memory/performance validation, particularly on 8 GB M1 Macs.

Read [AGENTS.md](AGENTS.md) and [decisions](docs/decisions.md) before editing. The [original proposal](docs/original-proposal.md) is preserved as context, including unverified claims. [ThirdPartyNotices](resources/ThirdPartyNotices.md) and bundled SDK license texts cover attribution.
