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


## Compact controls and unified Settings (2026-10-21)

- Group transcription language, speaker identification and expected count in one row, with a two-row fallback when needed. Move repeated language/speaker explanations into help tooltips; retain all language choices and automatic/1–12 speaker counts.
- Group summary preset/language in the first row and extra-instruction disclosure/destination in the second. Keep endpoint disclosure visible, with full destination/help on hover. Extra instructions remain editable; saved preset metadata moves beside the summary date/model rather than duplicating the tab bar.
- One native Settings window owns Local Models and Summarisation pages. The sidebar Settings link and ⌘, use that window; toolbar/menu Models and missing-model prompts open its Local Models page, while the summary gear opens Summarisation.
- Local model readiness, optional speaker preparation, download/progress/cancellation, storage access and attribution remain available. Provider/account/model, credential and advanced token controls retain their existing draft Save/Cancel behavior. Initialize the provider draft once per window session so navigation between pages does not intentionally reset it; clear closed drafts on reopening. No inference, credential format or transcript-storage change.


## Rich meeting notes (2026-10-21)

- User supplied a reference summary as a style/richness target and authorized learning from the transcription. Adopt its short overview, descriptive topic headings and substantive bullets, without copying private meeting facts or repeated headings into prompts or fixtures.
- Preserve requirements, workflow order, rationale, constraints, dependencies, priority, temporary workarounds, existing work, handoffs and unresolved choices. Later corrections should supersede earlier proposals only where clear; optional or unclear details must not become firm decisions. Use context for obvious recognition slips, but avoid guessed proper names or technical terms.
- Remove the universal 220-word final instruction for Meeting notes. Give this preset a 2400-token final response budget with flexible 400–700-word guidance for substantive multi-topic meetings; do not pad short conversations. Brief overview and Action items retain their 220-word/900-token final guidance.
- Scale Meeting notes' intermediate word budget with excerpt bytes (60–600 words), with a corresponding response-token budget, instead of compressing every large excerpt to 100 words. Retain the existing provider input bounds, full-source chunking and eight-pass failure limit; this improves allowance but does not establish model quality or eliminate reduction loss.
- Apply the shared preset through the existing local, ChatGPT and compatible API generators. Preserve source-language/output-language choice, extra instructions, saved-summary replacement rules and existing provider billing paths.


## Long-document scrolling and name editing (2026-10-21)

- Replace the shared growing SwiftUI TextField with a plain AppKit NSTextView. Keep the same 16-point text, line spacing, shared outer scroll view and existing edit/autosave binding. Cache measured text height until content or width changes; preserve caret/undo on unchanged updates and use the window's standard undo manager.
- Isolate playback in its own observed View so playhead ticks do not invalidate the document tree. Compute available speaker IDs once for a document render rather than scanning all sections in each row, and read each row's captured text without a second full-array search.
- Speaker names use a local sheet draft and explicit Save Names/Cancel. Apply all names with one atomic project save; publish the updated names only after successful persistence. A failed save keeps the draft available for retry. Transcript and summary text retain immediate autosave.
- This changes neither transcript formats nor inference/model selection. Avoid an asynchronous autosave queue or debounce lifecycle for this fix; source/audio preservation continues to use the existing synchronous atomic store.


## Profiled document-layout performance (2026-10-21)

- A paused interaction sample of the installed 0.3.8 app showed repeated SwiftUI/AppKit layout and minimum-size negotiation during scrolling and Speaker Names presentation. The earlier idle sample did not establish a bottleneck or speedup.
- Replace ViewThatFits' two copies of the transcription controls with one Layout containing one language picker and one speaker-controls group. Preserve the horizontal spacing, vertically centered single row, stacked fallback, complete language list, toggle and count choices. This avoids creating and destroying duplicate native picker/menu graphs during candidate fitting.
- Native editor sizing always answers minimum/ideal/maximum probes with finite sizes. Measure attributed text in a separate TextKit container and cache several widths; hypothetical proposals must not resize or rewrap the live editor. SwiftUI owns the editor frame; content changes invalidate only measurement, avoiding a second native intrinsic-size/window-layout cascade.
- Scope Speaker Names presentation state to its button, and initialize the draft before presentation instead of publishing several onAppear updates through the recording view. Keep Save Names/Cancel and atomic persistence unchanged.
- Retain the interface, native text editing, font/spacing, timestamp playback, per-section speaker menus, immediate autosave and window Undo. No data format, inference, provider, credential or audio handling changes.


## Stable local signing for Keychain access (2026-10-21)

- The user reports that Always Allow does not persist across restarts. The installed and dist 0.3.9 apps both have the same ad-hoc, cdhash-only designated requirement; matching copies rule out different installed/dist builds as the sole explanation. This does not inspect or establish the stored credential ACL state.
- Use an existing personal Apple Development identity on this Mac. Pin its public fingerprint in a Git-ignored `.signing-identity` file; `CODE_SIGN_IDENTITY` overrides it explicitly. Other checkouts without configuration retain ad-hoc builds with a warning. Never select an arbitrary certificate, use company distribution credentials automatically, export private keys, alter credential ACLs or silently downgrade a configured signing failure.
- Preserve the bundle identifier and normal certificate-derived designated requirement across builds. Existing credentials remain untouched, and the first certificate-signed app may need a one-time approval. Keychain storage and app authentication code are unchanged. Local signing omits a timestamp and does not claim notarization/distribution readiness.
- Reference: https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements and Apple's Code Signing Guide, Code Signing Tasks.


