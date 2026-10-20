# OreGuard cover-thumbnail brief — skeleton awaiting adoption pipeline

Generated-art is NOT shipped inside oreguard's deliverable graphics (the mod
has none). The one allowed generated artifact is the cover thumbnail that
ships in the zip (portal page + in-game mod list), delivered by the
`devctl mods art` pipeline:

    devctl mods art oreguard oreguard-thumbnail generate   # candidates
    devctl mods art oreguard oreguard-thumbnail adopt <i>  # human picks
    devctl mods art oreguard oreguard-thumbnail status     # state

Candidate pictures produced OUTSIDE this pipeline (another agent's run) can
still be adopted via a **reconstructed run record** (`reconstructed: true`
in the run.json, water-ford precedent) — what matters: the run record +
provenance must describe the toolchain faithfully.

## Content intent (prose contract for candidates)

- Subject: an ore patch **kept for mining** — the mod's whole point is that
  ore remains visible, framed, and guarded while the factory builds around
  it. Positive imagery: drills + pumpjack on visible ore. Anti-imagery:
  sprawl covering ore, no recognizable patch.
- Palette: ore tones (copper/iron) vs factory steel; no water themes
  (that's water-ford's family, a different mod).
- No text-on-image.
- Gallery STILLS (portal page) come from real in-game screenshots (play-test
  session) — see journal session 4; generated art is for the thumbnail only.