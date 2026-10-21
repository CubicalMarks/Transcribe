# Transcribe

A focused macOS app for local transcription and speaker identification. Built with SwiftUI, AVFoundation, WhisperKit, FluidAudio and SpeakerKit. Import audio, record the microphone, review editable transcripts alongside playback, create LLM summaries, and export Markdown, plain text or JSON.

## Build and run

Requirements: Apple Silicon (M1 or newer), macOS 15+, and Xcode with Swift 6.2+ for development. Source checks additionally use Python 3. The built app needs no Python, Node, ffmpeg, Homebrew or external transcription executable.

```sh
make check
open dist/Transcribe.app
```

`make build` creates an arm64 release app with an icon, microphone permission metadata, dependency notices and a code signature. It signs a fresh bundle and swaps it into `dist/Transcribe.app`, preserving the previous bundle in `.build/app-stage.*` so an open app's executable is never overwritten. Reopen the app to use the new build. `make run` builds and opens it. By default the signature is ad-hoc. For regular use, select an existing code-signing certificate by putting its SHA-1 fingerprint on a single line in `.signing-identity` (ignored by Git), or set `CODE_SIGN_IDENTITY` for that build. `security find-identity -v -p codesigning` lists available certificates. The environment variable takes precedence; use `CODE_SIGN_IDENTITY=-` for a disposable ad-hoc build. A configured signing failure stops the build; it never silently falls back to ad-hoc signing.

Use the same certificate and bundle identifier across updates so Keychain can recognize the app. Ad-hoc builds have a hash-based identity and can repeatedly request access; Always Allow does not provide a reliable update workflow for those builds. Switching from ad-hoc to certificate signing can require approving existing credentials once. This remains a local build without notarization; a certificate signature alone does not establish distribution readiness.

## Usage

1. Open **Settings → Local Models** (or the toolbar’s **Models** shortcut), choose a default model, a Swedish override if wanted, and a new-recording language preference, then **Prepare Configured Models**. **Whisper Turbo** is the default for multilingual recordings; **Pianissimo Swedish (experimental)** uses a community Core ML 8-bit conversion through FluidAudio. SpeakerKit is prepared separately when **Prepare speaker identification too** is enabled. First-time Core ML preparation can take several minutes. Prepared files are reused offline.
2. Open/drop audio, or choose **Record**. Imports are copied into the library. AVFoundation supports common M4A, AAC, MP3 and WAV files. Recording uses the default microphone and supports pause/resume. **Stop & Save** keeps audio; **Stop & Transcribe** saves it and starts processing, or opens model setup if needed.
3. Choose **Automatic**, **Swedish**, **English**, or another supported language for the recording. The model follows your rules in Local Models: the Swedish override is used only for Swedish, while Automatic and other languages use the multilingual default. Automatic is the starting point for mixed recordings; language switches need review. Choosing a language guides transcription, not translation.
4. Optionally enable **Identify speakers**, with automatic detection or an expected count. Transcription is saved before speaker identification. Speakers can also be identified later without repeating transcription.
5. Play/scrub audio or click a timestamp. Edit text or assign an existing speaker label; changes save locally. Use **Speaker Names…** to edit names, then **Save Names** to apply them together; **Cancel** discards that name draft. **Export** provides copy, TXT, Markdown and JSON.

Right-click a recording for **Rename…** or **Move to Trash…**. The same actions are in the File menu (**⇧⌘R** to rename, **⌘⌫** to trash); the sidebar also has a Trash button for the selected recording. Deletion asks for confirmation and moves the entire project folder, including saved audio, transcript and summary, to the Mac’s Trash. Imported source files and downloaded models remain in place. To restore, move the UUID-named project folder from Trash back into the Projects folder opened by **Show Local Library**, then reopen the app. These actions are disabled during recording/processing or while edits have not saved successfully.

The recording options keep language, speaker identification and expected speaker count together; they wrap into two rows when space is tight. Hover over these controls for language and speaker guidance.

