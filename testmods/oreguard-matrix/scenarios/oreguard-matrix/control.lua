-- OreGuard behavior-matrix scenario (see mods/oreguard/testing/PLAN.md).
--
-- LAB WORLD: on_init destroys every natural resource and every non-resource
-- entity, flattens a large rect to grass, then stamps exact ore fixtures —
-- so any tile outside a fixture is legal to build on by construction, and
-- every patch sits at a known coordinate.
--
-- PLAYER CASES: a scripted player (game.create_player) teleports next to the
-- target, puts the case item on the cursor, and calls player.build_from_cursor
-- — the REAL placement path, so OreGuard's on_built_entity /
-- on_player_built_tile handlers run for real. Assertion happens on the NEXT
-- tick via entity presence + item-flow bookkeeping (the case item always
-- starts with main-count 0):
--   placed          — entity exists, cursor emptied, main stays 0
--   guard-blocked   — entity destroyed by the guard, main == 1 (handler
--                     returned the item)
--   engine-refused  — cursor still holds the item, main 0, no entity (no
--                     event ever fired — collision layer / engine rule)
--   skip            — case item unavailable (DLC data?) — recorded, not failed
--
-- ROBOT CASES: roboport (energy topped up every tick — no EEI/network needed,
-- LuaEntity.energy is writable) + provider chest + script-created
-- entity-ghost made bot-buildable via an item-request-proxy. Driver asserts
-- ore-zone occupancy after the proxy is consumed.
--
-- INSTANCE BRANCH: the same scenario serves both runner instances; the case
-- table branches on the STARTUP setting oreguard-allow-ground-rail
-- (run-matrix.py seeds instance B's mod-settings.dat — the settings persist
-- in that file, which is precisely why seeding works).
--
-- Results: script-output/oreguard-matrix.json (+ MATRIX-RESULTS log line at
-- the end). Teardown (RCON /quit) and the pass/fail exit code belong to
-- testing/run-matrix.py.

local RESULTS_FILE = "oreguard-matrix.json"

-- ---------------------------------------------------------------- lab world

local GRASS = "grass-1"
local CARVE = { x0 = -150, y0 = -150, x1 = 150, y1 = 150 }

-- ore fixtures (script-placed at exact coordinates, 1x1 resource entities)
local FIXTURES = {
  iron   = { item = "iron-ore",   amount = 50000,  x0 = -18, x1 = -14, y0 = 0, y1 = 4 },
  copper = { item = "copper-ore", amount = 50000,  x0 = 10,  x1 = 14,  y0 = 0, y1 = 4 },
  oil    = { item = "crude-oil",  amount = 100000, x0 = 20,  x1 = 22,  y0 = -1, y1 = 1 },
  alley  = { item = "iron-ore",   amount = 50000,  x0 = -3,  x1 = 3,   y0 = -8, y1 = -8 },
}

local cases = { passed = 0, failed = 0, skipped = 0, failures = {}, records = {} }
local surface
local player
local queue
local q_index = 0
local stage = ""                -- "setup" -> "assert" alternation per case
local current_case
local current_main_before
local robot_case_index = 0
local robot_proxy
local robot_wait_until
local done = false

-- ------------------------------------------------------------- case tables
-- Tiers: hardcore -> drills only; mining -> +poles/belts/pipes; bot-mining ->
-- +roboports/logistic-chests; default -> +containers/beacons/furnaces.
-- (families.lua is the contract; the expected column encodes it here so any
-- drift shows up as a matrix failure.)

local PLAYER_CASES_A = {
  -- drills & pumpjacks: allowed over ore at every tier
  { id = "drill-iron-hc",    area = "iron",   pos = { -16, 2 }, item = "electric-mining-drill", tier = "hardcore", expected = "placed" },
  { id = "drill-iron-df",    area = "iron",   pos = { -15, 3 }, item = "electric-mining-drill", tier = "default",  expected = "placed" },
  { id = "drill-copper-mi",  area = "copper", pos = { 12, 2 },  item = "electric-mining-drill", tier = "mining",   expected = "placed" },
  { id = "pumpjack-oil-hc",  area = "oil",    pos = { 21, 0 },  item = "pumpjack",              tier = "hardcore", expected = "placed" },
  { id = "pumpjack-oil-df",  area = "oil",    pos = { 21, 1 },  item = "pumpjack",              tier = "default",  expected = "placed" },
  -- engine canary: pumpjack over a solid resource is refused by the ENGINE
  -- before any event fires (resource_categories rule; session-2 finding)
  { id = "pumpjack-iron-hc", area = "iron",   pos = { -17, 1 }, item = "pumpjack",              tier = "hardcore", expected = "engine-refused" },
  { id = "pumpjack-iron-df", area = "iron",   pos = { -14, 4 }, item = "pumpjack",              tier = "default",  expected = "engine-refused" },
}

