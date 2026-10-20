-- families.lua — the single source of truth for what may be built over ore.
--
-- Everything descriptive about OreGuard's allowances lives here and only
-- here:
--   * family  -> entity.type allow-lists. Runtime matching is by TYPE, so
--     any entity of a listed type is allowed over ore, whatever mod owns it.
--   * tier    -> family compositions. settings.lua's oreguard-tier
--     allowed_values must mirror Families.tier_values exactly;
--     tools/check-families.py enforces the sync.
--   * the floating-text warning is composed from this list at event time
--     (display names: locale [oreguard-family]) — no hand-maintained
--     enumerations anywhere else.
--
-- Engine-owned rule we deliberately do NOT reimplement: pumpjacks are
-- type "mining-drill" whose prototype declares
-- `resource_categories = {"basic-fluid"}`, and resource prototypes carry a
-- matching `category` (crude-oil, lithium-brine, sulfuric-acid-geyser and
-- fluorine-vent are `basic-fluid`; solid ores are uncategorised or
-- `hard-solid`). The engine refuses pumpjack placement on category
-- mismatch before any event fires, so a pumpjack can only ever be placed
-- over pumpable resources "as normal". (SA's big-mining-drill rides the
-- same mechanism for `hard-solid` tungsten.)
--
-- See also data-final-fixes.lua: the ground-rail family's collision-layer
-- stamping is toggled by the startup setting oreguard-allow-ground-rail,
-- and the runtime guard only grants the family when that toggle is on.

local Families = {}

Families.list = {
  { id = "mining-drills", types = { "mining-drill" } },
  { id = "power-poles", types = { "electric-pole" } },
  { id = "belts", types = { "transport-belt", "underground-belt", "splitter" } },
  { id = "pipes", types = { "pipe", "pipe-to-ground" } },
  { id = "bot-logistics", types = { "roboport", "logistic-container" } },
  { id = "containers", types = { "container" } },
  { id = "beacons", types = { "beacon" } },
  { id = "furnaces", types = { "furnace" } },
  -- Ground rail is granted by NO tier: only the startup toggle
  -- oreguard-allow-ground-rail activates it (and, at data stage, stops the
  -- oreguard layer being stamped onto the rail prototypes — otherwise the
  -- engine refuses placement before the runtime guard could allow it).
  { id = "ground-rail", types = { "straight-rail", "half-diagonal-rail", "curved-rail-a", "curved-rail-b", "rail-signal", "rail-chain-signal", "train-stop" } },
  -- Display-only pseudo-family: no types, in no tier. control.lua appends
  -- it to the composed floating warning while the runtime toggle
  -- oreguard-allow-decorative-tiles is on, so the warning reflects that
  -- tile paving is allowed too.
  { id = "tiles", types = {} },
}

Families.tiers = {
  ["hardcore"] = { "mining-drills" },
  ["mining"] = { "mining-drills", "power-poles", "belts", "pipes" },
  ["bot-mining"] = { "mining-drills", "power-poles", "belts", "pipes", "bot-logistics" },
  ["default"] = { "mining-drills", "power-poles", "belts", "pipes", "bot-logistics", "containers", "beacons", "furnaces" },
}
Families.default_tier = "default"

-- Values mirrored by settings.lua (oreguard-tier allowed_values). The
-- stored value "mining" is kept from 0.3.x (locale-only relabel to
-- "Belt Mining") so no save migration is needed.
Families.tier_values = { "hardcore", "mining", "bot-mining", "default" }

return Families