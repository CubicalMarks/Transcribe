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


## Summary authentication diagnostics — 2026-10-21

- App 0.2.2: `make check` passed with 15 tests. New cases verify missing/whitespace OpenAI credentials prevent any request, including when the OpenAI URL is selected as a custom endpoint; HTTP 401 identifies authentication and Settings without exposing the key or response body. Existing compatible-request coverage checks the Bearer header.
- Ran the actual Keychain implementation in an isolated harness with a unique synthetic endpoint account. Save, metadata-only existence lookup, read and removal passed. No existing credential was queried or changed, and no external API call was made.
- Settings now reports saved-key presence without retrieving the secret or triggering authentication UI. Presence is not a validity test. The reported screenshot establishes HTTP 401; whether the user's credential is missing, invalid or lacks access has not been established.


## ChatGPT plan integration — 2026-10-21

- `make check` passed: source/config lint, arm64 release app 0.3.0, strict ad-hoc signature verification and 21 tests. Bundled JWTKit and transitive Swift library license/notice texts were checked in app Resources.
- Synthetic OAuth tests validate fresh PKCE/state/nonce, callback host/path/port binding, duplicate/mismatched state, declined consent, issued client ID reuse and rejection of a changed returning registration.
- Generated ephemeral RSA keys to test actual JWTKit signature verification and issuer/audience/expiry/nonce/subject checks, including incorrect signatures and unsigned tokens. No external identity or token was used.
- Real loopback HTTP test exercised the IPv4-local callback listener, rejection of a wrong state, successful callback and cancellation. The app opens the system browser, but live OpenAI browser authentication/consent has not been completed by the agent.
- A URLProtocol fixture exercised code exchange, isolated synthetic Keychain persistence, concurrent refresh with a single rotation, account-specific model discovery, multiple registrations with distinct identities and the same email, identity-only consent blocking, request shape and a completed streamed summary. Verified temporary refresh failures preserve credentials and terminal invalid_grant clears tokens while retaining registration metadata. Test Keychain items were removed afterward.
- Multi-event streaming exposed Foundation AsyncBytes.lines omitting empty SSE boundaries. The implementation now frames raw bytes; tests cover multi-event streaming, Swedish/emoji UTF-8, CRLF, missing completion, failure and refusal. Only nonempty assistant output from response.completed is saved.
- Visually checked provider choices, ChatGPT account picker, Continue with ChatGPT, model placeholder and Manage Usage in a separate empty-library preview bundle with its own preferences and Keychain namespace. Cancel dismissed Settings; the preview exited cleanly. No agent-initiated real sign-in, plan consumption, private transcript upload or API-key fallback occurred.
- Remaining live validation: the user must sign in, approve plan usage, confirm their account's actual model catalog and generate a summary. Synthetic protocol checks establish integration behavior, not account eligibility, provider admission or summary quality. Existing microphone, M1/8 GB and macOS 15 runtime limitations above remain.


## Shared document layout — 2026-10-21

- `make check` passed: source/config lint, arm64 release app 0.3.1, strict ad-hoc signature verification and all 21 existing tests. This UI change adds no model/API traffic or data-format changes.
- An isolated preview with fictional English/Swedish segments, saved notes and silent audio showed transcript timestamp/speaker controls and the shared summary header, options placement, tab/export bar, growing text field and bottom regeneration action. The summary text scrolls in the common content area.
- The user began interacting with the preview's Settings; agent editing/export interaction checks were left unfinished to avoid interfering with their draft. Existing deterministic tests cover transcript/summary storage and exports, but this is not a claim of a completed manual editing round-trip in the new UI. No real account credentials or private transcript were used by agent validation.


## Transcription preview and progress — 2026-10-21

