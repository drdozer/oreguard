-- OreGuard: Prevents building over ore except for whitelisted entity types

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
  if allowed_types[entity_type] then
    return -- Allowed
  end

  -- Check for ore under the entity
  local surface = entity.surface
  local area = entity.selection_box
  local ores = surface.find_entities_filtered{
    area = area,
    type = "resource"
  }
  if #ores > 0 then
    local player = game.get_player(event.player_index)
    if player then
      player.create_local_flying_text{
        text = {"message.oreguard.cannot-build"},
        position = entity.position,
        color = {r=1, g=0.2, b=0.2}
      }
      -- Try to return the correct item to the player's inventory
      local items = entity.prototype.items_to_place_this
      local returned = false
      if items and type(game) == "table" and game.item_prototypes then
        for item_name, _ in pairs(items) do
          if game.item_prototypes[item_name] then
            local stack = {name = item_name, count = 1}
            local inserted = player.insert(stack)
            if inserted < 1 then
              player.surface.spill_item_stack(player.position, stack, true, player.force, false)
            end
            returned = true
            break -- Only return one valid item
          end
        end
      else
        if not (type(game) == "table" and game.item_prototypes) then
          log("[OreGuard] game.item_prototypes not available in on_built_entity event!")
        end
      end
      -- If no item found, do not attempt to insert
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
    local ores = surface.find_entities_filtered{
      area = {{tile.position.x, tile.position.y}, {tile.position.x + 1, tile.position.y + 1}},
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
      table.insert(restore_tiles, {name = restore_name, position = tile.position})
    end
    if #restore_tiles > 0 then
      surface.set_tiles(restore_tiles, true)
    end

    -- Return tiles to player or spill
    local item_name = event.item
    if item_name and item_name ~= "" then
      local stack = {name = item_name, count = #denied_tiles}
      local inserted = player.insert(stack)
      if inserted < #denied_tiles then
        surface.spill_item_stack(player.position, {name = item_name, count = #denied_tiles - inserted}, true, player.force, false)
      end
    end
    player.create_local_flying_text{
      text = {"message.oreguard.cannot-build"},
      position = player.position,
      color = {r=1, g=0.2, b=0.2}
    }
  end
end)
