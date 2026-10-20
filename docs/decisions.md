# Decisions

Updated: 2026-10-21

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

## Summarisation (2026-10-21)

User requested selectable local/API summarisation, structured meeting notes by default, and several presets. The chosen API mode is a configurable OpenAI-compatible endpoint; no specific provider or real credentials were supplied.

- Native Apple Foundation Models for on-device summaries, gated by macOS 26+ and runtime model availability. This preserves the standalone app approach and does not raise the transcription/API macOS 15 minimum.
- Endpoint URL/model configurable; keys stored per canonical completion URL in Keychain. No automatic fallback or private transcript transmission during validation.
- Meeting notes, brief overview and action-item presets, with optional instructions and source/English/Swedish output.
- Byte-bounded section processing and staged reduction, without dropping the tail of long recordings. New summaries replace saved results only after successful completion.
- Optional summary field preserves old project compatibility. Source digest tracks text/speaker/timestamp changes; summary edits do not modify the transcript.
- URLSession uses an ephemeral session without cookies or cached credentials and refuses redirects. Provider HTTP errors are reported without echoing response bodies. Only completed nonempty text replies are saved.
- API documentation: https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
- Apple API documentation: https://developer.apple.com/documentation/foundationmodels

No live hosted-provider or local Apple Intelligence generation quality claim is made. The compatible HTTP path and disabled-model state were validated; see validation.md for final checks.


## Summary settings and interface (2026-10-21)

- Provider selection and API connection configuration live in the native Settings window, opened with ⌘, or the summary pane's Settings link. Models retains its own menu item without taking the Settings shortcut.
- Summary controls focus on preset, output language and generation; optional instructions are collapsed, with a compact destination disclosure below.
- Offer On this Mac, OpenAI and Custom API. Selecting OpenAI explicitly applies `https://api.openai.com/v1`, editable `gpt-5.4-mini`, `max_completion_tokens` and a 4096-token budget. Existing custom configurations decode as Custom API and remain unchanged until the user selects a different provider.
- Provider settings use a draft with Save/Cancel. Save preserves the current preset/language/instructions, and blank credentials preserve an existing key for that URL. Credentials typed for one URL are cleared when changing URLs.
- OpenAI preset sources checked: https://developers.openai.com/api/docs/models/gpt-5.4-mini and the Chat Completions reference above. This preset is an editable starting point, not a claim of live provider validation.


## Summary authentication diagnostics (2026-10-21)

- Prevent requests to api.openai.com when the trimmed key is empty, while retaining optional authentication for compatible custom servers.
- Distinguish HTTP 401 from general request/configuration failures; direct the user to check the provider's credential and API access in Settings. Do not expose provider response bodies, which may contain credentials.
- Show per-URL Keychain item presence in Settings using metadata only, without reading its value or opening an authentication prompt. A saved key is not presented as a validated key.


## ChatGPT plan connection (2026-10-21)

- Add ChatGPT plan as a separate provider alongside On this Mac, OpenAI API and Custom API. Existing API connection fields remain intact when switching modes.
- Direct browser OAuth: per-attempt PKCE/state/nonce, persistent UUID host ID, IPv4-loopback-only callback on an ephemeral port, five-minute deadline and cancellation. New registration uses dynamic_agent_client and Transcribe as the agent name; returning connections reuse the issued client ID. Interrupted new registrations retain their client ID for explicit retry.
- Validate RS256 ID-token signatures with JWTKit against the issuer's JWKS, and verify issuer, audience, expiry, issued-at/not-before, nonce and returning subject. Keep new sign-in separate until verified. Identity-only consent is retained but cannot generate summaries.
- Store separate client/subject credential records in a bundle-scoped Keychain document. Serialize refreshes, persist rotating credentials together, preserve credentials on temporary failures and clear only unusable token sets. Sign-out stops new plan requests, discovers and attempts session revocation, then clears local tokens while keeping account/client metadata. Report unconfirmed remote revocation.
- Discover visible models for the selected account. Send only text to the public Responses endpoint with store=false, stream=true, instructions and a full input array. Omit unsupported output-token-limit fields. Require response.completed with nonempty assistant text; discard incomplete, failed, refused or interrupted output without replacing saved notes. Never switch billing paths automatically.
- User completes browser authentication and consent. No real account credentials or private transcript are used by agent tests. Preserve the distinction between synthetic protocol validation and live account/model evidence.
- Sources: https://developers.openai.com/siwc/token-sharing-open-source/sign-in, /profiles-and-sessions, /models-and-inference, /preview-limitations and /errors-and-recovery (checked 2026-10-21). JWTKit 5.7.1 and dependency versions are locked in Package.resolved; their license/notice files are bundled.