- `make check` passed: lint, arm64 release app 0.3.2, strict ad-hoc signature verification and 23 tests. New coverage checks that bounded delivery retains all sections in its newest snapshot, callbacks after finish are ignored, timestamps are monotonic/bounded, invalid entries are excluded and unknown duration remains indeterminate.
- Ran the real local engine on the existing 44.4-second synthetic English/Swedish speech fixture with cached tiny weights and outbound networking denied. Preview updates arrived before completion: six sections through 0:21, then ten through 0:43; the final result contained ten segments. The probe finished in 4.20 seconds on the development host. This confirms the callback path, not natural-meeting quality or M1 performance.
- A separately identified native preview bundle used only the synthetic speech and an isolated library with existing Turbo model files. Verified the loading state replaces the idle prompt. A real Turbo rerun showed 49% audio-position progress and its first three read-only sections while busy; successful completion saved six final segments and returned to the editable transcript.
- The UI preview kept prior text separate during reruns. Manual cancellation during inference was not independently completed in this pass; the short rerun finished before the attempted click, and further UI interaction was left to the user. Reporter finish/late-callback behavior is covered by deterministic tests. Existing cancellation inside third-party Core ML work can still take time to return.
- No private audio, new model download, hosted API or account credential was used by these checks. Speaker-identification progress remains the existing separate stage. Live microphone transcription has not been added.


## ChatGPT stream extraction and safe packaging — 2026-10-21

- `make check` passed for app 0.3.3: lint, arm64 release packaging, strict ad-hoc signature verification and all 28 tests. Five new parser tests cover compact completion after UTF-8 deltas, text/content/message finalization without duplication, part ordering, authoritative final snapshots, rejection of incomplete/failed/refused output and safe diagnostics for genuinely empty responses.
- The existing synthetic account lifecycle HTTP fixture now delivers delta/done events followed by a completed response with an empty output array. Generation returns the accumulated summary through the real URLSession streaming path. Synthetic credentials remain isolated and are cleaned up after testing.
- The user's actual event sequence was not captured, and no live account generation, real credential read or private transcript upload was performed by the agent. These tests confirm the parser gap and its correction; retrying with the user's connected account remains the live validation step.
- After changing packaging to sign a staged bundle and swap it into dist, `make build` and `make lint` passed. The newly installed app and the retained previous bundle both passed strict signature verification. A disposable fixture exercised the actual installer and verified that the old open file descriptor retained its bytes/inode while the destination contained the new bundle contents.


## Readable interface text — 2026-10-21

- App 0.3.4 builds and passes strict ad-hoc signature verification and source/config lint. This change only adjusts interface typography, contrast and control/label sizing; inference and persistence are unchanged. No new unit tests were added for font declarations.
- Visually checked an isolated preview with fictional Swedish/English transcript segments and saved notes. Both tabs show 16-point document text; supporting text, speaker names and timestamps use 13 points. A one-hour segment timestamp fits the widened column. The library title now uses normal case to fit its larger font.
- Inspected native Settings in local and OpenAI API modes: provider/model fields, saved-key status, wrapped help text and buttons remain legible within the existing window. Cancelled the settings draft and quit the preview. No real credential value was read, private transcript opened or hosted generation performed. Live-progress/model-setup text shares the same font changes but was not manually exercised in this pass.


## Recording rename and Trash — 2026-10-21

- `make check` passed for app 0.3.5: source/config lint, arm64 release build, strict ad-hoc signature verification and all 30 tests. Two new tests exercise real macOS Trash on disposable fixtures: the whole project remains byte-intact and restorable, while another recording, an imported-original fixture and model files remain unchanged; failure to trash a missing project leaves the library intact. The test restores its project before temporary-directory cleanup.
- In a separate preview bundle/library containing only two synthetic recordings, right-click Rename targeted the unselected row, updated its name and preserved the selected recording. Cancelled a deletion and verified both rows remained. ⌘⌫ opened confirmation for the selected fixture; confirmed deletion selected its neighbor. Deleting the last fixture showed the empty-library welcome view and disabled the Trash button.
- UI checks moved only the two disposable preview recordings to Trash; no user recording, private transcript or credential was read or changed. No transcription, provider inference or live-account claim applies to this library-management change.


## Compact options and unified Settings — 2026-10-21

- `make check` passed for app 0.3.6: source/config lint, arm64 release build, strict ad-hoc signature verification and all 30 existing tests. No new unit tests were added for this interface-only change.
- An isolated preview with fictional Swedish/English transcript and summary showed the one-row language/speaker/count group, compact summary rows, destination indicator, saved preset metadata and expanding/editable extra instructions. The summary gear opened the Summarisation page in the native Settings window, with Local Models alongside it in the toolbar.
- Further interaction checks, including switching pages with an unfinished provider draft, closing/reopening that draft and the local-model shortcut, were not completed: the computer-use tool detected user interaction with the preview, so agent actions stopped. Navigation/draft handling was reviewed in source; this is not a completed manual draft-preservation round-trip claim.
- No private transcript, real credential value, hosted generation or model download was used by agent checks. Existing live-provider, microphone and target-hardware limitations still apply.


