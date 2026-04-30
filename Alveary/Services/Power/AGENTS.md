## Power Services

These instructions cover keep-awake and power assertion services under `Alveary/Services/Power/`.

- Keep `DefaultKeepAwakeService` as the single owner of IOKit assertion IDs.
- Track independent activity sources and release assertions only after the last source clears.
- Use only supported assertions: idle system sleep and optional display sleep. Disk idle prevention is intentionally out of scope.
