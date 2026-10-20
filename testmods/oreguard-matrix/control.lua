-- OreGuard behavior-matrix DRIVER (mod control script).
-- Mod scripts reload FROM DISK every session — every fix lands without
-- re-cutting saves (the key lesson of the first lab run: level scripts are
-- frozen inside save files, see journal session 8). The lab WORLD is curated
-- by the level script on fresh generation (scenarios/oreguard-matrix/
-- control.lua) or by hand in the map editor (testing/LAB-WORLD.md); a
-- curated save is adopted as-is.
--
local RESULTS_FILE = "oreguard-matrix.json"

-- ---------------------------------------------------------------- lab world
-- Spec: mods/oreguard/testing/LAB-WORLD.md. Do not move fixtures without
-- moving the case positions below.

local GRASS = "grass-1"
local CARVE = { x0 = -150, y0 = -150, x1 = 150, y1 = 150 } -- spec: LAB-WORLD.md

local FIXTURES = {
  iron   = { item = "iron-ore",   amount = 50000,  x0 = -18, x1 = -14, y0 = 0, y1 = 4 },
  copper = { item = "copper-ore", amount = 50000,  x0 = 10,  x1 = 14,  y0 = 0,  y1 = 4 },
  -- widened 2026-10-20 (probe rounds 9–15): the rail-case entities (signals,
  -- chain, train-stop) place at tiles 1.5-2 rows off the track lines, so the
  -- strip needs vertical depth for their footprints to be over ore.
  alley  = { item = "iron-ore",   amount = 50000,  x0 = -3,  x1 = 3,   y0 = -10, y1 = -6 },
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
  spare_chest = { -22, 15 },  -- storage chest next to the provider chest (bot drop-off safety net)
}

-- ---------------------------------------------------------------- harness

local strsub = string.sub
local results = { passed = 0, failed = 0, skipped = 0, failures = {}, records = {} }
local surface
local player
local player_done = false      -- no player at all (headless) -> skips once
local player_grace_until
local queue
local q_index = 0
local stage = ""               -- next / assert / robot-*
local current_case
local unbuildable_reason
local main_before = 0
local robot_infra = {}
local robot_case_index = 0
local robot_ghost
local robot_wait_until
local case_wait_until
local done = false
local robot_infra_done = false
local pending_censuses = {}    -- deferred { until_tick, item, site } after robot cases
local last_harness_err
local DRIVER_REVISION = 25
local function seeded_rail()
  local ok, v = pcall(function() return settings.startup["oreguard-allow-ground-rail"].value end)
  if ok then return v == true end
  return false
end


local function write_results()
  results.done = done
  -- windowed sessions may lack a script-output dir (write_file fails
  -- silently) — the log lines are the authoritative record; the runner
  -- parses factorio-current.log for MATRIX-RESULTS / MATRIX-CASE.
  helpers.write_file(RESULTS_FILE, helpers.table_to_json(results) .. "\n", false, 0)
  if done then
    log(string.format("MATRIX-RESULTS passed=%d failed=%d skipped=%d",
      results.passed, results.failed, results.skipped))
  end
end