Local Models saves a multilingual default (currently Whisper Turbo), with **Use default**, Whisper or Pianissimo as the Swedish rule. **New recording language** starts with **Remember last selected**; you can instead choose Automatic or a fixed language. New imports and microphone recordings store that choice individually, so changing the default does not change their saved selection. Manually choosing a language also updates the remembered choice. The previous global Pianissimo selection migrates to a Swedish override and a remembered Swedish language. The language picker's help shows the model for the current selection.

Readiness is shown per configured model and independently for SpeakerKit. Preparing configured models downloads the default, overrides and optionally speaker models; transcription itself requires only the model for the selected language and any enabled speaker models. Pianissimo downloads about 632 MB from a pinned community conversion, verifies file sizes and available weight checksums, and records readiness only after loading the exact local components. Its decoder works in 15-second windows for longer audio. This is not Klang's official MLX implementation; its reported MLX speed/accuracy and phrase boosting do not carry over as validated features. Custom vocabulary is not exposed. Natural Swedish meetings, overlap and code-switching still need evaluation; Whisper remains the default.

During transcription, a read-only live preview shows completed sections with timestamps. Loading the model has its own status; audio-position progress advances as decoded sections finish, then speaker identification runs as a separate stage. This is progress through the recording, not a wall-clock ETA. Transcription exports become available when the new text is saved. Cancellation or failure discards the temporary preview and keeps the last saved transcript and audio; controls remain busy until the engine returns. Rerunning transcription asks before replacing edits. Rerunning speakers preserves edited text but clears names because cluster IDs may change. Labels are estimates within one recording, not recognition of named people across recordings. Background voices can produce additional labels. Setting a fixed count changes clustering; it does not isolate the foreground participants or remove background speech.

Transcription saves the speech model’s output directly, without automatic text cleanup or paragraph joining. Existing transcripts and edits remain as saved; legacy private original-text backups are retained in project storage and excluded from exports.

## Summaries

Open a recording's **Summary** tab. Both tabs share the recording header, playback, options area, export bar and scrollable text layout. Summary options sit in the same place as transcription options, above the tabs. Preset and language stay together, with extra instructions below and a compact destination indicator. The gear opens provider configuration. **Transcribe → Settings…** (**⌘,**) now contains two pages: **Local Models** for transcription/speaker models and storage, and **Summarisation** for on-device, ChatGPT and API summary providers. Choose a provider on the Summarisation page. Choose **Summarise** in the empty summary view, or **Regenerate Summary…** at the bottom of saved notes.

- **On this Mac** uses Apple's Foundation Models on-device model. Requires macOS 26+ and Apple Intelligence enabled with its model ready. The pane explains why it is unavailable when those requirements are not met. Transcription and API summaries still work on macOS 15+.
- **ChatGPT plan** lets you choose **Continue with ChatGPT**, complete browser sign-in, and approve plan usage for an eligible Plus or Pro account. Select an available model, then **Save Changes**. You can keep multiple account/workspace connections, reconnect a saved registration or sign out. **Manage ChatGPT Usage** opens your account's app limits. Usage comes from your existing plan or available credits; it never falls back automatically to API billing.
- **OpenAI API** fills in `https://api.openai.com/v1`, the `gpt-5.4-mini` model and `max_completion_tokens`. Enter your API key in Settings; the model remains editable.
- **Custom API** uses an OpenAI-compatible Chat Completions endpoint. Enter its base URL, model identifier and optional API key in Settings. Existing custom configurations are retained when upgrading. No external provider is enabled automatically. The destination is shown in the summary pane. HTTPS is required remotely; HTTP is allowed for loopback servers. Redirects are rejected.
- Presets: **Meeting notes** (short overview, detailed topic sections and useful takeaways/follow-ups), **Brief overview**, and **Action items**. Owners and deadlines are included only when stated. Choose source language, English or Swedish, with optional extra instructions.
- Meeting notes preserve concrete requirements, rationale, workflow order, dependencies, priorities and handoffs, while distinguishing decisions from suggestions and unresolved choices. Length follows the material: a substantive meeting may need 400–700 words; short conversations stay shorter. Brief overview and Action items retain their compact 220-word guidance. No meeting-specific terms or private reference text are embedded in the prompt.
- Long transcripts are processed in sections and their notes combined in stages. The full source is processed, with larger intermediate note budgets for Meeting notes; repeated reductions can still lose detail, particularly with the smaller on-device context. Generated notes remain lossy summaries and require review. If a stage fails or is cancelled, the previous saved summary remains.
- Summary text uses the same growing plain-text editor, 16-point font and line spacing as transcript text. Supporting labels use standard 13-point text. Edits save with the recording, and the active tab determines the copy/export choices. A changed transcript or speaker name marks it outdated. Regeneration asks before replacing existing summary edits.

