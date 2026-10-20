# Plan: A lightweight, fully local macOS transcription app

I would build this as a native SwiftUI application, with drag-and-drop audio transcription, direct microphone recording and optional speaker diarisation.

And after looking into the available libraries, there's a particularly attractive solution that simplifies the architecture considerably: WhisperKit + SpeakerKit.

These give you Whisper transcription and pyannote-based speaker diarisation using native Swift and Apple's Core ML framework. That means we can avoid embedding Python, PyTorch, `ffmpeg` and a separate `whisper.cpp` executable altogether.

The goal would be a self-contained `.app` that works offline after downloading its models, without subscriptions, cloud APIs or external dependencies.

## 1. Proposed interface

Transcribe

Local processing

Drop audio file here

AAC, M4A, MP3, WAV and more

&#x20; Open file  Record

Identify speakers

Label different voices in the transcript

LanguageAutomatic

ModelTurbo (fast)

Meeting transcript

Example output

Speaker 1

Jag tänker att vi kan köra en första version redan nästa vecka.

Speaker 2

Ja, men vi behöver nog testa den lite mer först.

This is an illustrative interface, not a functioning recording or transcription app.

The interface should remain deliberately simple. Open or record something, choose whether to identify speakers, and transcribe.

I'd also add a waveform player, clickable timestamps, editable speaker names, copy-to-clipboard and exports to Markdown, plain text and JSON.

## 2. Recommended technical architecture

SwiftUI macOS application

Recording · Drag & drop · Playback · Transcript editor

AVFoundation

Microphone recording · Audio decoding · Resampling

WhisperKit

Whisper transcription via Core ML

SpeakerKit

Pyannote diarisation via Core ML

Transcript assembler

Timestamp alignment · Speaker mapping · Editing

Local documents

Original audio · Transcript · TXT / MD / JSON export

### Why these libraries?

