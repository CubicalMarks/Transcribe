# Working in this repository

- Read README.md and docs/decisions.md before implementation. The original proposal is a starting point, not an established contract.
- Keep the application focused, local and usable as a normal Mac app. Keep inference engines behind small interfaces.
- Preserve source audio and user edits when work fails or is cancelled. Avoid committing recordings, transcripts, downloaded models or credentials.
- Explicitly distinguish build checks, real inference tests, quality observations and packaging/offline validation when reporting results.
- Keep docs current with agreed scope and actual commands. Do not describe planned features as working.