ChatGPT access/refresh/ID tokens are held in macOS Keychain in separate records for each verified account registration. Tokens refresh near expiry. Signing out attempts remote session revocation and clears local tokens while retaining the registration for reconnecting. Temporary network failures preserve the connection; revoked/expired refresh credentials require signing in again. Cancel stops an unfinished sign-in; successfully connected accounts are retained even if you cancel the provider draft. If registration succeeded but code exchange was interrupted, **Retry Previous Sign-in** reuses its issued client ID.

API keys live in macOS Keychain per API URL, outside project files, exports and UserDefaults. Settings shows whether a key is saved for that URL without loading its value. OpenAI API mode requires a saved API key before any transcript request is sent; a rejected key produces a specific authentication error directing you to Settings. A blank key field preserves a saved credential; **Remove saved key** deletes it on Save. API URL/model and preset preferences are stored in application preferences. Settings → **Summarisation → Advanced** contains the token-limit parameter and output-token budget. Custom APIs initially use `max_tokens`; the OpenAI preset selects `max_completion_tokens`. Choose the parameter your provider/model requires. The configurable output-token budget defaults to 4096 and also covers reasoning tokens on providers that count those against the limit. A response ending because of a token limit or refusal is rejected rather than saved as a complete summary. Endpoint support follows the standard text Chat Completions schema; provider-specific protocols are not covered.

## Local data

Stored under `~/Library/Application Support/Transcribe/`:

```text
Projects/<UUID>/audio.<extension>    Original imported/recorded audio
Projects/<UUID>/transcript.json     Text, names and alignment evidence
Models/                            Weights, tokenizer and installation records
```

**Show Local Library** in the app menu opens projects; **Settings → Local Models → Show Local Storage** opens the parent folder. Audio is saved before inference. Audio is never uploaded. On-device summaries keep transcript text on the Mac; ChatGPT plan summaries send transcript text to OpenAI, and API summaries send it to the endpoint you configure, when you choose Summarise. ChatGPT sign-in/model discovery makes account requests but does not send transcripts. Plan summaries use the public streaming Responses API with storage disabled. Streamed text is accumulated across text/content/message events, finalized without duplication and saved only after completed inference; an empty terminal snapshot does not discard text already received. There is no telemetry or app subscription; the selected ChatGPT plan or API provider's usage limits, charges and data policies apply. First-time transcription model/tokenizer preparation needs internet. JSON exports omit internal alignment evidence and include any saved summary.

Microphone permission is requested when you choose Record. System/call audio and live microphone transcription while recording remain outside the current scope. Saved recordings and imported files show preview sections while being transcribed. Recordings are unencrypted local files. Private audio, transcripts, weights and exports must stay out of Git; build output and named local-data directories are ignored, but exports elsewhere need care before staging.

## Development

| Command | Purpose |
| --- | --- |
| `make build` | Build/sign `dist/Transcribe.app` |
| `make run` | Build and open the app |
| `make lint` | Shell/config/package syntax and source whitespace |
| `make test` | Preservation, storage, export and native-editor tests; no model downloads |
| `make check` | Lint, release packaging and tests |
| `make probe` | Headless inference validation command usage |