-- tiered families: blocked in tiers that omit the family, placed in those
-- that grant it
local TIERED = {
  { item = "electric-pole",          min_tier = 2 },
  { item = "transport-belt",         min_tier = 2 },
  { item = "underground-belt",       min_tier = 2 },
  { item = "splitter",               min_tier = 2 },
  { item = "pipe",                   min_tier = 2 },
  { item = "pipe-to-ground",         min_tier = 2 },
  { item = "roboport",               min_tier = 3 },
  { item = "logistic-chest-storage", min_tier = 3 },
  { item = "iron-chest",             min_tier = 4 },
  { item = "beacon",                 min_tier = 4 },
  { item = "stone-furnace",          min_tier = 4 },
}
local TIER_ORDER = { "hardcore", "mining", "bot-mining", "default" }
local TIER_INDEX = { hardcore = 1, mining = 2, ["bot-mining"] = 3, default = 4 }
for _, spec in ipairs(TIERED) do
  for _, tier in ipairs(TIER_ORDER) do
    PLAYER_CASES_A[#PLAYER_CASES_A + 1] = {
      id = spec.item .. "-" .. tier,
      area = "iron", pos = { -14, 2 },  -- one anchor row; cleanups isolate cases
      item = spec.item, tier = tier,
      expected = TIER_INDEX[tier] >= spec.min_tier and "placed" or "guard-blocked",
    }
  end
end

