-- data-final-fixes.lua for OreGuard
-- Add oreguard collision layer and modify ore and rail collision masks

local debug_log = settings.startup["oreguard-verbose-debugging"].value and log or function() end

-- Check if collision mask modification is enabled
if not settings.startup["oreguard-modify-ore-collision"].value then
    log("OreGuard: Ore collision mask modification disabled in settings")
    return
end

log("OreGuard: Starting data-final-fixes - adding oreguard collision layer and modifying collision masks")

local maskutil = require("collision-mask-util")


-- Add custom collision layer for oreguard
data:extend({
    {
        type = "collision-layer",
        name = "oreguard"
    }
})

local ore_modified_count = 0
local rail_modified_count = 0

-- Function to add oreguard layer to collision mask
local function add_oreguard_layer(prototype, entity_name, entity_type)
    local mask = maskutil.get_mask(prototype)
    mask.layers["oreguard"] = true
    prototype.collision_mask = mask
    debug_log("OreGuard: Added oreguard layer to " .. entity_type .. " " .. entity_name)
    return true
end

-- Add oreguard layer to all ore entities
for name, prototype in pairs(data.raw.resource) do
    if add_oreguard_layer(prototype, name, "ore") then
        ore_modified_count = ore_modified_count + 1
    end
end

-- Add oreguard layer to specific rail prototype types
local rail_types = {
    "straight-rail",
    "half-diagonal-rail",
    "curved-rail-a",
    "curved-rail-b"
}

for _, rail_type in ipairs(rail_types) do
    if data.raw[rail_type] then
        for name, prototype in pairs(data.raw[rail_type]) do
            -- Only modify rails where the name matches the type (excludes waterways, etc.)
            if name == rail_type then
                if add_oreguard_layer(prototype, name, rail_type) then
                    rail_modified_count = rail_modified_count + 1
                end
            end
        end
    end
end

log("OreGuard: Modified collision masks for " .. ore_modified_count .. " ore entities")
log("OreGuard: Modified collision masks for " .. rail_modified_count .. " rail entities")