Actual inference with a separate library/cache:

```sh
swift run transcribe-probe --audio /path/to/audio.m4a \
  --root /tmp/transcribe-validation --prepare --speakers --language auto
```

`--prepare` enables model downloads; omit it to reuse installed models. `--model tiny` selects a development Whisper model. Probe output contains transcript text; use synthetic audio or an explicitly approved fixture. Test Pianissimo with a separate library:

```sh
swift run transcribe-probe --audio /path/to/synthetic-swedish.wav \
  --root /tmp/transcribe-pianissimo --engine pianissimo --language sv --prepare --speakers
```

`--engine` defaults to `whisper`. Pianissimo requires `--language sv` and rejects `--model`; its model revision is pinned. Omit `--speakers` to test transcription alone. See [validation](docs/validation.md) for checked behavior and limits.

Compare speaker settings against an explicitly selected saved transcript and its adjacent source audio:

```sh
swift run transcribe-probe --compare-speakers \
  --transcript /path/to/private-library/Projects/UUID/transcript.json \
  --root /path/to/private-library --output /path/to/private-comparison
```

This reuses prepared SpeakerKit models and writes private transcripts/turn evidence for Automatic, two speakers, clustering thresholds 0.5/0.7 and a 0.2-second segment-gap experiment. It never downloads models or uploads audio/text. Add `--reuse-evidence /path/to/private-comparison` with a **different output directory** to replay alignment without inference; replay durations are zero, not inference timings. Use ignored private directories for all outputs. See [speaker evaluation](docs/speaker-evaluation.md) for the measured result and its accuracy limits.


```text
Sources/Transcribe/             Window, recording, playback and app lifecycle
Sources/TranscribeCore/         Transcript/storage and inference interfaces
Sources/TranscribeProbe/        Real-model validation command
Tests/TranscribeCoreTests/      Deterministic preservation tests
Tests/TranscribeAppTests/       Native editor, document layout, binding and undo tests
resources/                     Bundle metadata, entitlements and attribution
scripts/                       Build/signing, icon generation and checks
```

Argmax OSS Swift is pinned at v1.1.1; only its WhisperKit and SpeakerKit products are linked. FluidAudio is pinned at c79c4106b954f81205113c3343e5a7e59a1089b5 with TTS, FluidAudio diarization and NeMo text-processing traits disabled. Package.resolved locks dependency resolution. Both transcription engines use one worker and support bounded audio conversion for longer files. Speaker inference uses two workers and currently loads 16 kHz mono audio in memory. Long recordings need memory/performance validation, particularly on 8 GB M1 Macs.

Read [AGENTS.md](AGENTS.md) and [decisions](docs/decisions.md) before editing. The [original proposal](docs/original-proposal.md) is preserved as context, including unverified claims. [ThirdPartyNotices](resources/ThirdPartyNotices.md) and bundled SDK license texts cover attribution.

For a fixed synthetic summary smoke test (no personal audio/text):

```sh
swift run transcribe-probe --summary-demo
swift run transcribe-probe --summary-demo --summary-api http://127.0.0.1:PORT/v1 --summary-model MODEL
```

The first command needs Apple's on-device model available. The second sends only the built-in synthetic fixture; an optional credential can be supplied via `TRANSCRIBE_SUMMARY_API_KEY`. Do not print real credentials or commit them. UI checks can use `TRANSCRIBE_LIBRARY_PATH` to point the app at a separate fixture library; use a separately identified QA bundle to isolate application preferences too.

ChatGPT sign-in follows the official [local-app OAuth flow](https://developers.openai.com/siwc/token-sharing-open-source/sign-in), with [account-specific models and streaming Responses](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference). This is intended for this local personal app; paid or remotely hosted distribution requires reviewing OpenAI's integration eligibility. Real account consent and hosted summary quality still require a user-completed sign-in and validation.