## Rich meeting-notes preset — 2026-10-21

- `make check` passed for app 0.3.7: lint, arm64 release build, strict ad-hoc signing verification and 31 tests. New regression coverage runs all three presets through a multi-section synthetic transcript: every source section is supplied within the input bound, Meeting notes receives larger section/final budgets and preserves a response longer than 220 words, while Brief overview and Action items retain their compact limits. Language, extra instructions and source digest remain intact.
- Reviewed the user-supplied transcription to identify corrections, optional versus required details, workflow dependencies, prior work, priorities and end-of-meeting handoffs as generic summary requirements. No private transcript, reference summary or meeting-specific vocabulary was added to prompts, tests or Git. A private illustrative Swedish summary was written outside the repository; it is a human-review target generated in this conversation, not an app/model evaluation result.
- The local synthetic summary probe built successfully but could not generate: Apple Intelligence remains disabled on this Mac. No real ChatGPT/API request, credential read or private transcript upload was performed by the agent. Output richness and fidelity from the user's selected model remain unverified until regeneration and review; smaller-context reduction can still lose details. Existing saved summaries were not changed.


## Long-document scrolling and speaker-name editing — 2026-10-21

- App 0.3.8: `make check` passed source/config lint, arm64 release packaging, strict ad-hoc signing verification and all 35 tests. Four native-editor tests cover long Unicode text wrapping and resize, repeated cached-size queries, caret/undo preservation for unchanged content, clearing stale undo on external document replacement, full-text binding delivery and real NSTextView typing/undo through the window undo manager.
- Compared isolated previews using the same synthetic fixture: 1,200 transcript sections and a 100-topic, roughly 30 KB summary. The updated native text rendered correctly and the transcript and summary scroll containers advanced while retaining the editable content. These are interaction checks, not a quantified frame-rate or M1 performance benchmark. A short CPU sample was mostly idle and does not establish a numerical speedup.
- In the updated speaker-name sheet, typed a longer Unicode name and verified the saved project still held its original name until Save Names. Applying it persisted the new name while all 1,200 transcript sections and saved summary remained unchanged.
- Edited a visible transcript section with Unicode and a paragraph break; checked the saved JSON contained the complete edit. In the final build, typed into the long summary and confirmed autosave retained its last topic; Command-Z restored and autosaved the exact original summary. The first native prototype used a private undo manager that did not route the app's keyboard Undo command; corrected it to the standard window manager and added a regression before final validation.
- The checks used only disposable synthetic libraries and separate bundle/preference identities. Requested closure of the three test previews afterwards. No private recording, transcript, credential, model download or hosted generation was used. Keyboard editing remains synchronous for persistence; this pass does not establish performance for arbitrarily large libraries or recordings.


## Profiled paused document performance — 2026-10-21

- The installed 0.3.8 app was sampled while paused, scrolling and opening/cancelling Speaker Names. Main-thread activity centered on SwiftUI/AppKit layout and minimum-size queries. Native editor construction/text layout and background inference were not the dominant sampled work. An earlier mostly idle sample provided no performance conclusion.
- Compared release builds against 0.3.8 using the same offscreen NSWindow/NSHostingView fixture: 224 short, uniquely numbered synthetic sections, two speakers, 1160×780 points, 30 scroll/layout/fitting-size passes. Three runs per variant: initial layout 0.3248/0.3224/0.3020 seconds before, 0.0808/0.0718/0.0742 after; scroll passes 1.1350/1.0000/1.0179 seconds before, 0.5458/0.5496/0.5538 after. Median reductions are approximately 77% and 46% respectively. This is an offscreen layout benchmark on this development Mac, not onscreen FPS, a speaker-sheet latency benchmark, an M1 guarantee or a whole-app speed multiplier.
- `make check` for 0.3.9 passed lint, arm64 release packaging, strict ad-hoc signature verification and all 37 tests. New coverage checks finite editor proposals, repeated multi-width cache reuse without changing the live frame/container, and actual SwiftUI/native row growth after typing. The integration fixture verifies full-text autosave to disk and exact restoration through window Undo, without showing a window or accessing user recordings.
- A separately identified QA bundle/library showed the unchanged transcript controls/editor and long-summary layout. Scrolled both tabs, opened Speaker Names and saved a Unicode name; checked all 224 sections and the saved 100-topic summary remained intact. The UI automation launch tool stalled; its wall-clock duration is not an app launch measurement. No real recording edits, credentials, downloads or hosted generation were involved.
- The shared editor's measurement changes also apply to summaries. Summary scrolling was exercised, but no numerical summary or speaker-dialog speedup is claimed. Persistence remains synchronous; very large-document edit latency and performance on 8 GB M1 hardware remain unmeasured.

