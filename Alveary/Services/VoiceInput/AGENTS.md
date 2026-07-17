## Voice Input Services

- Keep microphone permission checks ahead of every model-network operation.
- Keep recognition local. Do not store microphone audio or recognition output outside the composer draft/message lifecycle, and never upload it.
- Keep FluidAudio managers and Core ML operations behind the serialized inference owner; never expose a manager to UI code.
- Pass the one app-scoped service through Needle dependencies; composer code must not resolve `AppDI.component`.
- Consult the service's synchronous preparation admission before local readiness. The blocking preparation modal prevents another composer activation while setup is active; keep the app-scoped admission gate defensive against races.
- Treat preparation provenance as authoritative; do not add a persisted setup-completed flag. An authorized microphone plus validated pinned cache warms Core ML with only the microphone spinner and auto-starts a still-valid mouse, keyboard, or accessibility activation.
- Keep installation, app-managed update, repair, newly requested permission, and cache-failure paths in the blocking modal. Consume their initiating activation and require Continue plus a fresh activation after readiness.
- Cancel cache-only warmup and its pending activation when its composer navigates away. Do not flash a cancellation modal for that hidden cleanup, and never let another composer join it.
- Copy tap buffers into owned storage. The real-time tap must not create tasks, wait, log, convert audio, or touch UI.
- Close capture admission and remove the tracked tap synchronously before asynchronous inference cleanup.
- Preserve compatible `.part` downloads after cancellation or transient network failure. Cleanup loaded models before deleting validated model files.
- Model-preparation cancellation comes from the blocking voice-model modal. Keep that modal visible through delayed Core ML cancellation, and close it only after the owning preparation task returns.
- Store models under `SessionComponent.appSupportDirectory/VoiceInput/Models/<schema>/<revision>`, exclude the cache from backup, and validate every descriptor artifact before atomic promotion.
- Treat the bundled `VoiceInputModelDescriptor.json` as the only production model identity. Download with `resolve/<revision>` and never fall back to `main`, mixed revisions, or runtime metadata discovery.
- Change the model pin only through `scripts/update-voice-model-descriptor.py` with an exact commit and an Alveary release; do not add periodic or manual model updates.
- Keep older pinned revisions until the replacement loads successfully. Remove them only while inference is idle, and route cache clearing through the app-scoped service so cleanup precedes deletion.
- Start memory-pressure monitoring only after a model loads, and bind each pressure request to the ready model generation it observed. Pressure raised during preparation must not unload the newly produced ready generation after Continue.
- During app termination, synchronously commit and flush the active composer before scheduled-task and agent shutdown.
