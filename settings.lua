data:extend({
  -- Startup settings (need a game restart to change)
  {
    type = "double-setting",
    name = "ppl-buffer-gj",
    setting_type = "startup",
    default_value = 1000,
    minimum_value = 0.1,
    maximum_value = 1000,
    order = "a",
  },
  {
    type = "double-setting",
    name = "ppl-flow-mw",
    setting_type = "startup",
    default_value = 10000,
    minimum_value = 1,
    maximum_value = 10000,
    order = "b",
  },
  {
    type = "bool-setting",
    name = "ppl-scale-recipe",
    setting_type = "startup",
    default_value = true,
    order = "c",
  },
  {
    type = "bool-setting",
    name = "ppl-allow-cerys",
    setting_type = "startup",
    default_value = true,
    order = "d",
  },

  -- Runtime settings (can be changed in a running game)
  {
    type = "double-setting",
    name = "ppl-upkeep-mw",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 0,
    maximum_value = 600,
    order = "a",
  },
  {
    type = "int-setting",
    name = "ppl-update-interval",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 60,
    order = "b",
  },
  {
    type = "int-setting",
    name = "ppl-refill-minutes",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 0,
    maximum_value = 10000,
    order = "c",
  },
})
