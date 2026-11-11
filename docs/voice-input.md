# Voice input

Voice input records from the system's default microphone and transcribes English speech on your Mac. Audio and transcripts aren't stored separately or sent to a server, and dictation you commit becomes ordinary composer text.

The first use downloads the Parakeet Unified speech model, about 600 MB, from Hugging Face, and caches it under `~/Library/Application Support/com.afollestad.alveary/VoiceInput/Models/`, which is excluded from backups. After that, setup is skipped while the microphone is allowed and the cached model is still valid.

Each Alveary release pins one model revision, so the model changes only with an app update. It's distributed under the CC-BY-4.0 license, and the app includes its attribution.
