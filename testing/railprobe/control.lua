-- OreGuard RAIL-PROBE round 14 (throwaway diagnostic; instance-B semantics).
--
-- Round 13 facts: bot-built script rails ARE train-grade (loco landed);
-- signals place at taper-end tiles; stops refuse everywhere; and EVERY
-- create_entity rail attempt produced a VERTICAL piece at an even-(x+y)
-- lattice point, regardless of requested direction. The tips sim's track
-- recipe creates rails at x even + y=-1 (x+y ODD = the other parity) with
-- direction=east — the EW class. This round:
--   L) lattice matrix: dir {0,2,4,6} x positions on both parities; dump
--      position/direction/bbox per piece
--   F) if an EW class exists: lay an EW track along y=-9 over the ore strip,
--      then scan all 4 forms for rail-signal/rail-chain-signal/train-stop
--      and run the REAL builds at the case tiles.
--
-- Run via testing/run-railprobe.py.
local GRASS = "grass-1"

local surface
local player

local function carve()
  local tiles = {}
  for x = -70, 69 do
    for y = -70, 69 do
      tiles[#tiles + 1] = { name = GRASS, position = { x, y } }
    end
  end
  surface.set_tiles(tiles, true)
  for _, ent in pairs(surface.find_entities({ { -70, -70 }, { 70, 70 } })) do
    if ent.type ~= "character" then
      pcall(function() if ent.valid then ent.destroy() end end)
    end
  end
  pcall(function()
    game.forces["enemy"].kill_all_units()
    game.forces["enemy"].ai_controllable = false
    game.map_settings.enemy_expansion.enabled = false
  end)
end

local function clear_area(x0, y0, x1, y1)
  for _, ent in pairs(surface.find_entities({ { x0, y0 }, { x1, y1 } })) do
    if ent.type ~= "character" then
      pcall(function() if ent.valid then ent.destroy() end end)
    end
  end
end

local function piece_desc(ent)
  local bb = ent.bounding_box
  return string.format("%.2f,%.2f d%d [%.2f,%.2f-%.2f,%.2f]",
    ent.position.x, ent.position.y, ent.direction,
    bb.left_top.x, bb.left_top.y, bb.right_bottom.x, bb.right_bottom.y)
end

local function probe_scan_forms(tag, item, cx, cy, half)
  local spots = {}
  for dy = -half, half do
    for dx = -half, half do
      for _, form in ipairs({ { 0, 0 }, { 0.5, 0.5 }, { 0.5, 0 }, { 0, 0.5 } }) do
        local pt = { cx + dx + form[1], cy + dy + form[2] }
        for _, dir in ipairs({ 0, 2, 4, 6 }) do
          local ok2, can = pcall(function()
            return player.can_place_entity({ name = item, position = pt,
              direction = dir })
          end)
          if ok2 and can then
            spots[#spots + 1] = string.format("(%.1f,%.1f)d%d", pt[1], pt[2], dir)
          end
        end
      end
    end
  end
  log("PROBE-SCAN " .. tag .. " " .. item .. " spots=" .. #spots .. " :: " ..
    table.concat(spots, " "))
end

script.on_init(function()
  surface = game.get_surface(1)
  carve()
  for x = -3, 3 do
    for y = -10, -6 do
      surface.create_entity({ name = "iron-ore", position = { x, y },
        amount = 50000, force = "neutral" })
    end
  end
  log("PROBE-BEGIN")
end)

script.on_event(defines.events.on_tick, function(_)
  local tick = game.tick
  if tick == 60 then
    local ok, err = pcall(function()
      player = game.player or game.get_player(1) or game.create_player("probe")
      if not player then log("PROBE-ERR no player") return end
      player.teleport({ 0, -2 })
      clear_area(-20, -20, 20, -1)
      -- L) lattice matrix on clean ground: y odd (-9) and y even (-8)
      for _, cy in ipairs({ -9, -8 }) do
        for _, dir in ipairs({ 0, 2, 4, 6 }) do
          for _, cx in ipairs({ 20, 21 }) do
            local ok2, ent = pcall(function()
              return surface.create_entity({ name = "straight-rail",
                position = { cx, cy }, direction = dir, force = "player" })
            end)
            log(string.format("PROBE-L dir=%d at (%d,%d): %s", dir, cx, cy,
              ok2 and ent and piece_desc(ent) or "nil"))
            pcall(function() if ent and ent.valid then ent.destroy() end end)
          end
        end
      end
      -- F) the EW-lattice recipe: dir=4 pieces at odd x, y=-9 and y=-6
      clear_area(-12, -16, 12, -1)
      local built = 0
      for _, cy in ipairs({ -9, -6 }) do
        for _, cx in ipairs({ -5, -3, -1, 1, 3, 5 }) do
          local ok2, ent = pcall(function()
            return surface.create_entity({ name = "straight-rail",
              position = { cx, cy }, direction = 4, force = "player" })
          end)
          if ok2 and ent then built = built + 1 end
        end
      end
      log("PROBE-F ew-built=" .. built)
      for _, ent in ipairs(surface.find_entities_filtered({
          area = { { -8, -14 }, { 8, -3 } }, type = "straight-rail" })) do
        log("PROBE-RAIL " .. piece_desc(ent))
      end
      -- signal spots around the y=-6 track (scan wide)
      probe_scan_forms("f-signal", "rail-signal", 1, -8, 5)
      probe_scan_forms("f-stop", "train-stop", -3, -8, 5)
      -- real builds at the case tiles (guard must allow: B toggle ON)
      for _, spec in ipairs({
        { "rail-signal", { -1, -8 }, 4 },
        { "rail-chain-signal", { 1, -8 }, 4 },
        { "train-stop", { -3, -8 }, 4 },
      }) do
        player.clear_cursor()
        pcall(function()
          player.cursor_stack.set_stack({ name = spec[1], count = 1 })
        end)
        local inv_before = player.get_main_inventory().get_item_count(spec[1])
        local ok2, err2 = pcall(function()
          player.build_from_cursor({ position = spec[2], direction = spec[3] })
        end)
        local found = {}
        for _, ent in ipairs(surface.find_entities_filtered({
            area = { { spec[2][1] - 2.5, spec[2][2] - 2.5 },
                      { spec[2][1] + 2.5, spec[2][2] + 2 } },
            name = spec[1] })) do
          found[#found + 1] = string.format("(%.2f,%.2f)d%d",
            ent.position.x, ent.position.y, ent.direction)
        end
        local cs = player.cursor_stack
        log(string.format(
          "PROBE-BUILD %s tile=(%.1f,%.1f) dir=%d: ok2=%s err2=%s found=[%s] cursor=%s inv_delta=%d",
          spec[1], spec[2][1], spec[2][2], spec[3], tostring(ok2), tostring(err2),
          table.concat(found, " "), tostring(cs and cs.valid_for_read),
          player.get_main_inventory().get_item_count(spec[1]) - inv_before))
        player.clear_cursor()
      end
    end)
    if not ok then log("PROBE-ERR " .. tostring(err)) end
    log("PROBE-DONE")
  end
end)