## Shared transcript and summary layout (2026-10-21)

- User chose to retain two tabs with a shared layout, using the transcript UI as the design baseline.
- One recording layout owns title/metadata, playback, contextual options, the tab/export bar, scrolling content, empty states and bottom actions. Summary options move into the same header slot as transcription options.
- Both documents use the same growing plain-text field, 15-point type, line spacing and scroll-area margins. Keep transcript timestamp/speaker controls and summary generation metadata/staleness indicators contextual.
- Regeneration sits at the bottom like transcription reruns; first generation uses the same central empty-state action pattern. Remove the redundant Summarise shortcut under the transcript. Providers and credentials remain in native Settings.
- Data format, engine behavior, edit persistence and export formats remain unchanged. The active tab selects its own copy/export actions; regenerated summaries still require replacement confirmation.


## Transcription preview and progress (2026-10-21)

- Use WhisperKit's completed-segment discovery callback on the existing incremental-file pipeline. Keep decoding options and model selection unchanged; no microphone streaming was added.
- Relay read-only preview snapshots through a serialized, bounded AsyncStream. Each newest snapshot contains all discovered sections; finishing the reporter rejects late SDK callbacks, and the consumer drains before the engine returns.
- Track the furthest valid discovered timestamp against recording duration. Clamp progress to the audio bounds, keep it monotonic, and remain indeterminate when duration/decoded position is unavailable. Progress advances by sections; no invented ETA or elapsed-time percentage.
- Replace the idle empty state with loading/decoding status and preview text. Show percentages when available, live section count and distinct speaker-identification stages. Disable transcript export while the draft is displayed.
- Preview state never enters the saved Transcript. Publish the complete result only after successful transcription, then clear the preview before speaker identification. Cancellation/failure clears it and preserves prior saved text and edits.
- SDK contract inspected in the pinned v1.1.1 source: https://github.com/argmaxinc/argmax-oss-swift/blob/v1.1.1/Sources/WhisperKit/Core/WhisperKit.swift and Core/TranscribeTask.swift.


## ChatGPT stream text handling (2026-10-21)

- The previous parser ignored text delta/done events and extracted notes only from response.completed.output. This can incorrectly report an empty summary when the terminal event has a compact/empty output snapshot.
- Accumulate streamed output text by output/content position, replacing partial text with finalized text/content/message events instead of appending duplicates. Use a nonempty terminal assistant-text snapshot when present; otherwise retain the accumulated text after confirmed completion.
- Continue rejecting interrupted, failed, incomplete, refused and genuinely empty results. Do not collect reasoning text as notes. Bound accumulated text and include only event/item counts and a bounded request ID in empty-result diagnostics, never response text or credentials.
- The user's screenshot establishes an empty-result error after a completed response, but does not reveal the actual event sequence. Regression fixtures cover the confirmed parser gap; live account behavior remains separate validation.
- Sources: https://developers.openai.com/api/reference/resources/responses/streaming-events and OpenAI's reference stream implementation linked from https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt (checked 2026-10-21).


## Safe replacement of local app builds (2026-10-21)

- Build and sign a fresh app bundle in a unique .build staging directory, then atomically swap it into dist. Retain the previous bundle in the staging directory so existing processes keep their mapped executable unchanged.
- A development-host crash report showed a CODESIGNING Invalid Page termination during an in-place rebuild. Replacing the bundle avoids overwriting a running signed executable. Reopen the app to use the installed build.


## Readable supporting text (2026-10-21)

- Replace 9–11 point labels and caption styles with standard 13-point body text across the library, timestamps, speaker names, status, summary options, Settings and model setup. Recording titles use 14 points; transcript, summary and live preview text use 16 points with the existing line spacing.
- Widen timestamp/playback labels for the larger text, use a regular playback slider and footer buttons, and improve document metadata contrast. Keep the shared two-tab layout.


## Recording library actions (2026-10-21)

- Add Rename and Move to Trash to each recording's context menu and the File menu, plus a selected-recording Trash button in the sidebar and Delete handling when the list has focus. Rename uses ⇧⌘R; Trash uses ⌘⌫. Keep direct title editing available.
- Confirm deletion with the recording title and scope. Move the whole UUID project directory using macOS Trash; imported originals and shared models stay in place. Restore the project folder into Projects and reopen to recover it.
- Block both operations while processing/recording or when edits have failed to save. Update the list only after successful disk operations. Deleting the selected recording stops playback and selects a neighbor, or returns to the empty library. Rename changes metadata without changing selection, audio, transcript or notes.