## Experimental Pianissimo and model selection (2026-10-21)

- User authorized trying Pianissimo on a separate local branch and expanding Local Models settings. Whisper Turbo remains the default; the saved model selector adds Pianissimo Swedish (experimental), with readiness per selection and independent SpeakerKit readiness. A change affects the next run and retains existing transcripts and downloads.
- Use native Swift/Core ML through FluidAudio, pinned at c79c4106b954f81205113c3343e5a7e59a1089b5 with default traits disabled. Keep SpeakerKit and the existing transcription/speaker interfaces. No Python, MLX runtime or external executable is added to the app.
- Community model: magnushjelm/pianissimo-sv-coreml at ff8af835072b77a880991ce2d5402d249f923886, an 8-bit-palettized encoder with the v3 component contract and 15-second windows. This is a different implementation from Klang's official MLX version; do not inherit its benchmarks or phrase-boosting claims. No vocabulary control is exposed.
- Pianissimo sets and locks Swedish. English, Automatic and mixed recordings use Whisper by explicit model selection; there is no implicit rerouting or failure fallback. The probe accepts `--engine pianissimo --language sv`; Whisper's existing `--model` flag remains available only with Whisper.
- Download only the pinned file manifest, verify sizes and available LFS SHA-256 checksums, and load all local components before publishing readiness. Stage downloads separately and retain any prior installation until replacement succeeds. Inference uses FluidAudio's exact-directory `loadLocal`, never its stock-repository download or repair loader. Disable verbose FluidAudio transcript logging and console mirroring.
- Retain provider-neutral word evidence in the existing private alignment field. Split into editable sections at sentence/length boundaries and into speaker turns when diarizing. Use word evidence only when it covers all recognized text with valid ordered timings; otherwise preserve the full text with coarser segment attribution. Legacy Whisper evidence remains readable; adding speakers to edited text never reconstructs it from old evidence. Save text before diarization as before.
- FluidAudio Apache 2.0 and incorporated fastcluster notices are bundled. Pianissimo/Klang, NVIDIA base model, conversion author, 8-bit modification, source links and CC BY 4.0 attribution are retained with the app and downloaded model card.
- Primary sources: https://huggingface.co/magnushjelm/pianissimo-sv-coreml, https://huggingface.co/KlangAI/pianissimo-sv-mlx-8bit and the pinned FluidAudio source. Native integration smoke checks do not establish natural-meeting accuracy or a speed advantage over Whisper.


## Language defaults and automatic text cleanup (2026-10-21)

- Replace the global model choice with a multilingual default and language-specific rules. Currently Swedish has an alternative engine: Use default, Whisper Turbo or Pianissimo. Automatic/mixed, English and other languages use the compatible default. Migrate a saved global Pianissimo selection to a Swedish override plus remembered Swedish; no incompatible Swedish-only engine is routed to other languages.
- New recordings/imports start with Remember last selected (default), Automatic or a fixed language. Store the requested language separately from the ASR-detected language. Each recording with a saved selection retains it; explicit language changes also update the remembered choice. Settings prepares all configured models and optional speakers; an individual transcription requires only its resolved model and enabled speaker models.
- The user requested an optional LLM cleanup pass that just works when toggled, without a review window. Add a remembered Clean up text toggle beside recording options and show its provider destination when enabled. After ASR is saved and speaker identification is saved, generate and save cleaned text automatically. Clean Up Now applies the same pass to existing text. Do not add a cleanup review/approval step or per-run confirmation; keep the existing transcription-replacement and restore confirmations.
- Rename the provider page Text & AI and share its existing on-device, ChatGPT or compatible API generator. Keep ASR model selection separate. The cleanup prompt conservatively edits punctuation, capitalization and unambiguous wording while preserving source languages, names, numbers, negations, uncertainty and incomplete thoughts. Summary presets/language/extra instructions do not affect cleanup.
- Process all source text in bounded JSON batches, splitting oversized segments without dropping Unicode or the tail. Require every supplied fragment ID exactly once and reject incomplete, empty-for-nonempty-source or invalid results. Reassemble only text; retain section IDs, times, speaker labels and private ASR alignment. Verify the source snapshot before the atomic save. Failures or cancellation never save a partial cleanup or remove the already-saved transcript.
- Retain the text/sections from before the first applied cleanup in private project data. Restore Original Text restores that text and boundaries; retain current speaker labels for matching sections and leave restored unmatched sections unassigned. Retranscription clears the old cleanup backup. JSON exports omit the private backup, as they omit internal alignment evidence.
- Add Join with Previous Section to timestamp context menus. Preserve both sections' words and full time span; use the previous speaker label, with confirmation across different labels. Do not use LLM text cleanup to invent speaker attribution. The screenshot establishes fragmented text/labels, not the correct number or identity of real speakers.