-- rail family at toggle-OFF: ground rails carry the oreguard layer, so the
-- ENGINE refuses them; signal-type entities were never stamped and reach the
-- runtime guard instead
local RAIL_A = {
  { id = "straight-rail-hc", area = "alley", pos = { -2, -8 },  item = "straight-rail",     tier = "hardcore", expected = "engine-refused" },
  { id = "straight-rail-df", area = "alley", pos = { 2, -8 },   item = "straight-rail",     tier = "default",  expected = "engine-refused" },
  { id = "rail-signal-hc",   area = "alley", pos = { -1, -8 },  item = "rail-signal",       tier = "hardcore", expected = "guard-blocked" },
  { id = "rail-signal-df",   area = "alley", pos = { 0, -8 },   item = "rail-signal",       tier = "default",  expected = "guard-blocked" },
  { id = "rail-chain-df",    area = "alley", pos = { 1, -8 },   item = "rail-chain-signal", tier = "default",  expected = "guard-blocked" },
  { id = "train-stop-df",    area = "alley", pos = { -3, -8 },  item = "train-stop",        tier = "default",  expected = "guard-blocked" },
  -- elevation-friendly prototypes: name-exempt in every tier; ON ore so the
  -- exemption is what's tested (not a vacuous no-ore placement)
  { id = "elevated-rail-hc", area = "alley", pos = { 3, -8 },   item = "elevated-rail",     tier = "hardcore", expected = "placed" },
  { id = "rail-support-df",  area = "alley", pos = { 0, -8 },   item = "rail-support",      tier = "default",  expected = "placed" },
  { id = "rail-ramp-df",     area = "alley", pos = { 1, -8 },   item = "rail-ramp",         tier = "default",  expected = "placed" },
}
for _, cas in ipairs(RAIL_A) do
  PLAYER_CASES_A[#PLAYER_CASES_A + 1] = cas
end

-- tiles: the tile guard honors only the decorative-tiles toggle (runtime
-- global; the case driver flips it). Tile cases reuse one anchor each.
local TILE_CASES_A = {
  { id = "landfill-off-hc",  area = "iron", pos = { -14, 0 }, item = "landfill",         tiles = false, expected = "guard-blocked" },
  { id = "landfill-off-df",  area = "iron", pos = { -15, 0 }, item = "landfill",         tiles = false, expected = "guard-blocked" },
  { id = "landfill-on-df",   area = "iron", pos = { -16, 1 }, item = "landfill",         tiles = true,  expected = "placed" },
  { id = "concrete-off-df",  area = "iron", pos = { -17, 2 }, item = "refined-concrete", tiles = false, expected = "guard-blocked" },
  { id = "concrete-on-hc",   area = "iron", pos = { -18, 1 }, item = "refined-concrete", tiles = true,  expected = "placed" },
}
for _, cas in ipairs(TILE_CASES_A) do
  PLAYER_CASES_A[#PLAYER_CASES_A + 1] = cas
end

-- no-ore control zone: the guard must never fire off-ore
local CONTROL_CASES = {
  { id = "furnace-control-hc",  pos = { -1, 7 }, item = "stone-furnace", tier = "hardcore", expected = "placed" },
  { id = "roboport-control-hc", pos = { 2, 7 },  item = "roboport",      tier = "hardcore", expected = "placed" },
  { id = "beacon-control-hc",   pos = { -2, 7 }, item = "beacon",        tier = "hardcore", expected = "placed" },
  { id = "landfill-control-hc", pos = { 1, 7 },  item = "landfill",      tier = "hardcore", expected = "placed", tiles = true },
}
for _, cas in ipairs(CONTROL_CASES) do
  PLAYER_CASES_A[#PLAYER_CASES_A + 1] = cas
end

-- instance B (startup toggle on): rails place at any tier
local PLAYER_CASES_B = {
  { id = "b-rail-hc",   area = "alley", pos = { -2, -8 }, item = "straight-rail",     tier = "hardcore", expected = "placed" },
  { id = "b-rail-df",   area = "alley", pos = { 2, -8 },  item = "straight-rail",     tier = "default",  expected = "placed" },
  { id = "b-signal-hc", area = "alley", pos = { -1, -8 }, item = "rail-signal",      tier = "hardcore", expected = "placed" },
  { id = "b-chain-df",  area = "alley", pos = { 1, -8 },  item = "rail-chain-signal", tier = "default",  expected = "placed" },
  { id = "b-stop-df",   area = "alley", pos = { -3, -8 }, item = "train-stop",       tier = "default",  expected = "placed" },
}

-- robot cases (instance A): real robots via item-request-proxy
local ROBOT_CASES = {
  { id = "robot-assembler-hc", area = "iron", pos = { -18, 0 }, item = "assembling-machine-1", tier = "hardcore", expected = "guard-blocked" },
  { id = "robot-belt-mi",      area = "iron", pos = { -17, 1 }, item = "transport-belt",       tier = "mining",   expected = "placed" },
  { id = "robot-solar-df",     area = "iron", pos = { -16, 2 }, item = "solar-panel",          tier = "default",  expected = "guard-blocked" },
  { id = "robot-drill-hc",     area = "iron", pos = { -19, 3 }, item = "electric-mining-drill", tier = "hardcore", expected = "placed" },
}
local ROBOT_SETTLE_TICKS = 2400

-- ---------------------------------------------------------------- harness

local function write_results()
  cases.done = done
  helpers.write_file(RESULTS_FILE, helpers.table_to_json(cases) .. "\n", false, 0)
  if done then
    log(string.format("MATRIX-RESULTS passed=%d failed=%d skipped=%d",
      cases.passed, cases.failed, cases.skipped))
  end
end

local function record(rec)
  cases.records[#cases.records + 1] = rec
  if rec.pass == true then
    cases.passed = cases.passed + 1
  elseif rec.pass == false then
    cases.failed = cases.failed + 1
    cases.failures[#cases.failures + 1] = rec.id .. ": " .. tostring(rec.detail)
  else
    cases.skipped = cases.skipped + 1
  end
end

local function set_tier(tier)
  if settings.global["oreguard-tier"].value ~= tier then
    settings.global["oreguard-tier"] = { value = tier }
  end
end

local function set_tiles_toggle(on)
  if settings.global["oreguard-allow-decorative-tiles"].value ~= on then
    settings.global["oreguard-allow-decorative-tiles"] = { value = on }
  end
end

local function clear_rect(x, y, reach)
  local area = { { x - reach, y - reach }, { x + reach, y + reach } }
  for _, ent in pairs(surface.find_entities_filtered({ area = area })) do
    pcall(function()
      if ent.type ~= "resource" and ent.valid and ent.name ~= "character" then
        ent.destroy()
      end
    end)
  end
end

local function restore_grass(x, y)
  surface.set_tiles({ { name = GRASS, position = { x, y } } }, true)
end

local function placed_entity_present(cas)
  local area = { { cas.pos[1] - 0.49, cas.pos[2] - 0.49 }, { cas.pos[1] + 0.49, cas.pos[2] + 0.49 } }
  -- tile items: the "built" state is the surface tile itself — paved means
  -- the tile is no longer the carved grass; guard-blocked restores grass.
  if prototypes.tile[cas.item] then
    local tile = surface.get_tile(cas.pos[1], cas.pos[2])
    return tile and tile.name ~= GRASS
  end
  local ptype = nil
  local proto = prototypes.item[cas.item]
  if proto and proto.place_result then ptype = proto.place_result.type end
  if ptype then
    if #surface.find_entities_filtered({ area = area, type = ptype }) > 0 then return true end
  end
  for _, ent in pairs(surface.find_entities_filtered({ area = area })) do
    if ent.type ~= "resource" then return true end
  end
  return false
end

-- per player case: stage 1 (setup+build) runs on one tick, stage 2
-- (assert+cleanup) on the next — the guard's event handler has then run.
local function case_setup(cas)
  current_case = cas
  clear_rect(cas.pos[1], cas.pos[2], 3)
  restore_grass(cas.pos[1], cas.pos[2])
  if cas.tier then set_tier(cas.tier) end
  if cas.tiles ~= nil then set_tiles_toggle(cas.tiles) end

  -- deterministic bookkeeping: cursor cleaned, main stripped of the case item
  player.clean_cursor()
  local leftovers = player.get_main_inventory().get_item_count(cas.item)
  if leftovers > 0 then
    player.remove_item({ name = cas.item, count = leftovers })
  end
  current_main_before = 0

  if not prototypes.item[cas.item] then
    stage = "assert"
    return -- recorded as skip in the assert stage
  end
  player.teleport({ cas.pos[1] + 3, cas.pos[2] + 3 })
  player.cursor_stack.set_stack({ name = cas.item, count = 1 })
  player.build_from_cursor({ position = { cas.pos[1], cas.pos[2] }, direction = defines.direction.north })
  stage = "assert"
end

local function case_assert(cas)
  local main_inv = player.get_main_inventory()
  local main_after = main_inv.get_item_count(cas.item)
  local cursor_holds = player.cursor_stack ~= nil
    and player.cursor_stack.valid_for_read and player.cursor_stack.name == cas.item
    and player.cursor_stack.count > 0 and true or false
  local present = placed_entity_present(cas)

  local rec = { id = cas.id, expected = cas.expected }
  if not prototypes.item[cas.item] then
    rec.pass = nil
    rec.got = "skip"
    rec.detail = "item prototype absent (elevated-rails data?)"
  else
    local got
    if cas.expected == "placed" then
      got = present and main_after == current_main_before and not cursor_holds and "placed" or "other"
    elseif cas.expected == "guard-blocked" then
      got = (not present) and main_after == current_main_before + 1 and "guard-blocked" or "other"
    elseif cas.expected == "engine-refused" then
      got = (not present) and cursor_holds and main_after == current_main_before and "engine-refused" or "other"
    end
    rec.got = got or "other"
    rec.pass = rec.got == cas.expected
    rec.detail = string.format("present=%s main_after=%d cursor=%s",
      tostring(present), main_after, tostring(cursor_holds))
  end
  record(rec)

  -- cleanup for the next case
  player.clean_cursor()
  local back = main_inv.get_item_count(cas.item)
  if back > 0 then player.remove_item({ name = cas.item, count = back }) end
  clear_rect(cas.pos[1], cas.pos[2], 3)
  restore_grass(cas.pos[1], cas.pos[2])
end

-- robot infrastructure: roboport with per-tick energy top-up (no electric
-- network needed), provider chest stocked per case.
local robot_infra
local function robot_ticker()
  if robot_infra and robot_infra.roboport and robot_infra.roboport.valid then
    robot_infra.roboport.energy = 100000000
  end
end

local function robot_case_setup(cas)
  robot_case_index = robot_case_index + 1
  set_tier(cas.tier)
  clear_rect(cas.pos[1], cas.pos[2], 3)
  restore_grass(cas.pos[1], cas.pos[2])
  if not robot_infra.chest.insert({ name = cas.item, count = 2 }) then
    record({ id = cas.id, pass = false, detail = "chest insert refused" })
    return nil
  end
  local ghost = surface.create_entity({
    name = "entity-ghost", inner_name = cas.item,
    position = { cas.pos[1] + 0.5, cas.pos[2] + 0.5 }, force = "player",
  })
  if not ghost or not ghost.valid then
    record({ id = cas.id, pass = false, detail = "ghost creation failed" })
    return nil
  end
  robot_proxy = surface.create_entity({
    name = "item-request-proxy", target = ghost, position = ghost.position,
    force = "player", inventory = { { name = cas.item, count = 1 } },
  })
  return true
end

local function robot_case_assert(cas)
  local present = placed_entity_present(cas)
  record({
    id = cas.id, expected = cas.expected,
    pass = present == (cas.expected == "placed"),
    got = present and "placed" or "absent",
    detail = "robot path (proxy-driven)",
  })
end

-- ------------------------------------------------------------- lifecycle

script.on_init(function()
  surface = game.get_surface(1)

  -- lab world curation
  for _, ent in pairs(surface.find_entities_filtered({ force = "enemy" })) do
    pcall(function() ent.destroy() end)
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
  for _, ent in pairs(surface.find_entities_filtered({ type = "resource" })) do
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

  player = game.create_player("matrix")
  player.force.set_cease_fire(game.forces.enemy)
  game.forces.enemy.set_cease_fire(player.force)

  local seeded = settings.startup["oreguard-allow-ground-rail"].value
  record({
    id = "seed-rail-toggle", pass = true, got = seeded and "on" or "off",
    detail = "startup oreguard-allow-ground-rail at scenario init: " .. tostring(seeded),
  })

  if seeded then
    queue = PLAYER_CASES_B
  else
    queue = PLAYER_CASES_A
    robot_infra = {}
  end
  stage = "next"
  write_results()
  log(string.format("MATRIX-READY cases=%d railtoggle=%s oreguard=%s",
    #queue, tostring(seeded), tostring(script.active_mods["oreguard"])))
end)

script.on_nth_tick(600, function()
  if surface then
    for _, ent in pairs(surface.find_entities_filtered({ force = "enemy" })) do
      pcall(function() ent.destroy() end)
    end
  end
end)

script.on_tick(function()
  if done then return end
  if stage == "next" then
    q_index = q_index + 1
    local cas = queue[q_index]
    if cas then
      case_setup(cas)
      stage = "assert"
    elseif not seeded_rail() then
      -- player queue exhausted -> robot phase (instance A only)
      if not robot_infra.roboport then
        local ok1 = surface.create_entity({ name = "roboport", position = { -22, 12 }, force = "player" })
        local ok2 = surface.create_entity({
          name = "logistic-chest-passive-provider", position = { -20, 13 }, force = "player" })
        robot_infra.roboport = ok1
        robot_infra.chest = ok2
        if not ok1 or not ok2 then
          for _, cas in ipairs(ROBOT_CASES) do
            record({ id = cas.id, pass = false, detail = "robot infra setup failed" })
          end
          done = true
          write_results()
          return
        end
      end
      robot_case_index = 0
      stage = "robot-next"
    else
      done = true
      write_results()
      return
    end
  elseif stage == "assert" then
    case_assert(current_case)
    stage = "next"
  elseif stage == "robot-next" then
    robot_ticker()
    robot_case_index = robot_case_index + 1
    local cas = ROBOT_CASES[robot_case_index]
    if not cas then
      done = true
      write_results()
      return
    end
    if robot_case_setup(cas) then
      current_case = cas
      robot_wait_until = game.tick + ROBOT_SETTLE_TICKS
      stage = "robot-wait"
    else
      -- failed setup already recorded; move on next tick
    end
  elseif stage == "robot-wait" then
    robot_ticker()
    local proxy_gone = not (robot_proxy and robot_proxy.valid)
    if proxy_gone or game.tick >= robot_wait_until then
      if not proxy_gone then
        pcall(function() if robot_proxy and robot_proxy.valid then robot_proxy.destroy() end end)
      end
      robot_case_assert(current_case)
      stage = "robot-next"
    end
  end
end)

function seeded_rail()
  local ok, v = pcall(function() return settings.startup["oreguard-allow-ground-rail"].value end)
  if ok then return v end
  return false
end