local function record(rec)
  results.records[#results.records + 1] = rec
  log("MATRIX-CASE " .. helpers.table_to_json(rec))
  if rec.pass == true then
    results.passed = results.passed + 1
  elseif rec.pass == false then
    results.failed = results.failed + 1
    results.failures[#results.failures + 1] = rec.id .. ": " .. tostring(rec.detail)
  else
    results.skipped = results.skipped + 1
  end
end

local function set_tier(tier)
  -- settings writes are owner-only; drive them through OreGuard's remote
  -- interface (executes in OreGuard's own ownership context)
  local ok = pcall(function()
    remote.call("oreguard", "set_tier", tier)
  end)
  if not ok then log("OreGuard matrix: remote set_tier failed") end
end

local function set_tiles_toggle(on)
  local ok = pcall(function()
    remote.call("oreguard", "set_tiles_toggle", on)
  end)
  if not ok then log("OreGuard matrix: remote set_tiles_toggle failed") end
end

local function clear_rect(x, y, reach)
  local area = { { x - reach, y - reach }, { x + reach, y + reach } }
  for _, ent in pairs(surface.find_entities_filtered({ area = area })) do
    pcall(function()
      -- spare drones: the carrying drone of the previous blocked build idles
      -- right at the old build site; the next case's cleanup must not kill it
      if ent.type ~= "resource" and ent.valid and ent.name ~= "character"
          and ent.type ~= "construction-robot" and ent.type ~= "logistic-robot" then
        ent.destroy()
      end
    end)
  end
end

-- (rail ensure call lives below; forward-gated by the nil check in case_setup)

local function restore_grass(x, y)
  surface.set_tiles({ { name = GRASS, position = { x, y } } }, true)
end

TILE_DEBUG = "?"

local function placed_entity_present(cas)
  local area = { { cas.pos[1] - 0.49, cas.pos[2] - 0.49 }, { cas.pos[1] + 0.49, cas.pos[2] + 0.49 } }
  -- tile items: "built" state is the surface tile itself — paved != grass;
  -- guard-blocked restores grass.
  if cas.tile_name then
    local tile = surface.get_tile(cas.pos[1], cas.pos[2])
    TILE_DEBUG = tile and tile.name or "?"
    return tile and tile.name == cas.tile_name
  end
  if prototypes.tile[cas.item] then
    local tile = surface.get_tile(cas.pos[1], cas.pos[2])
    TILE_DEBUG = tile and tile.name or "?"
    return tile and tile.name ~= GRASS
  end
  local ptype = nil
  local proto = prototypes.item[cas.item]
  if proto and proto.place_result then ptype = proto.place_result.type end
  if ptype then
    -- rail-attached entities land at tile-grid positions 0.5-1 off the case
    -- tile (probed: signals at tile centers, stops at tile corners); widen
    -- the collision-window for them (the filter matches collision overlap)
    local reach = RAIL_ATTACHED and RAIL_ATTACHED[cas.item] and 1.6 or 0.49
    if #surface.find_entities_filtered({
        area = { { cas.pos[1] - reach, cas.pos[2] - reach },
                 { cas.pos[1] + reach, cas.pos[2] + reach } },
        type = ptype }) > 0 then return true end
  end
  -- generic fallback: any non-resource entity. NOT used for rail-attached
  -- items — the fixture rails legitimately sit inside the window (their
  -- bodies overhang the case tile) and only the ptype scan above is
  -- definitive for signals/stops.
  if not (RAIL_ATTACHED and RAIL_ATTACHED[cas.item]) then
    for _, ent in pairs(surface.find_entities_filtered({ area = area })) do
      if ent.type ~= "resource" then return true end
    end
  end
  return false
end

-- per player case: stage 1 (setup+build) on one tick, stage 2 (assert+cleanup)
-- on the next — the guard's event handler has then definitely run.
-- 2.x removed LuaPlayer.clean_cursor — clear via stack clear / put-back
local function clear_player_cursor()
  local ok = pcall(function() return player.clear_cursor() end)   -- 1.x spelling
  if not ok then
    local cs = player.cursor_stack
    if cs and cs.valid_for_read then
      pcall(function()
        player.insert({ name = cs.name, count = cs.count })  -- put back first
      end)
      pcall(function() cs.clear() end)
    end
  end
end

local function case_setup(cas)
  current_case = cas
  unbuildable_reason = nil
  clear_rect(cas.pos[1], cas.pos[2], 3)
  restore_grass(cas.pos[1], cas.pos[2])
  if RAIL_ATTACHED and RAIL_ATTACHED[cas.item] and ensure_rail_infra then
    ensure_rail_infra() -- the clear above wipes nearby fixture rails; re-lay
  end
  if cas.tier then set_tier(cas.tier) end
  if cas.tiles ~= nil then set_tiles_toggle(cas.tiles) end

  clear_player_cursor()
  if not prototypes.item[cas.item] then
    main_before = 0
    return -- recorded as skip in the assert stage
  end
  main_before = player.get_main_inventory().get_item_count(cas.item)
  player.teleport({ cas.pos[1] + 3, cas.pos[2] + 3 })
  local cs_ok = pcall(function()
    player.cursor_stack.set_stack({ name = cas.item, count = 1 })
  end)
  if not cs_ok then
    unbuildable_reason = "cursor_stack refused the item (planner-only rails?)"
    return
  end
  local build_pos = cas.tile_name
    and { cas.pos[1] + 0.5, cas.pos[2] + 0.5 } or { cas.pos[1], cas.pos[2] }
  local diag_ok, diag = pcall(function()
    local proto = prototypes.entity[
        prototypes.item[cas.item] and prototypes.item[cas.item].place_result or cas.item]
    local sm = proto and proto.collision_mask and proto.collision_mask.layers or {}
    local res = surface.find_entities_filtered({
        area = { { build_pos[1] - 0.5, build_pos[2] - 0.5 }, { build_pos[1] + 0.5, build_pos[2] + 0.5 } },
        type = "resource" })
    local rm = res[1] and res[1].prototype.collision_mask.layers or {}
    local smn, rmn = {}, {}
    for k in pairs(sm) do smn[#smn + 1] = k end
    for k in pairs(rm) do rmn[#rmn + 1] = k end
    local extra = ""
    if RAIL_ATTACHED[cas.item] then
      local rails = surface.find_entities_filtered({
        area = { { build_pos[1] - 1, build_pos[2] - 1 }, { build_pos[1] + 2, build_pos[2] + 2 } },
        type = "straight-rail" })
      local rdesc = {}
      for _, r in ipairs(rails) do
        rdesc[#rdesc + 1] = string.format("(%.1f,%.1f/d%d)", r.position.x, r.position.y, r.direction)
      end
      extra = " rails=" .. table.concat(rdesc, " ")
        .. " can_corner_e=" .. tostring(player.can_place_entity({
            name = cas.item, position = build_pos, direction = defines.direction.east }))
        .. " can_center_e=" .. tostring(player.can_place_entity({
            name = cas.item, position = { build_pos[1] + 0.5, build_pos[2] + 0.5 },
            direction = defines.direction.east }))
        .. " can_corner_w=" .. tostring(player.can_place_entity({
            name = cas.item, position = build_pos, direction = defines.direction.west }))
        .. " can_center_w=" .. tostring(player.can_place_entity({
            name = cas.item, position = { build_pos[1] + 0.5, build_pos[2] + 0.5 },
            direction = defines.direction.west }))
    end
    return string.format("can_place=%s sig-mask=[%s] ore-mask=[%s]%s",
        tostring(player.can_place_entity({ name = cas.item, position = build_pos })),
        table.concat(smn, " "), table.concat(rmn, " "), extra)
  end)
  log("MATRIX-MASK-DIAG " .. cas.id .. ": " .. tostring(diag))
  local build_dir, build_pt = defines.direction.north, build_pos
  if RAIL_ATTACHED[cas.item] then
    -- 2.x rail-lattice directions (probed 2026-10-20): raw values 0-6 select
    -- the attachment class; dir 2 works for signals on the NS-class pieces,
    -- dir 4/6 for stops on the EW-class line. The 16-way defines.direction
    -- names (east=4...) collide with these raw values — do not use them here.
    for _, combo in ipairs({ { 2, build_pos },
                             { 2, { build_pos[1] + 0.5, build_pos[2] + 0.5 } },
                             { 4, build_pos },
                             { 4, { build_pos[1] + 0.5, build_pos[2] + 0.5 } },
                             { 6, build_pos },
                             { 6, { build_pos[1] + 0.5, build_pos[2] + 0.5 } },
                             { 0, build_pos },
                             { 0, { build_pos[1] + 0.5, build_pos[2] + 0.5 } } }) do
      if player.can_place_entity({ name = cas.item, position = combo[2],
          direction = combo[1] }) then
        build_pt, build_dir = combo[2], combo[1]
        log("MATRIX-BUILD-PICK " .. cas.id .. " d" .. combo[1])
        break
      end
    end
  end
  local built_ok = pcall(function()
    player.build_from_cursor({ position = build_pt, direction = build_dir })
  end)
  if not built_ok then
    unbuildable_reason = "build_from_cursor refused (engine unknown-item/other)"
    return
  end
  if prototypes.tile[cas.item] then
    log(string.format("MATRIX-DIAG %s build-tick tile=%s main=%d toggle=%s",
      cas.id, tostring(surface.get_tile(cas.pos[1], cas.pos[2]).name),
      player.get_main_inventory().get_item_count(cas.item),
      tostring(settings.global["oreguard-allow-decorative-tiles"].value)))
  end
  case_wait_until = game.tick + 4
  stage = "pre-assert"
end

local function case_assert(cas)
  local rec = { id = cas.id, expected = cas.expected }
  if unbuildable_reason or not prototypes.item[cas.item] then
    rec.pass = nil
    rec.got = "skip"
    rec.detail = unbuildable_reason or "item prototype absent (planner-rails / DLC data?)"
    record(rec)
    clear_player_cursor()
    clear_rect(cas.pos[1], cas.pos[2], 3)
    restore_grass(cas.pos[1], cas.pos[2])
    return
  end
  local main_inv = player.get_main_inventory()
  local main_after = main_inv.get_item_count(cas.item)
  local cursor_holds = player.cursor_stack ~= nil
    and player.cursor_stack.valid_for_read and player.cursor_stack.name == cas.item
    and player.cursor_stack.count > 0 and true or false
  local present = placed_entity_present(cas)

  if not prototypes.item[cas.item] then
    rec.pass = nil
    rec.got = "skip"
    rec.detail = "item prototype absent (planner-placed rails / DLC data?)"
  else
    local got
    if cas.expected == "placed" then
      got = present and main_after == main_before and not cursor_holds and "placed" or "other"
    elseif cas.expected == "guard-blocked" then
      got = (not present) and main_after == main_before + 1 and "guard-blocked" or "other"
    elseif cas.expected == "engine-refused" then
      got = (not present) and cursor_holds and main_after == main_before and "engine-refused" or "other"
    end
    rec.got = got or "other"
    rec.pass = rec.got == cas.expected
    rec.detail = string.format("present=%s main_before=%d main_after=%d cursor=%s tile=%s",
      tostring(present), main_before, main_after, tostring(cursor_holds), tostring(TILE_DEBUG))
  end
  record(rec)

  clear_player_cursor()
  local back = main_inv.get_item_count(cas.item)
  if back > 0 then player.remove_item({ name = cas.item, count = back }) end
  clear_rect(cas.pos[1], cas.pos[2], 3)
  restore_grass(cas.pos[1], cas.pos[2])
end

local function robot_ticker()
  for _, key in ipairs({ "roboport", "eei" }) do
    local ent = robot_infra[key]
    if ent and ent.valid then
      pcall(function() ent.energy = 100000000 end)
    end
  end
end

local function find_or_create_entity(name, position)
  local found = surface.find_entities_filtered({
    area = { { position[1] - 0.49, position[2] - 0.49 }, { position[1] + 0.49, position[2] + 0.49 } },
    name = name,
  })
  if #found > 0 then return found[1] end
  local pos = { position[1] + 0.5, position[2] + 0.5 }
  if surface.get_tile(position[1], position[2]).name == "water" then
    surface.set_tiles({ { name = GRASS, position = { position[1], position[2] } } }, true)
  end
  return surface.create_entity({ name = name, position = pos, force = "player" })
end

local function robot_infra_setup()
  for key, pos in pairs(POWER_ISLAND) do
    local name = ({ eei = "electric-energy-interface", substation = "substation",
                    roboport = "roboport", chest = "passive-provider-chest",
                    spare_chest = "storage-chest" })[key]
    local ent = find_or_create_entity(name, pos)
    if not ent or not ent.valid then
      return false, "could not create/adopt " .. name
    end
    robot_infra[key] = ent
  end
  -- roboports only fly bots inserted into them — stock it (the user's save
  -- showed none, since script stocking was missing)
  pcall(function()
    robot_infra.roboport.insert({ name = "construction-robot", count = 20 })
    robot_infra.roboport.energy = 100000000
  end)
  pcall(function() robot_infra.eei.energy = 100000000 end)
  return true
end

local function robot_case_setup(cas)
  set_tier(cas.tier)
  clear_rect(cas.pos[1], cas.pos[2], 3)
  restore_grass(cas.pos[1], cas.pos[2])
  robot_infra.chest.insert({ name = cas.item, count = 2 })
  local ghost = surface.create_entity({
    name = "entity-ghost", inner_name = cas.item,
    position = { cas.pos[1] + 0.5, cas.pos[2] + 0.5 }, force = "player",
  })
  if not ghost or not ghost.valid then
    return false, "ghost creation failed"
  end
  -- 2.x: script-created entity-ghosts resolve their material WITHOUT any
  -- item-request-proxy — construction robots fetch from the network chests
  -- and build them (probed 2026-10-20: rail ghosts built with the explicit
  -- item_requests write FAILING — the implicit request is what drives it).
  robot_ghost = ghost
  return true
end

local function item_census(name, site_pos)
  -- every copy of `name`: main inventory, in-flight drones (with position),
  -- the robot-phase chests, and ground item-entities (site + infra zones)
  local function chest_count(ent)
    local inv = ent.get_inventory and ent.get_inventory(defines.inventory.chest) or nil
    return inv and inv.get_item_count(name) or 0
  end
  local parts = {
    "main=" .. (player and player.valid and player.get_main_inventory().get_item_count(name) or 0),
  }
  for _, r in ipairs(surface.find_entities_filtered({ type = "construction-robot" })) do
    local inv = r.get_inventory(defines.inventory.robot_cargo)
    local n = inv and inv.get_item_count(name) or 0
    if n > 0 then
      parts[#parts + 1] = string.format("c-drone@(%.1f,%.1f)=%d", r.position.x, r.position.y, n)
    end
  end
  for _, r in ipairs(surface.find_entities_filtered({ type = "logistic-robot" })) do
    local inv = r.get_inventory(defines.inventory.robot_cargo)
    local n = inv and inv.get_item_count(name) or 0
    if n > 0 then
      parts[#parts + 1] = string.format("l-drone@(%.1f,%.1f)=%d", r.position.x, r.position.y, n)
    end
  end
  for key, ent in pairs(robot_infra) do
    if ent and ent.valid and chest_count(ent) > 0 then
      parts[#parts + 1] = key .. "=" .. chest_count(ent)
    end
  end
  for _, zone in ipairs({ site_pos, { -22, 14 } }) do
    local ents = surface.find_entities_filtered({
      area = { { zone[1] - 6, zone[2] - 6 }, { zone[1] + 6, zone[2] + 6 } },
      type = "item-entity", name = name })
    for _, ie in ipairs(ents) do
      parts[#parts + 1] = string.format("ground(%.1f,%.1f)=%d", ie.position.x, ie.position.y, ie.stack.count)
    end
  end
  return table.concat(parts, " ")
end

local function robot_case_assert(cas)
  local present = placed_entity_present(cas)
  record({
    id = cas.id, expected = cas.expected,
    pass = present == (cas.expected == "placed"),
    got = present and "placed" or "absent",
    detail = "robot path (upgrade-driven: real robot built the replacement)",
  })
  log("MATRIX-CENSUS-NOW " .. cas.id .. " " .. cas.item .. " :: " .. item_census(cas.item, cas.pos))
  -- where does the guard's recovered item go from here? deferred census
  pending_censuses[#pending_censuses + 1] = { until_tick = game.tick + 600, item = cas.item, site = cas.pos }
end

-- ----------------------------------------------------------- case tables
-- Tiers: hardcore -> drills only; mining -> +poles/belts/pipes; bot-mining ->
-- +roboports/bot-chests; default -> +containers/beacons/furnaces.
-- families.lua is the contract; the expected column encodes it so any drift
-- shows up as a matrix failure.

local PLAYER_CASES_A = {
  { id = "drill-iron-hc",    area = "iron",   pos = { -16, 2 }, item = "electric-mining-drill", tier = "hardcore", expected = "placed" },
  { id = "drill-iron-df",    area = "iron",   pos = { -15, 3 }, item = "electric-mining-drill", tier = "default",  expected = "placed" },
  { id = "drill-copper-mi",  area = "copper", pos = { 12, 2 },  item = "electric-mining-drill", tier = "mining",   expected = "placed" },
  { id = "pumpjack-oil-hc",  area = "oil",    pos = { 20, 0 },  item = "pumpjack",              tier = "hardcore", expected = "placed" },
  { id = "pumpjack-oil-df",  area = "oil",    pos = { 24, 4 },  item = "pumpjack",              tier = "default",  expected = "placed" },
  { id = "pumpjack-iron-hc", area = "iron",   pos = { -17, 1 }, item = "pumpjack",              tier = "hardcore", expected = "engine-refused" },
  { id = "pumpjack-iron-df", area = "iron",   pos = { -14, 4 }, item = "pumpjack",              tier = "default",  expected = "engine-refused" },
}

local TIERED = {
  { item = "small-electric-pole", min_tier = 2 },
  { item = "transport-belt",      min_tier = 2 },
  { item = "underground-belt",    min_tier = 2 },
  { item = "splitter",            min_tier = 2 },
  { item = "pipe",                min_tier = 2 },
  { item = "pipe-to-ground",      min_tier = 2 },
  { item = "roboport",            min_tier = 3 },
  { item = "storage-chest",       min_tier = 3 },
  { item = "iron-chest",          min_tier = 4 },
  { item = "beacon",              min_tier = 4 },
  { item = "stone-furnace",       min_tier = 4 },
}
local TIER_ORDER = { "hardcore", "mining", "bot-mining", "default" }
local TIER_INDEX = { hardcore = 1, mining = 2, ["bot-mining"] = 3, default = 4 }
for _, spec in ipairs(TIERED) do
  for _, tier in ipairs(TIER_ORDER) do
    PLAYER_CASES_A[#PLAYER_CASES_A + 1] = {
      id = spec.item .. "-" .. tier,
      area = "iron", pos = { -14, 2 },
      item = spec.item, tier = tier,
      expected = TIER_INDEX[tier] >= spec.min_tier and "placed" or "guard-blocked",
    }
  end
end

-- rail family at toggle-OFF. With the fixture rails laid (ensure_rail_infra
-- keeps script-created pieces over the ore), the engine accepts signal/stop
-- placement (their collision masks are empty; they are never stamped) and
-- the RUNTIME GUARD is what refuses: block + item-return -> guard-blocked.
-- The ground-rail-stamping dump-diff remains the engine-defense evidence
-- for the rails themselves. rail-ramp has a real item and places (name
-- exemption proven); straight-rail/elevated-rail have no cursor item in
-- 2.1 (the planner item "rail" needs drag semantics build_from_cursor
-- can't drive) -> pcall'd set_stack records a clean skip.
local RAIL_A = {
  { id = "rail-signal-hc",   area = "alley", pos = { -1, -8 }, item = "rail-signal",       tier = "hardcore", expected = "guard-blocked" },
  { id = "rail-signal-df",   area = "alley", pos = { -1, -8 }, item = "rail-signal",       tier = "default",  expected = "guard-blocked" },
  { id = "rail-chain-df",    area = "alley", pos = { 1, -8 },  item = "rail-chain-signal", tier = "default",  expected = "guard-blocked" },
  { id = "train-stop-df",    area = "alley", pos = { -3, -8 }, item = "train-stop",        tier = "default",  expected = "guard-blocked" },
  { id = "rail-support-df",  area = "alley", pos = { 0, -8 },  item = "rail-support",      tier = "default",  expected = "placed" },
  { id = "rail-ramp-df",     area = "alley", pos = { 1, -8 },  item = "rail-ramp",         tier = "default",  expected = "placed" },
  { id = "straight-rail-hc", area = "alley", pos = { -2, -8 }, item = "straight-rail",     tier = "hardcore", expected = "skip" },
  { id = "elevated-rail-hc", area = "alley", pos = { 3, -8 },  item = "elevated-rail",     tier = "hardcore", expected = "skip" },
}
for _, cas in ipairs(RAIL_A) do
  PLAYER_CASES_A[#PLAYER_CASES_A + 1] = cas
end

-- tiles: the tile guard honors only the decorative-tiles toggle (runtime
-- global; the case driver flips it)
local TILE_CASES_A = {
  -- landfill is WATER-only in vanilla (engine-refused on grass regardless of
  -- the guard) — placeable tile items: stone-brick / refined-concrete
  { id = "brick-off-hc",     area = "iron", pos = { -14, 0 }, item = "stone-brick",      tile_name = "stone-path",      tiles = false, expected = "guard-blocked" },
  { id = "brick-off-df",     area = "iron", pos = { -15, 0 }, item = "stone-brick",      tile_name = "stone-path",      tiles = false, expected = "guard-blocked" },
  { id = "brick-on-df",      area = "iron", pos = { -16, 1 }, item = "stone-brick",      tile_name = "stone-path",     tiles = true,  expected = "placed" },
  { id = "concrete-off-df",  area = "iron", pos = { -17, 2 }, item = "refined-concrete", tile_name = "refined-concrete", tiles = false, expected = "guard-blocked" },
  { id = "concrete-on-hc",   area = "iron", pos = { -18, 1 }, item = "refined-concrete", tile_name = "refined-concrete", tiles = true,  expected = "placed" },
}
for _, cas in ipairs(TILE_CASES_A) do
  PLAYER_CASES_A[#PLAYER_CASES_A + 1] = cas
end

-- no-ore control zone: the guard must never fire off-ore
local CONTROL_CASES = {
  { id = "furnace-control-hc",  pos = { -1, 7 }, item = "stone-furnace", tier = "hardcore", expected = "placed" },
  { id = "roboport-control-hc", pos = { 2, 7 },  item = "roboport",      tier = "hardcore", expected = "placed" },
  { id = "beacon-control-hc",   pos = { -2, 7 }, item = "beacon",        tier = "hardcore", expected = "placed" },
  { id = "brick-control-hc",   pos = { 1, 7 },  item = "stone-brick",   tile_name = "stone-path", tier = "hardcore", expected = "placed" },
}
for _, cas in ipairs(CONTROL_CASES) do
  PLAYER_CASES_A[#PLAYER_CASES_A + 1] = cas
end

-- instance B (startup toggle on): the rail family is granted at runtime and
-- the layer is no longer stamped. straight-rail skips (no cursor item).
local PLAYER_CASES_B = {
  { id = "b-signal-hc", area = "alley", pos = { -1, -8 }, item = "rail-signal",        tier = "hardcore", expected = "placed" },
  { id = "b-chain-df",  area = "alley", pos = { 1, -8 },  item = "rail-chain-signal",  tier = "default",  expected = "placed" },
  { id = "b-stop-df",   area = "alley", pos = { -3, -8 }, item = "train-stop",         tier = "default",  expected = "placed" },
  { id = "b-pole-hc-blk",   area = "iron",  pos = { -16, 2 }, item = "small-electric-pole", tier = "hardcore", expected = "guard-blocked" },
}

-- ROBOT CASES (ghost-driven): script-created ghosts get their item_requests
-- set directly (LuaEntity.item_requests is read-write in 2.x — "items this
-- ghost will request when revived")! item-request-proxy can NOT be used
-- headless: it rejects health-less ghost targets ("Target must have health").
-- Construction robots fetch the item from the provider chest and build the
-- ghost -- firing the genuine on_robot_built_entity our guard handles.
local ROBOT_CASES = {
  { id = "robot-assembler-hc", area = "iron", pos = { -18, 0 }, item = "assembling-machine-1",  tier = "hardcore", expected = "guard-blocked" },
  { id = "robot-belt-mi",      area = "iron", pos = { -17, 1 }, item = "transport-belt",        tier = "mining",   expected = "placed" },
  { id = "robot-solar-df",     area = "iron", pos = { -16, 2 }, item = "solar-panel",           tier = "default",  expected = "guard-blocked" },
  { id = "robot-drill-hc",     area = "iron", pos = { -19, 3 }, item = "electric-mining-drill", tier = "hardcore", expected = "placed" },
}

local ROBOT_SETTLE_TICKS = 2400


-- player acquisition is LAZY: windowed singleplayer has game.player; headless
-- servers never do (player cases skip after the grace window).
local function acquire_player()
  local p = game.player or game.get_player(1)
  if not p then return false end
  player = p
  -- 2.x: the cease_fire STATE argument is required (defaults removed)
  pcall(function() player.force.set_cease_fire(game.forces.enemy, false) end)
  pcall(function() game.forces.enemy.set_cease_fire(player.force, false) end)
  log("MATRIX-PLAYER-READY")
  return true
end

local function skip_remaining_player_cases(reason)
  if not queue then return end
  for i = q_index + 1, #queue do
    record({ id = queue[i].id, pass = nil, got = "skip", detail = reason })
  end
  q_index = #queue
end


-- the alley track fixtures (railprobe rounds 6–15, 2026-10-20 — the 2.0
-- rail lattice, empirically decoded):
--   * 2.0 rails run on an x+y-even half-lattice; create_entity accepts raw
--     direction values 0-6 (8-way rail convention) and snaps the position.
--   * dir=2 pieces at even centers (0,-6)/(2,-6): vertical lines whose
--     taper-end signal spots sit at the case tiles (-1,-8)/(1,-8);
--     signal builds work with signal-direction 2.
--   * dir=4 pieces at odd/odd positions on the y=-9 line: an E-W line whose
--     stop spots cover tiles (x,-8)/(x,-7); the stop build works with
--     stop-direction 4. (A single create_entity request cannot make an E-W
--     line on the even-x rows — the probe's L-matrix.)
RAIL_ATTACHED = { ["rail-signal"] = true, ["rail-chain-signal"] = true, ["train-stop"] = true }
RAIL_PIECES = {
  { position = { 0, -6 }, direction = 2 },
  { position = { 2, -6 }, direction = 2 },
  { position = { -5, -9 }, direction = 4 },
  { position = { -3, -9 }, direction = 4 },
  { position = { -1, -9 }, direction = 4 },
  { position = { 1, -9 },  direction = 4 },
  { position = { 3, -9 },  direction = 4 },
  { position = { 5, -9 },  direction = 4 },
}
function ensure_rail_infra()
    -- idempotent: match by EXACT piece position — find_entities_filtered's
    -- area filter matches rails by an UNROTATED box (±1.7 reach), so a
    -- window-overlap check miscounts neighbours as "already present"
    -- (b-chain fixture regression, caught 2026-10-20 by found-for logging)
    local built = 0
    for _, spec in ipairs(RAIL_PIECES) do
        local have = false
        for _, r in ipairs(surface.find_entities_filtered({
            area = { { spec.position[1] - 2.5, spec.position[2] - 2.5 },
                     { spec.position[1] + 2.5, spec.position[2] + 2.5 } },
            type = "straight-rail" })) do
            if math.abs(r.position.x - spec.position[1]) < 0.05
                and math.abs(r.position.y - spec.position[2]) < 0.05 then
                have = true
                break
            end
        end
        if have then
            built = built + 1
        else
            local ok, ent = pcall(function()
                return surface.create_entity({ name = "straight-rail",
                    position = spec.position, direction = spec.direction,
                    force = "player" })
            end)
            if ok and ent then
                built = built + 1
                log(string.format("MATRIX-RAIL-INFRA relaid (%d,%d) -> at %.2f,%.2f d%d",
                    spec.position[1], spec.position[2],
                    ent.position.x, ent.position.y, ent.direction))
            else
                log(string.format("MATRIX-RAIL-INFRA refused (%d,%d): %s",
                    spec.position[1], spec.position[2],
                    ok and "nil" or tostring(ent)))
            end
        end
    end
    log("MATRIX-RAIL-INFRA pieces=" .. built .. "/" .. #RAIL_PIECES)
end

function tick_dispatch()
  if not surface then
    surface = game.get_surface(1)
  end
  -- deferred item-destination census: 10s after a blocked robot build, count
  -- every copy of the item: in-flight drones (with their positions), the
  -- network chests, and the player's main inventory
  for i = #pending_censuses, 1, -1 do
    local pending = pending_censuses[i]
    if game.tick >= pending.until_tick then
      log("MATRIX-ITEM-CENSUS-10s " .. pending.item .. " :: " .. item_census(pending.item, pending.site))
      table.remove(pending_censuses, i)
    end
  end
  if not matrix_started then
    matrix_started = true
    local seeded = seeded_rail()
    record({
      id = "seed-rail-toggle", pass = true, got = seeded and "on" or "off",
      detail = "startup oreguard-allow-ground-rail at run start: " .. tostring(seeded),
    })
    if seeded then
      queue = {}
      for _, cas in ipairs(PLAYER_CASES_B) do
        if not cas.case then queue[#queue + 1] = cas end
      end
    else
      queue = PLAYER_CASES_A
      robot_infra = {}
    end
    player_grace_until = game.tick + 1200
    local infra_ok, infra_err = pcall(ensure_rail_infra)
    if not infra_ok then log("MATRIX-RAIL-INFRA setup error: " .. tostring(infra_err)) end
    stage = "next"
    write_results()
    log(string.format("MATRIX-READY rev=%d cases=%d railtoggle=%s curated=%s oreguard=%s",
    DRIVER_REVISION,
      #queue, tostring(seeded), tostring(storage.oreguard_lab_curated),
      tostring(script.active_mods["oreguard"])))
  end

  if not player and not player_done then
    if game.tick <= player_grace_until then
      if acquire_player() then return end
      return -- still within the grace window: no player cases without a player
    end
    if game.tick > player_grace_until then
      player_done = true
      skip_remaining_player_cases("no player in this environment (grace expired)")
      if seeded_rail() then
        done = true
        write_results()
        return
      end
    end
  end

  if player_done then
    -- headless-style robot-only pass
    robot_ticker()
    if not robot_infra_done and stage == "next" then
      local ok, err = robot_infra_setup()
      if not ok then
        for _, cas in ipairs(ROBOT_CASES) do
          record({ id = cas.id, pass = false, detail = "robot infra setup failed: " .. tostring(err) })
        end
        done = true
        write_results()
        return
      end
      robot_infra_done = true
      return -- start robot cases on the next tick
    end
    if stage == "next" then
      robot_case_index = robot_case_index + 1
      local cas = ROBOT_CASES[robot_case_index]
      if not cas then
        if #pending_censuses > 0 then return end -- census flushes before finishing
        done = true
        write_results()
        return
      end
      local ok, err = robot_case_setup(cas)
      if ok then
        current_case = cas
        robot_wait_until = game.tick + ROBOT_SETTLE_TICKS
        stage = "robot-wait"
      else
        record({ id = cas.id, pass = nil, got = "skip", detail = "robot case: " .. tostring(err) })
      end
    elseif stage == "robot-wait" then
      local ghost_gone = not (robot_ghost and robot_ghost.valid)
      if ghost_gone or game.tick >= robot_wait_until then
        robot_ghost = nil
        -- do not finish the case yet: the drone that built (and may be
        -- carrying the recovered item) still sits at the site; wait for it
        -- to depart (maintainer's hand-procedure, 2026-10-20)
        robot_wait_until = game.tick + 600
        stage = "robot-drone-gone"
      end
    elseif stage == "robot-drone-gone" then
      local site = current_case.pos
      local drones = surface.find_entities_filtered({
        area = { { site[1] - 8, site[2] - 8 }, { site[1] + 8, site[2] + 8 } },
        type = "construction-robot" })
      if #drones == 0 or game.tick >= robot_wait_until then
        robot_case_assert(current_case)
        stage = "next"
      end
    end
    return
  end

  if stage == "pre-assert" then
    if game.tick >= case_wait_until then stage = "assert" end
  elseif stage == "assert-then-next" then
    stage = "next"
  elseif stage == "next" then
    q_index = q_index + 1
    local cas = queue[q_index]
    if cas then
      case_setup(cas)
      stage = "pre-assert"
    elseif not seeded_rail() then
      -- player queue exhausted -> robot phase (instance A only)
      local ok, err = robot_infra_setup()
      if not ok then
        for _, rc in ipairs(ROBOT_CASES) do
          record({ id = rc.id, pass = false, detail = "robot infra setup failed: " .. tostring(err) })
        end
        done = true
        write_results()
        return
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
      if #pending_censuses > 0 then return end -- census flushes before finishing
      done = true
      write_results()
      return
    end
    local ok, err = robot_case_setup(cas)
    if ok then
      current_case = cas
      robot_wait_until = game.tick + ROBOT_SETTLE_TICKS
      stage = "robot-wait"
    else
      -- known-blocked mechanism (2.1: proxy refuses health-less ghosts,
      -- ghost.item_requests is read-only): record as skip, not failure
      record({ id = cas.id, pass = nil, got = "skip", detail = "robot case: " .. tostring(err) })
    end
  elseif stage == "robot-wait" then
    robot_ticker()
    local ghost_gone = not (robot_ghost and robot_ghost.valid)
    if ghost_gone or game.tick >= robot_wait_until then
      robot_ghost = nil
      -- wait for the building drone to depart the site before the assert
      robot_wait_until = game.tick + 600
      stage = "robot-drone-gone"
    end
  elseif stage == "robot-drone-gone" then
    robot_ticker()
    local site = current_case.pos
    local drones = surface.find_entities_filtered({
      area = { { site[1] - 8, site[2] - 8 }, { site[1] + 8, site[2] + 8 } },
      type = "construction-robot" })
    if #drones == 0 or game.tick >= robot_wait_until then
      robot_case_assert(current_case)
      stage = "robot-next"
    end
  end
end

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


script.on_init(function()
  surface = game.get_surface(1)
  pcall(function()
    game.forces["enemy"].kill_all_units()
    game.forces["enemy"].ai_controllable = false
    game.map_settings.enemy_expansion.enabled = false
    game.forces["enemy"].evolution_factor = 0
  end)
  for _, ent in pairs(surface.find_entities_filtered({ force = "enemy", limit = 1000 })) do
    pcall(function() ent.destroy() end)
  end
  log("MATRIX-MOD-INIT (enemy hard-off)")
end)

script.on_configuration_changed(function()
  -- pure-local reset only (on-configuration context: game allowed, but the
  -- state machine should simply restart cleanly on the next tick)
  stage = "next"
end)

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

script.on_event(defines.events.on_tick, function(event)
  if done then return end
  -- CRASH CONTAINMENT: scripting errors must never reach the engine (the
  -- windowed error dialog needs human clearing). Record + move on.
  local function err_handler(e)
    return tostring(e) .. " | " .. strsub(debug.traceback(e, 1) or "", 1, 300)
  end
  local ok, err = xpcall(tick_dispatch, err_handler)
  if not ok then
    local detail = "uncaught tick error: " .. err
    if detail ~= last_harness_err then
      last_harness_err = detail
      record({ id = current_case and current_case.id or "harness",
        pass = false, detail = detail })
      current_case = nil
      stage = "next"
      write_results()
    end
  else
    last_harness_err = nil
  end
end)