- Final 0.3.9 (14) packaging/checks passed again after guarding nonfinite control-layout widths. Atomically updated `/Applications/Transcribe.app`, retained the previous bundle, verified the installed strict signature and identical executable hash against `dist`. The QA app was closed; the installed release awaits the user reopening it.


## Certificate signing and Keychain continuity — 2026-10-21

- App 0.3.10 (15): source/config/package lint and arm64 release packaging passed with the selected existing personal Apple Development certificate. Strict signature verification passed. The installed `/Applications/Transcribe.app` has the same executable hash as dist and a certificate-based designated requirement, replacing the previous cdhash-only ad-hoc requirement. Installation retained the previous bundle without overwriting its mapped executable.
- Compiled and signed two disposable probe app variants with the same identifier/certificate and different executable contents. Verified matching certificate-derived requirements. Variant A created a uniquely namespaced synthetic Keychain item; fresh A processes read it twice, then B read it with authentication UI explicitly disabled. All reads returned the exact synthetic value. Removed the synthetic item afterwards. No user credential value or credential ACL was read or modified.
- Explicit empty and nonexistent signing identities both failed without falling back or replacing the valid dist executable. The per-machine certificate fingerprint file is ignored by Git. No private key export, Keychain trust/ACL change, account sign-in, private transcript upload or notarization was performed.
- Application/authentication source is unchanged, so existing unit tests were not rerun for this packaging-only patch. The synthetic check confirms certificate continuity for new items, not migration of the user's existing ad-hoc-authorized item. The first signed app may request one approval; actual existing-account access and repeated user-app restarts still require user validation. The running app was not forcibly quit.


## Intermittent scrolling beachball investigation — 2026-10-21

- User identified scrolling as the trigger. No Transcribe process was running during inspection or a subsequent 45-second capture window. Existing user crash reports are for older releases; no current hang report was found. The reported beachball remains unreproduced and unresolved.
- Expanded the existing synthetic 224-section offscreen regression to include 240 jumps distributed across the whole document, including both ends. Both scroll tests passed; subsequent native editing, frame growth, disk autosave and Undo preservation checks passed. No application source, interface, installed app or recording was changed by this investigation.
- The rapid test took approximately 10.49 seconds for its scroll loop (slowest pass 0.078 seconds); a separate profiled run took 11.51 seconds (slowest 0.097 seconds). These wall times include event-loop waiting and fitting-size queries. The sample contains layout work and idle waits, without establishing a deadlock or a sustained main-thread block. This offscreen programmatic test does not reproduce physical wheel/trackpad event handling or establish the cause of the user's beachball.
- Read only recording length/count statistics to check fixture scale; no private dialogue, credential or audio content was copied into tests or Git. Capturing the running app during the actual stall remains necessary before claiming a corrective patch.


## Experimental Pianissimo and model settings — 2026-10-21

