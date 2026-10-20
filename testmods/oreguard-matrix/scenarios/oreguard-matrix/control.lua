-- OreGuard matrix level script (scenario side).
-- Curation-ONLY: runs on fresh --load-scenario generations (carves the lab
-- world, stamps fixtures, hard-offs enemies) and must stay minimal -- level
-- scripts are SNAPSHOT INTO SAVE FILES (lab/control.lua), so anything that
-- could ever need a fix belongs in the carrier MOD's control.lua instead,
-- which reloads from disk every session (journal session 8).
--
-- The behavior matrix itself lives in the carrier MOD's control.lua.
-- Lab-world spec: mods/oreguard/testing/LAB-WORLD.md.

-- OreGuard matrix level script (scenario side).
-- Curation-ONLY: this runs on fresh --load-scenario generations (carves the
-- lab world, stamps fixtures, hard-offs enemies) and must stay minimal —
-- level scripts are SNAPSHOT INTO SAVES (lab/control.lua), so anything that
-- would ever need a fix belongs in the carrier MOD's control.lua instead,
-- which reloads from disk every session (journal session 8).
--
-- The behavior matrix itself lives in the carrier MOD's control.lua.
-- Lab-world spec: mods/oreguard/testing/LAB-WORLD.md.

-- ---------------------------------------------------------------- lab world
-- Spec: mods/oreguard/testing/LAB-WORLD.md. Do not move fixtures without
-- moving the case positions below.

local GRASS = "grass-1"
local CARVE = { x0 = -150, y0 = -150, x1 = 150, y1 = 150 }

local FIXTURES = {
  iron   = { item = "iron-ore",   amount = 50000,  x0 = -18, x1 = -14, y0 = 0, y1 = 4 },
  copper = { item = "copper-ore", amount = 50000,  x0 = 10,  x1 = 14,  y0 = 0,  y1 = 4 },
  alley  = { item = "iron-ore",   amount = 50000,  x0 = -3,  x1 = 3,   y0 = -8, y1 = -8 },
}
-- oil wells: crude-oil is a 3x3 entity — one well per non-overlapping 3x3
-- block, at the block CENTER; pumpjack cases anchor the same center tiles.
local OIL_WELLS = { { 20, 0 }, { 24, 4 } }

-- power island (robot phase): EEI -> substation -> roboport (auto-wired);
-- placeable by hand in the curated save at exactly these coordinates, or
-- created by script if absent.
local POWER_ISLAND = {
  eei        = { -27, 12 },
  substation = { -25, 13 },
  roboport   = { -28, 14 },
  chest      = { -22, 13 },
  spare_chest = { -22, 15 },  -- steel chest next to the provider chest (safety net)
}

-- ------------------------------------------------------------ lab curation
-- Fresh-generation path only (a map-editor save carries the curated state in
-- storage + the world itself).

local function curate_world()
  -- purge natural resources until verifiably empty (explicit generous
  -- area — the unbounded filter form proved unreliable)
  for _ = 1, 5 do
    local leftovers = surface.find_entities_filtered({
      area = { { -4000, -4000 }, { 4000, 4000 } }, type = "resource" })
    if #leftovers == 0 then break end
    for _, ent in pairs(leftovers) do
      pcall(function() if ent.valid then ent.destroy() end end)
    end
  end
  local tiles = {}
  for x = CARVE.x0, CARVE.x1 do
    for y = CARVE.y0, CARVE.y1 do
      tiles[#tiles + 1] = { name = GRASS, position = { x, y } }
    end
  end
  surface.set_tiles(tiles, true)
  local to_destroy = {}
  for _, ent in pairs(surface.find_entities_filtered({
    area = { { CARVE.x0, CARVE.y0 }, { CARVE.x1, CARVE.y1 } } })) do
    if ent.type ~= "resource" and ent.name ~= "character" then
      to_destroy[#to_destroy + 1] = ent
    end
  end
  for _, ent in pairs(surface.find_entities_filtered({
    area = { { CARVE.x0, CARVE.y0 }, { CARVE.x1, CARVE.y1 } }, type = "resource" })) do
    to_destroy[#to_destroy + 1] = ent
  end
  for _, ent in pairs(to_destroy) do
    pcall(function() if ent.valid then ent.destroy() end end)
  end
  for _, fx in pairs(FIXTURES) do
    for x = fx.x0, fx.x1 do
      for y = fx.y0, fx.y1 do
        surface.create_entity({ name = fx.item, position = { x, y }, amount = fx.amount, force = "neutral" })
      end
    end
  end
  for _, c in ipairs(OIL_WELLS) do
    surface.create_entity({ name = "crude-oil", position = { c[1] + 0.5, c[2] + 0.5 }, amount = 100000, force = "neutral" })
  end
  -- power island: EEI + substation (roboport/chest land at matrix time)
  pcall(function()
    surface.create_entity({ name = "electric-energy-interface",
      position = { POWER_ISLAND.eei[1] + 0.5, POWER_ISLAND.eei[2] + 0.5 }, force = "player" })
    surface.create_entity({ name = "substation",
      position = { POWER_ISLAND.substation[1] + 0.5, POWER_ISLAND.substation[2] + 0.5 }, force = "player" })
  end)
  storage.oreguard_lab_curated = true
end



script.on_init(function()
  surface = game.get_surface(1)
  curate_world()
  pcall(function()
    game.forces["enemy"].kill_all_units()
    game.forces["enemy"].ai_controllable = false
    game.map_settings.enemy_expansion.enabled = false
    game.forces["enemy"].evolution_factor = 0
    local p = game.player or game.get_player(1)
    if p then p.force.set_cease_fire(game.forces.enemy) end
  end)
  for _, ent in pairs(surface.find_entities_filtered({ force = "enemy", limit = 1000 })) do
    pcall(function() ent.destroy() end)
  end
  log("MATRIX-LAB-CURATED (fresh generation; save via the editor for --lab runs)")
end)

-- periodic enemy sweep (kill-all-units + AI off + expansion off + destroy)
script.on_nth_tick(600, function()
  if surface then
    pcall(function()
      game.forces["enemy"].kill_all_units()
      game.forces["enemy"].ai_controllable = false
      game.map_settings.enemy_expansion.enabled = false
    end)
    for _, ent in pairs(surface.find_entities_filtered({ force = "enemy" })) do
      pcall(function() ent.destroy() end)
    end
  end
end)

-- ON LOAD: game is inaccessible here (deserialization-safe context; the
-- first lab load crashed exactly on a game.get_surface in on_load). Level
-- scripts have nothing to do on load -- no matrix, no state, no game.
script.on_load(function()
end)
