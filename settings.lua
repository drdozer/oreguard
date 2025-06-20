data:extend({
    {
        type = "string-setting",
        name = "oreguard-tier",
        setting_type = "runtime-global",
        default_value = "default",
        allowed_values = { "hardcore", "mining", "bot-mining", "default", "decorative" },
        order = "a"
    },
    {
        type = "bool-setting",
        name = "oreguard-modify-ore-collision",
        setting_type = "startup",
        default_value = true,
        order = "b"
    },
    {
        type = "bool-setting",
        name = "oreguard-verbose-debugging",
        setting_type = "startup",
        default_value = false,
        order = "c"
    }
})
