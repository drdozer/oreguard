-- OreGuard: Prevents building over ore except for whitelisted entity types.
-- The allow-list itself lives in families.lua (single source of truth —
-- tiers, toggles and the floating-text enumerations are all derived there).

local Families = require("families")

local debug_log = settings.startup["oreguard-verbose-debugging"].value and log or function() end

local RED = { r = 1, g = 0.2, b = 0.2 }
local NEARBY_TEXT_RADIUS = 40
local ROBOT = "construction-robot"

local family_by_id = {}
for _, family in ipairs(Families.list) do
    family_by_id[family.id] = family
end

-- Names (not types) that bypass the guard in every tier: elevated rails,
-- rail supports and rail ramps. data-final-fixes.lua complements this by
-- never stamping the oreguard collision layer onto those prototypes.
local function is_exempt_name(name)
    return name and (name:find("^elevated%-") ~= nil or name == "rail-support" or name == "rail-ramp")
end

-- Active families: the tier's composition, plus the startup-gated
-- ground-rail family when oreguard-allow-ground-rail is on.
local function active_families()
    local tier = settings.global["oreguard-tier"].value
    local ids = Families.tiers[tier] or Families.tiers[Families.default_tier]
    local list = {}
    for _, id in ipairs(ids) do
        local family = family_by_id[id]
        if family then
            list[#list + 1] = family
        else
            debug_log("[OreGuard] tier references unknown family: " .. id)
        end
    end
    if settings.startup["oreguard-allow-ground-rail"].value then
        list[#list + 1] = family_by_id["ground-rail"]
    end
    return list
end

-- Entity-type allow-set for the current settings state.
local function get_allowed_types()
    local set = {}
    for _, family in ipairs(active_families()) do
        for _, type in ipairs(family.types) do
            set[type] = true
        end
    end
    return set
end

-- Floating warning text composed from the active families. The template
-- lives in locale [oreguard-message] (with __1__), the family display
-- names in locale [oreguard-family]; the composition here is the only
-- place where the two meet, so neither can drift from the real rules. The
-- display-only "tiles" pseudo-family (families.lua) is appended while the
-- decorative-tiles toggle is on.
local function ore_guard_text()
    local parts = {}
    for _, family in ipairs(active_families()) do
        parts[#parts + 1] = { "oreguard-family." .. family.id }
    end
    if settings.global["oreguard-allow-decorative-tiles"].value then
        parts[#parts + 1] = { "oreguard-family.tiles" }
    end
    local joined = { "" }
    for i, part in ipairs(parts) do
        if i > 1 then
            joined[#joined + 1] = ", "
        end
        joined[#joined + 1] = part
    end
    return { "oreguard-message.cannot-build", joined }
end

local function warn_player(player, position)
    player.create_local_flying_text({
        text = ore_guard_text(),
        position = position,
        color = RED
    })
end

-- Robot blocks have no player; show the warning to any connected member of
-- the owning force near the site.
local function warn_nearby(surface, force, position)
    for _, player in ipairs(force.players) do
        if player.connected and player.surface == surface then
            local dx, dy = player.position.x - position.x, player.position.y - position.y
            if dx * dx + dy * dy <= NEARBY_TEXT_RADIUS * NEARBY_TEXT_RADIUS then
                warn_player(player, position)
            end
        end
    end
end

-- Item a blocked entity was built from (entity prototypes only — ghosts
-- carry no items). Falls back to the prototype's own name, as before.
local function item_for(entity)
    local items = entity.prototype.items_to_place_this
    if not items then
        return nil
    end
    for _, item_name in ipairs(items) do
        local name = item_name
        if type(item_name) == "table" and item_name.name then
            name = item_name.name
        end
        if prototypes.item[name] then
            return name
        end
    end
    return nil
end

-- Players insert directly; construction robots receive the item back in
-- their cargo inventory.
local function insert_into(carrier, stack)
    if carrier.type == ROBOT then
        local inv = carrier.get_inventory(defines.inventory.robot_cargo)
        return inv and inv.insert(stack) or 0
    end
    return carrier.insert(stack)
end

local function spill_stack(surface, position, stack, force)
    surface.spill_item_stack(position, stack, true, force, false)
end

-- Player-path recovery: same semantics as 0.3.x — insert one item, spill if
-- the inventory is full, fall back to the entity's own name.
local function recover_player_item(player, entity)
    local name = item_for(entity) or (prototypes.item[entity.name] and entity.name or nil)
    if not name then
        debug_log("[OreGuard] No valid item to return for: " .. entity.name)
        return
    end
    local stack = { name = name, count = 1 }
    local inserted = player.insert(stack)
    if inserted < 1 then
        debug_log("[OreGuard] Inventory full, spilling item: " .. name)
        spill_stack(player.surface, player.position, stack, player.force)
    end
end

-- Robot-path recovery: the robot's cargo inventory. Revival has already
-- consumed the ghost at this point, so there is no re-place loop.
local function recover_robot_item(robot, entity, surface, position)
    local name = item_for(entity) or (prototypes.item[entity.name] and entity.name or nil)
    if not name then
        debug_log("[OreGuard] No valid item to return for robot-built: " .. entity.name)
        return
    end
    local stack = { name = name, count = 1 }
    if robot and robot.valid then
        local inserted = insert_into(robot, stack)
        if inserted < 1 then
            spill_stack(surface, position, stack, robot.force)
        end
    else
        spill_stack(surface, position, stack, entity.force)
    end
end

local function overlaps_ore(entity)
    return #entity.surface.find_entities_filtered({
        area = entity.selection_box,
        type = "resource"
    }) > 0
end

-- Player placements: real entities, entity-ghosts (blueprints, shift-
-- placement) and tile-ghosts all arrive here. Blocked types are refused:
-- ghosts are destroyed AT PLACEMENT so robots never inherit the job.
script.on_event(defines.events.on_built_entity, function(event)
    local allow = get_allowed_types()
    local entity = event.created_entity or event.entity
    if not entity or not entity.valid then
        return
    end

    local raw_type = entity.type
    local entity_type = raw_type
    local entity_name = entity.name
    local is_ghost = raw_type == "entity-ghost" or raw_type == "tile-ghost"
    if raw_type == "entity-ghost" then
        entity_type = entity.ghost_type
        entity_name = entity.ghost_name
    end

    -- Allow elevated rails, rail supports, and rail ramps to be placed over ore
    if is_exempt_name(entity_name) then
        return -- Allowed
    end
    if allow[entity_type] then
        return -- Allowed
    end

    -- Check for ore under the entity
    if not overlaps_ore(entity) then
        return
    end

    local player = game.get_player(event.player_index)
    debug_log("[OreGuard] Blocked " .. (is_ghost and "ghost" or "entity") .. ": " .. (entity_name or "nil")
        .. ", type: " .. (entity_type or "nil"))
    if is_ghost then
        -- Refuse the ghost itself (no items to recover; the blueprint stays
        -- intact, the blocked ghosts simply do not survive placement).
        if player then
            warn_player(player, entity.position)
        end
        entity.destroy()
        return
    end

    if player then
        warn_player(player, entity.position)
        recover_player_item(player, entity)
    end
    entity.destroy()
end)

-- Construction robots: same guard on the robot event stream. The revived
-- ghost is consumed by the build itself, so destroy + item-back-to-cargo
-- cannot loop.
script.on_event(defines.events.on_robot_built_entity, function(event)
    local allow = get_allowed_types()
    local entity = event.entity
    if not entity or not entity.valid then
        return
    end
    if is_exempt_name(entity.name) or allow[entity.type] or not overlaps_ore(entity) then
        return
    end
    debug_log("[OreGuard] Blocked robot-built entity: " .. entity.name .. ", type: " .. entity.type)
    warn_nearby(entity.surface, entity.force, entity.position)
    recover_robot_item(event.robot, entity, entity.surface, entity.position)
    entity.destroy()
end)

-- Tile paving: deny per tile unless the decorative-tile toggle is on.
-- Shared by the player and robot event streams.
local function enforce_tile_guard(surface, tiles, item_name, carrier)
    if settings.global["oreguard-allow-decorative-tiles"].value then
        return
    end
    local denied = {}
    for _, tile in ipairs(tiles) do
        local ores = surface.find_entities_filtered({
            area = { { tile.position.x, tile.position.y }, { tile.position.x + 1, tile.position.y + 1 } },
            type = "resource"
        })
        if #ores > 0 then
            denied[#denied + 1] = tile
        end
    end
    if #denied == 0 then
        return
    end

    -- Remove the denied tiles by restoring their old tile (with fallback)
    local restore_tiles = {}
    for _, tile in ipairs(denied) do
        restore_tiles[#restore_tiles + 1] = {
            name = tile.old_tile and tile.old_tile.name or "grass-1",
            position = tile.position
        }
    end
    surface.set_tiles(restore_tiles, true)

    if item_name and item_name ~= "" and prototypes.item[item_name] then
        local stack = { name = item_name, count = #denied }
        local inserted = insert_into(carrier, stack)
        if inserted < #denied then
            local spill_position = carrier.type == ROBOT and denied[1].position or carrier.position
            debug_log("[OreGuard] Carrier full or absent, spilling " .. (#denied - inserted) .. " of " .. item_name)
            spill_stack(surface, spill_position, { name = item_name, count = #denied - inserted },
                carrier.force or game.forces.player)
        end
    end

    if carrier.type == ROBOT then
        warn_nearby(surface, carrier.force, denied[1].position)
    elseif carrier.create_local_flying_text then
        warn_player(carrier, carrier.position)
    end
end

-- Robot tile events may not carry the tile item; fall back to the tile's
-- minable result (the tile item), e.g. landfill.
local function tile_item_fallback(tiles)
    for _, tile in ipairs(tiles) do
        local proto = prototypes.tile[tile.name]
        local result = proto and proto.minable and proto.minable.result
        if result and prototypes.item[result] then
            return result
        end
    end
    return nil
end

script.on_event(defines.events.on_player_built_tile, function(event)
    local carrier = game.get_player(event.player_index)
    if not carrier or not carrier.surface then
        return
    end
    enforce_tile_guard(carrier.surface, event.tiles, event.item, carrier)
end)

script.on_event(defines.events.on_robot_built_tile, function(event)
    local carrier = event.robot
    if not carrier or not carrier.valid then
        return
    end
    enforce_tile_guard(carrier.surface, event.tiles, event.item or tile_item_fallback(event.tiles), carrier)
end)

-- 0.3.x -> 0.4.0 migration: older versions refused blocked entities only at
-- revival, so blocked ghosts could linger over ore in old saves (robots
-- would still build them). Sweep them once per mod update.
script.on_configuration_changed(function(data)
    if not (data.mod_changes and data.mod_changes["oreguard"]) then
        return
    end
    local allow = get_allowed_types()
    local swept = 0
    for _, surface in pairs(game.surfaces) do
        for _, ghost in ipairs(surface.find_entities_filtered({ type = "entity-ghost" })) do
            if not allow[ghost.ghost_type] and not is_exempt_name(ghost.ghost_name) then
                if #surface.find_entities_filtered({ area = ghost.selection_box, type = "resource" }) > 0 then
                    ghost.destroy()
                    swept = swept + 1
                end
            end
        end
    end
    if swept > 0 then
        log("OreGuard: migration swept " .. swept .. " blocked ghost(s) from pre-0.4.0 saves")
    end
end)
-- Remote interface: integration/test entry points for runtime settings.
-- Engine policy: runtime-global settings can only be written by the owning
-- mod (or the player in the settings UI) — so the matrix harness
-- (mods/oreguard/testing/run-matrix.py) drives tiers/toggles through these
-- functions, which execute in OreGuard's own ownership context.
remote.add_interface("oreguard", {
    -- tier: "hardcore" | "mining" | "bot-mining" | "default"
    set_tier = function(tier)
        local valid = { hardcore = true, mining = true, ["bot-mining"] = true, ["default"] = true }
        if valid[tier] then
            settings.global["oreguard-tier"] = { value = tier }
            log("OreGuard remote: tier -> " .. tier)
            return true
        end
        return false, "invalid tier: " .. tostring(tier)
    end,
    -- allow/decorative-tiles toggle (runtime-global)
    set_tiles_toggle = function(on)
        settings.global["oreguard-allow-decorative-tiles"] = { value = on == true }
        log("OreGuard remote: decorative tiles -> " .. tostring(on == true))
        return true
    end,
    get_state = function()
        return {
            tier = settings.global["oreguard-tier"].value,
            tiles = settings.global["oreguard-allow-decorative-tiles"].value,
        }
    end,
})
