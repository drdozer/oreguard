-- OreGuard: Prevents building over ore except for whitelisted entity types

local debug_log = settings.startup["oreguard-verbose-debugging"].value and log or function() end

local function get_allowed_types()
    local tier = settings.global["oreguard-tier"].value
    if tier == "hardcore" then
        return { ["mining-drill"] = true }
    elseif tier == "mining" then
        return {
            ["mining-drill"] = true,
            ["electric-pole"] = true,
            ["transport-belt"] = true,
            ["pipe"] = true
        }
    elseif tier == "bot-mining" then
        return {
            ["mining-drill"] = true,
            ["electric-pole"] = true,
            ["transport-belt"] = true,
            ["pipe"] = true,
            ["roboport"] = true,
            ["logistic-container"] = true
        }
    elseif tier == "default" then
        return {
            ["mining-drill"] = true,
            ["electric-pole"] = true,
            ["transport-belt"] = true,
            ["pipe"] = true,
            ["roboport"] = true,
            ["logistic-container"] = true,
            ["container"] = true,
            ["beacon"] = true,
            ["furnace"] = true
        }
    elseif tier == "decorative" then
        return {
            ["mining-drill"] = true,
            ["electric-pole"] = true,
            ["transport-belt"] = true,
            ["pipe"] = true,
            ["roboport"] = true,
            ["logistic-container"] = true,
            ["container"] = true,
            ["beacon"] = true,
            ["furnace"] = true
        }, true
    end
    return {
        ["mining-drill"] = true,
        ["electric-pole"] = true,
        ["transport-belt"] = true,
        ["beacon"] = true,
        ["pipe"] = true,
        ["roboport"] = true,
        ["container"] = true,
        ["logistic-container"] = true,
        ["furnace"] = true
    }
end

local allowed_types = get_allowed_types()

script.on_event(defines.events.on_built_entity, function(event)
    local allowed_types, allow_flooring = get_allowed_types()
    local entity = event.created_entity or event.entity
    if not entity or not entity.valid then return end

    local entity_type = entity.type
    local entity_name = entity.name

    -- Resolve ghost entities to their actual entity type and name
    if entity_type == "entity-ghost" then
        entity_type = entity.ghost_type
        entity_name = entity.ghost_name
    end

    -- Allow elevated rails, rail supports, and rail ramps to be placed over ore
    if entity_name:find("^elevated%-") or entity_name == "rail-support" or entity_name == "rail-ramp" then
        return -- Allowed
    end
    if allowed_types[entity_type] then
        return -- Allowed
    end

    -- Check for ore under the entity
    local surface = entity.surface
    local area = entity.selection_box
    local ores = surface.find_entities_filtered {
        area = area,
        type = "resource"
    }
    if #ores > 0 then
        local player = game.get_player(event.player_index)
        if player then
            debug_log("[OreGuard] Blocked entity: " .. (entity.name or "nil") .. ", type: " .. (entity_type or "nil"))
            player.create_local_flying_text {
                text = { "message.oreguard.cannot-build" },
                position = entity.position,
                color = { r = 1, g = 0.2, b = 0.2 }
            }
            -- Try to return the correct item to the player's inventory
            local items = entity.prototype.items_to_place_this
            local returned = false
            if items then
                debug_log("[OreGuard] items_to_place_this found for " .. entity.name)
                for _, item_name in ipairs(items) do
                    local actual_item_name = item_name
                    if type(item_name) == "table" and item_name.name then
                        actual_item_name = item_name.name
                    end
                    debug_log("[OreGuard] Checking item prototype: " .. tostring(actual_item_name))
                    if prototypes.item[actual_item_name] then
                        debug_log("[OreGuard] Inserting item: " .. tostring(actual_item_name))
                        local stack = { name = actual_item_name, count = 1 }
                        local inserted = player.insert(stack)
                        if inserted < 1 then
                            debug_log("[OreGuard] Inventory full, spilling item: " .. tostring(actual_item_name))
                            player.surface.spill_item_stack(player.position, stack, true, player.force, false)
                        end
                        returned = true
                        break -- Only return one valid item
                    else
                        debug_log("[OreGuard] No item prototype for: " .. tostring(actual_item_name))
                    end
                end
            else
                debug_log("[OreGuard] No items_to_place_this for " .. entity.name)
            end
            -- Fallback: if nothing was returned, try to return the entity itself as an item (for legacy/simple cases)
            if not returned and prototypes.item[entity.name] then
                debug_log("[OreGuard] Fallback: inserting entity as item: " .. entity.name)
                local stack = { name = entity.name, count = 1 }
                local inserted = player.insert(stack)
                if inserted < 1 then
                    debug_log("[OreGuard] Inventory full, spilling fallback item: " .. entity.name)
                    player.surface.spill_item_stack(player.position, stack, true, player.force, false)
                end
            elseif not returned then
                debug_log("[OreGuard] No valid item to return for: " .. entity.name)
            end
            if not returned then
                debug_log("[OreGuard] No item was returned or inserted for entity: " .. (entity.name or "nil"))
            end
        end
        entity.destroy()
    end
end)

-- Prevent flooring tiles from being built over ore
script.on_event(defines.events.on_player_built_tile, function(event)
    local allowed_types, allow_flooring = get_allowed_types()
    if allow_flooring then return end

    local player = game.get_player(event.player_index)
    local surface = player and player.surface
    if not player or not surface then return end

    local denied_tiles = {}
    for _, tile in ipairs(event.tiles) do
        local ores = surface.find_entities_filtered {
            area = { { tile.position.x, tile.position.y }, { tile.position.x + 1, tile.position.y + 1 } },
            type = "resource"
        }
        if #ores > 0 then
            table.insert(denied_tiles, tile)
        end
    end

    if #denied_tiles > 0 then
        -- Remove the denied tiles by restoring their old tile (with fallback)
        local restore_tiles = {}
        for _, tile in ipairs(denied_tiles) do
            local restore_name = tile.old_tile and tile.old_tile.name or "grass-1"
            table.insert(restore_tiles, { name = restore_name, position = tile.position })
        end
        if #restore_tiles > 0 then
            surface.set_tiles(restore_tiles, true)
        end

        -- Return tiles to player or spill
        local item_name = event.item
        if item_name and item_name ~= "" then
            local stack = { name = item_name, count = #denied_tiles }
            local inserted = player.insert(stack)
            if inserted < #denied_tiles then
                surface.spill_item_stack(player.position, { name = item_name, count = #denied_tiles - inserted }, true,
                    player.force, false)
            end
        end
        player.create_local_flying_text {
            text = { "message.oreguard.cannot-build" },
            position = player.position,
            color = { r = 1, g = 0.2, b = 0.2 }
        }
    end
end)