- Build checks: `make check` passed source/config lint, arm64 release packaging, strict certificate-signature verification and all 44 tests. Added coverage for incomplete/invalid word evidence, text preservation during speaker attribution (including edits and legacy Whisper evidence), Swedish-only scope, cancelled preparation, missing installation and truncated/wrong-checksum weights. FluidAudio is pinned; existing dependency versions are unchanged.
- Real inference: downloaded the pinned community Core ML conversion into an ignored, isolated `.build/pianissimo-qa/library`. Transcribed a 43.26-second Swedish macOS Alva speech fixture about a fictional library exhibition. The native path emitted four temporary window previews and saved twelve sections with 104 aligned words. SpeakerKit preparation and inference then completed using those timings and identified one voice, consistent with this single-voice fixture. The speaker installation manifest contains no Whisper model; preparing Pianissimo plus speakers does not download Whisper.
- Quality observation: the synthetic output retained the fixture's wording, with number formatting (`fem tusen kronor` became `5000 kr`) and punctuation changes. This is a narrow integration smoke test, not a natural-meeting accuracy evaluation, a measured WER comparison against Whisper, an overlap/multi-speaker assessment or a verified speed advantage. First-load/warm-run timings varied, so no model benchmark is inferred.
- Packaging/offline: a release probe succeeded with `sandbox-exec -p '(version 1) (allow default) (deny network*)'` and no `--prepare`, using only the prepared models. It transcribed and diarized the fixture successfully. Model loading uses the exact-directory local loader. No Python, ffmpeg or external ASR executable was needed. The signed app contains FluidAudio and fastcluster notices; model weights are separate. This does not establish fresh-Mac, notarization, M1 or long-meeting readiness.
- Native UI: used a separate QA bundle identifier and only the synthetic library. Verified Whisper initially showed Not prepared while SpeakerKit showed Ready; selecting Pianissimo showed its own Ready state, Swedish-only guidance and unavailable vocabulary hints. Selecting it disabled the recording's language picker at Swedish. Ran transcription plus speaker identification from the app through saved completion. Restarting retained the model choice and Swedish restriction; switching back to Whisper restored language selection and its independent readiness. The settings layout was visually inspected; the QA app was then closed.
- Confirmed every imported synthetic audio copy remained byte-identical and each saved alignment covered all transcript text. Private recordings, transcripts and account credentials were not used. No model, generated audio, transcript, build artifact or machine signing configuration is committed. The installed app in `/Applications` was not replaced.


## Language routing and automatic cleanup — 2026-10-21

- Build checks: all 52 tests passed after the automatic-cleanup implementation. New core/app checks cover legacy model-preference migration, compatible language routing, fixed/remembered defaults, per-recording persistence, bounded complete Unicode cleanup inputs, incomplete/duplicate/unknown/empty response rejection, cancellation/partial failure, source-change rejection, backup storage/export omission/restoration and manual joins. Release packaging, source/config lint and strict signature verification passed.
- Native UI: used a separately identified QA bundle and isolated fictional library/preferences. Visually checked default/Swedish model rules and new-recording language options, and the shared Text & AI provider page. Verified the enabled Clean up text toggle shows the destination and survives restarting. The final flow contains no cleanup review window or per-run cleanup confirmation. Manual join across different speaker labels confirmed the retained label and preserved both texts and the full span; restoring pre-cleanup text also completed in the synthetic fixture.
- Real inference plus protocol validation: from one Transcribe action, the prepared native Pianissimo model transcribed the same 43.26-second synthetic Swedish Alva recording, SpeakerKit identified one voice, and cleanup automatically called a loopback mock Chat Completions endpoint. Held the mock response pending and verified that twelve raw ASR sections plus speaker labels were already on disk. Released the response; its deterministic punctuation edit saved automatically, with every section ID/time/speaker, the private alignment data and byte-identical audio retained. The backup exactly matched the pre-cleanup sections.
- Failure validation: stopped the mock endpoint, restarted the QA app (cleanup remained enabled), and retranscribed the synthetic fixture. The expected connection error left the freshly saved raw ASR text, all twelve sections, speaker labels and audio usable; no incomplete cleanup or stale backup was saved. The QA app and mock endpoint were closed afterwards.
- Quality/offline limits: the cleanup endpoint returned deterministic fixture text, not a real LLM inference. Cleanup wording quality, Swedish/mixed-language fidelity and natural-meeting improvements remain unmeasured. No private recording, transcript, credential or hosted account was used by the agent. No new model download was needed; existing prepared QA models were reused. The previous ASR offline probe remains separate evidence; hosted cleanup itself requires its selected provider to be reachable. No fresh-Mac, live on-device LLM, hosted LLM, notarization or M1 performance claim is made. The installed `/Applications` app was not replaced.
