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

Experimental Swedish transcription uses FluidAudio (FluidInference, Apache 2.0),
pinned at c79c4106b954f81205113c3343e5a7e59a1089b5. TTS, FluidAudio diarization
and NeMo text processing traits are disabled. Full FluidAudio and incorporated
fastcluster (BSD) license texts are bundled in Resources.
https://github.com/FluidInference/FluidAudio

Pianissimo model: Klang AI, fine-tuned from NVIDIA Parakeet TDT 0.6B v3,
CC BY 4.0. Community Core ML conversion by magnushjelm, adapted from
FluidInference's mobius conversion scripts; encoder weights compressed with
8-bit k-means palettization. This is a conversion of the original model,
not Klang's official MLX package. The preprocessor and vocabulary are retained
from Parakeet v3. Model revision: ff8af835072b77a880991ce2d5402d249f923886.
The downloaded model card is retained with the weights.
https://huggingface.co/KlangAI/pianissimo-sv
https://huggingface.co/magnushjelm/pianissimo-sv-coreml
https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
https://creativecommons.org/licenses/by/4.0/

The app contains no analytics. Audio inference runs locally. Model/tokenizer preparation downloads files; optional hosted summaries and transcript cleanup send transcript text to the user-selected provider after an explicit request. On-device text processing uses the macOS Foundation Models framework and Apple Intelligence model.


ChatGPT account identity verification uses JWTKit (MIT), with Apple Swift Crypto,
Swift Certificates, Swift ASN.1 and Swift Log (Apache 2.0 with Swift Runtime Library
Exception where specified). Full LICENSE and NOTICE texts are bundled in Resources.
https://github.com/vapor/jwt-kit
https://github.com/apple/swift-crypto
https://github.com/apple/swift-certificates
https://github.com/apple/swift-asn1
https://github.com/apple/swift-log

ChatGPT plan summarisation sends only transcript text to OpenAI after the user
connects their account and selects that provider. Sign-in uses the system browser;
OAuth credentials are stored in macOS Keychain separately from API keys.
