# Thumbnail — mod-portal image (drills ON the ore, factory OFF it)

**Delivery**: `mod/thumbnail.png`, 288×288 (@2× pixel density of the portal's
144×144 spec), built from a 512² generation master via LANCZOS.

## Intent (round 2 direction, per maintainer verdict on round 1)

A scene **painted in the gritty, semi-realistic in-game art style of the game
Factorio** — muted earthy industrial palette, hand-painted textures, soft
occlusion shadows — NOT the bold cartoon of round 1. Story beats that must
read at 144²:

- **Mining drills sit on the ore patch**, working, feeding transport belts.
- **The factory is kept clearly off the ore**: machines and buildings stand
  on plain dirt/paved ground well away from the patch, with a visible
  boundary between them.
- **A "keep off the ore" sign** marks the boundary: a rectangular metal sign
  on a post showing a grey assembling-machine silhouette inside a bold red
  prohibition circle with a diagonal slash — pictogram only, no words.
- The **engineer** appears as the in-game character
  (`reference/character.png`): dark gunmetal-grey power armor with bright
  orange visor and accents.
- No text, letters, logos, UI or watermarks anywhere else.

The sign is an explicit maintainer request (2026-10-20) and a deliberate
exception to the water-ford-era "no pictogram/UI-like elements" habit — it is
the one graphic symbol allowed.

## References (copies; sources in superproject `shared-assets/from-maintainer/`)

- `character.png` — the in-game engineer spritesheet (120×64); scoping source
  for the engineer's armor (gunmetal grey) and accent color (orange)
- `cartoonish-character.png` — round-1 carryover, kept for provenance only;
  round 2 does NOT stylize from it

## Predicted fragility (round 2)

- Naming "the game Factorio" in the prompt is the main style lever; watch for
  drift into generic sci-fi or back to cartoon on some seeds.
- The prohibition sign may sprout letters — every prompt states "no words"
  via the tail; check the sign on the contact sheet before adopting.
- Red prohibition circle vs red-tinted unbuildable ghosts (prompt 5) both use
  red; that is intentional (Factorio-authentic refusal color) but verify the
  sign still reads as a sign, not as UI chrome.
- Belt-around-ore remains a negative constraint — the factory-off-ore boundary
  is stated positively (machines "on plain dirt well away", "across a dirt
  track").

Variant map (round 2): 1 wide boundary+sign · 2 sign close-up · 3 aerial
boundary map · 4 engineer placing drill · 5 red ghost refusal · 6 copper
variant · 7 factory floor ends at the edge · 8 elevated rail bridge.

## Regeneration

`devctl mods art oreguard thumbnail generate` (offline dry-run: `--dry-run`).
Engine/VRAM facts: superproject `docs/ai-art-tooling.md`; process spec:
`docs/ai-art-briefs.md`.
