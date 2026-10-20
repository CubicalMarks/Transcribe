# Third-party software and model attribution

Transcribe uses WhisperKit and SpeakerKit from Argmax OSS Swift, pinned at v1.1.1:
https://github.com/argmaxinc/argmax-oss-swift

Copyright © Argmax, Inc. MIT license. The build bundles the SDK's complete LICENSE and NOTICES, including its incorporated Hugging Face swift-transformers Apache 2.0 notices.

Whisper model weights: OpenAI Whisper, converted/optimized by Argmax, MIT.
https://github.com/openai/whisper
https://huggingface.co/argmaxinc/whisperkit-coreml

Speaker model weights: Pyannote-derived segmentation, embeddings and clustering models, converted/quantized by Argmax. CC BY 4.0, as stated by the Argmax model repository. These Core ML representations are conversions of the original models.
https://huggingface.co/argmaxinc/speakerkit-coreml
https://github.com/pyannote/pyannote-audio
https://creativecommons.org/licenses/by/4.0/

Model weights are downloaded separately by the user and are not bundled into this application. Keep model attribution and applicable notices with any redistribution. No Hugging Face login or acceptance is automated by this app; download failures are shown to the user.

The app contains no analytics. Audio inference runs locally. Model/tokenizer preparation downloads files; optional API summarisation sends transcript text to the user-configured endpoint. On-device summarisation uses the macOS Foundation Models framework and Apple Intelligence model.
