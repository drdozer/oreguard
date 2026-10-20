-- OreGuard settings. The oreguard-tier value list mirrors Families.tier_values
-- in families.lua (tools/check-families.py enforces the sync). The stored
-- value "mining" is deliberately unchanged from 0.3.x — the "Belt Mining"
-- name lives in locale [mod-setting-value] (no save migration needed); the
-- decorative tier is gone: tiles-over-ore is governed solely by
-- oreguard-allow-decorative-tiles.
data:extend({
    {
        type = "string-setting",
        name = "oreguard-tier",
        setting_type = "runtime-global",
        default_value = "default",
        allowed_values = { "hardcore", "mining", "bot-mining", "default" },
        order = "a"
    },
    {
        type = "bool-setting",
        name = "oreguard-allow-decorative-tiles",
        setting_type = "runtime-global",
        default_value = false,
        order = "b"
    },
    {
        type = "bool-setting",
        name = "oreguard-modify-ore-collision",
        setting_type = "startup",
        default_value = true,
        order = "b"
    },
    {
        -- Startup (not runtime): with the toggle on, data-final-fixes skips
        -- stamping the oreguard layer onto ground-rail prototypes. A runtime
        -- toggle could never un-stamp data-stage layers, so it would be a
        -- no-op while the engine still refused placement.
        type = "bool-setting",
        name = "oreguard-allow-ground-rail",
        setting_type = "startup",
        default_value = false,
        order = "b1"
    },
    {
        type = "bool-setting",
        name = "oreguard-verbose-debugging",
        setting_type = "startup",
        default_value = false,
        order = "c"
    }
})