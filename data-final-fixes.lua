-- Planet Power Link
-- Planet mods restrict accumulators with surface conditions (Cerys: "Ambient radiation is
-- too high"; Moshine: too hot), and our buildings are accumulators. When the startup
-- setting "Allow on any planet" is on, remove every surface condition from our two
-- buildings so they can be placed anywhere. Other entities are not touched.

if not settings.startup["ppl-allow-cerys"].value then return end

local NAMES = { "ppl-power-link", "ppl-power-receiver" }

for _, name in ipairs(NAMES) do
  local entity = data.raw["accumulator"] and data.raw["accumulator"][name]
  if entity then
    entity.surface_conditions = nil
  end
end
