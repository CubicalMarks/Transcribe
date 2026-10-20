# Transcribe

A focused macOS app for local transcription and speaker identification. Built with SwiftUI, AVFoundation, WhisperKit and SpeakerKit. Import audio, record the microphone, review editable transcripts alongside playback, create LLM summaries, and export Markdown, plain text or JSON.

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

## Summaries

Open a recording's **Summary** tab (or choose **Summarise…** below its transcript).

- **On this Mac** uses Apple's Foundation Models on-device model. Requires macOS 26+ and Apple Intelligence enabled with its model ready. The pane explains why it is unavailable when those requirements are not met. Transcription and API summaries still work on macOS 15+.
- **API endpoint** uses an OpenAI-compatible Chat Completions endpoint. Open **API Settings…** and enter the base URL, model identifier and optional API key. No provider is selected by default. The destination is shown beside the action. HTTPS is required remotely; HTTP is allowed for loopback servers. Redirects are rejected.
- Presets: **Meeting notes** (overview, decisions, actions, open questions), **Brief overview**, and **Action items**. Owners and deadlines are included only when stated. Choose source language, English or Swedish, with optional extra instructions.
- Long transcripts are processed in sections and their notes combined in stages. The full source is processed; generated notes remain lossy summaries and require review. If a stage fails or is cancelled, the previous saved summary remains.
- Summary text is editable, saved with the recording, and exportable/copyable from the Summary tab. A changed transcript or speaker name marks it outdated. Regeneration asks before replacing existing summary edits.

Keys live in macOS Keychain per API URL, outside project files, exports and UserDefaults. A blank key field preserves a saved credential; **Remove saved key** deletes it on Save. API URL/model and preset preferences are stored in application preferences. The default token-limit parameter is `max_tokens`; select `max_completion_tokens` when your provider/model requires it. The configurable output-token budget defaults to 4096 and also covers reasoning tokens on providers that count those against the limit. A response ending because of a token limit or refusal is rejected rather than saved as a complete summary. Endpoint support follows the standard text Chat Completions schema; provider-specific protocols are not covered.

## Local data

Stored under `~/Library/Application Support/Transcribe/`:

```text
Projects/<UUID>/audio.<extension>    Original imported/recorded audio
Projects/<UUID>/transcript.json     Text, names and alignment evidence
Models/                            Weights, tokenizer and installation records
```

**Show Local Library** in the app menu opens projects; **Models → Show Local Storage** opens the parent folder. Audio is saved before inference. Audio is never uploaded. On-device summaries keep transcript text on the Mac; API summaries send transcript text to the endpoint you configure, only when you choose API summarisation. There is no telemetry or app subscription; API provider charges and data policies apply. First-time transcription model/tokenizer preparation needs internet. JSON exports omit internal alignment evidence and include any saved summary.

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

For a fixed synthetic summary smoke test (no personal audio/text):

```sh
swift run transcribe-probe --summary-demo
swift run transcribe-probe --summary-demo --summary-api http://127.0.0.1:PORT/v1 --summary-model MODEL
```

The first command needs Apple's on-device model available. The second sends only the built-in synthetic fixture; an optional credential can be supplied via `TRANSCRIBE_SUMMARY_API_KEY`. Do not print real credentials or commit them. UI checks can use `TRANSCRIBE_LIBRARY_PATH` to point the app at a separate fixture library; use a separately identified QA bundle to isolate application preferences too.