The [Argmax open-source Swift SDK](https://github.com/argmaxinc/argmax-oss-swift?utm_source=chatgpt.com) now includes:

- WhisperKit: Runs Whisper on Apple Silicon using Core ML.
- SpeakerKit: Runs pyannote's Community-1-style segmentation and embedding models through Core ML.
- Speaker assignment: Built-in functionality to reconcile diarisation results with Whisper transcription segments.

That last capability is especially valuable. We don't need to build our own alignment algorithm from scratch.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



The SDK is MIT-licensed, although the model weights have their own licensing and download conditions.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub

+1



## 3. Native versus Python versus command-line tools

| Approach                                        | Packaging          | Complexity    | Recommendation  |
| ----------------------------------------------- | ------------------ | ------------- | --------------- |
| Swift + WhisperKit + SpeakerKit                 | Self-contained     | Low–medium    | Preferred       |
| Swift + bundled `whisper.cpp` + Python pyannote | Complicated        | High          | Avoid           |
| Swift + external MacPorts tools                 | Requires setup     | Low initially | Prototype only  |
| Python GUI + Whisper + pyannote                 | Python environment | Medium        | Useful fallback |

The biggest weakness of the Python approach isn't writing the application. It's packaging PyTorch, audio dependencies, model files and a compatible Python runtime into something that feels like a normal Mac application.

Likewise, I wouldn't build a permanent dependency on an externally installed `whisper.cpp` or `ffmpeg`. It's brittle when sharing the application with other people.

With AVFoundation, you can decode the iPhone's AAC/M4A files natively and prepare audio for both inference engines.

One caveat: I'd verify SpeakerKit's diarisation accuracy and model-loading behaviour on your M5 before committing to it. The native implementation looks promising, but I haven't benchmarked it against the original Python pipeline.

## 4. Core functionality

Recording

Capture microphone audio using AVFoundation. Show duration, level meter and pause/resume controls. Save the original recording before processing, so transcription can be retried safely.

File import

Accept dropped or selected audio files, particularly `.aac`, `.m4a`, `.wav` and `.mp3`. Decode with AVFoundation into a common PCM representation.

Transcription

Run WhisperKit asynchronously. Allow Swedish, English or automatic language detection. Display progress and retain segment timestamps.

Optional speaker diarisation

Run SpeakerKit when enabled. Detect speaker turns, optionally specify the expected number of speakers and merge speaker labels with transcript segments.

Review and export

Editable transcript, speaker renaming, audio playback at selected timestamps, copy and save as Markdown, TXT or JSON.

I would make the speaker toggle work after transcription, too. That is, you could transcribe a recording quickly without diarisation, then enable speaker identification later without transcribing the audio again.

## 5. Suggested project structure

```
Transcribe/
├── App/
│   ├── TranscribeApp.swift
│   └── ContentView.swift
├── Models/
│   ├── Recording.swift
│   ├── Transcript.swift
│   └── TranscriptSegment.swift
├── Services/
│   ├── AudioRecorder.swift
│   ├── AudioImporter.swift
│   ├── TranscriptionService.swift
│   ├── DiarizationService.swift
│   ├── TranscriptAssembler.swift
│   └── ModelManager.swift
├── Views/
│   ├── RecordingView.swift
│   ├── TranscriptView.swift
│   └── SettingsView.swift
└── Storage/
    └── TranscriptStore.swift
```

Keep the transcription engine and diarisation engine behind small interfaces. That gives us the freedom to replace WhisperKit with `whisper.cpp` or swap diarisation implementations without changing the rest of the application.

A transcript segment might be represented as:

```
struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    var text: String
    var speakerID: String?
}
```

I'd also persist speaker display names separately from model-assigned IDs.

## 6. Implementation phases

Phase 1 — Validate the inference engines

Create a small Swift command-line prototype using WhisperKit and SpeakerKit. Test the actual Swedish AAC recording you're experimenting with, check speaker attribution and measure speed and memory consumption.

Deliverable: working local transcription with optional speakers.

Phase 2 — Build the SwiftUI application

Implement file import, drag-and-drop, language selection, speaker toggle, processing progress and transcript display.

Deliverable: usable macOS GUI for existing audio files.

Phase 3 — Recording and review

Add microphone capture, audio playback, timestamps, speaker renaming and editing. Persist projects locally.

Deliverable: complete recording-to-transcript workflow.

Phase 4 — Packaging and polish

Manage model downloads, support offline launches, bundle all runtime dependencies, handle errors and cancellation, and build a signed `.app`.

Deliverable: standalone application requiring no developer tooling.

## 7. Important implementation decisions

Model downloads: I'd download models on first use and store them in Application Support, rather than shipping several gigabytes inside the app. Provide a simple model-management preference.

Recording: For the first version, capture the Mac's microphone. Capturing both sides of a video call requires additional system-audio handling and permissions, so I'd treat that as a separate feature.

Streaming: I'd initially support recording while displaying audio levels, then transcribe after stopping. Real-time transcription adds complexity without much value for the intended workflow.

Speaker recognition: SpeakerKit can identify recurring speakers within a recording. Associating those speakers with named people across multiple meetings would require another layer of reference embeddings, identity matching and consent controls.

Privacy: No audio needs to leave the machine for inference. First-use model downloads are the exception. Users should still be informed when their conversations are being recorded.

Licensing: The pyannote Community-1 weights are CC-BY-4.0 and require accepting Hugging Face access conditions. SpeakerKit's Core ML models and redistribution arrangements should be checked separately before distributing a packaged app.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://huggingface.co\&sz=32)

Hugging Face



## Final recommendation

I'd use:

| Component                     | Technology                       |
| ----------------------------- | -------------------------------- |
| Application                   | SwiftUI                          |
| Audio capture/decoding        | AVFoundation                     |
| Transcription                 | WhisperKit                       |
| Model                         | Whisper large-v3-turbo initially |
| Speaker diarisation           | SpeakerKit (pyannote-based)      |
| Inference                     | Core ML / Apple Silicon          |
| Storage                       | Local files                      |
| Packaging                     | Native `.app`                    |
| External runtime dependencies | None                             |

I particularly like this approach because it respects the Mac as a capable local computing platform rather than treating it as a thin client for yet another hosted service.

And the most important engineering choice is to prototype WhisperKit and SpeakerKit together before spending time on the interface. If their Swedish transcription and diarisation results are satisfactory, the remainder is fairly straightforward macOS application development.

You could realistically end up with a useful, elegant little utility that does exactly what you need — with no ongoing subscription and without managing Python environments or CLI binaries.