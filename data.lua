-- Planet Power Link
-- Two 4x4 buildings made from the vanilla accumulator:
--   * Planet power transmitter (blue): only charges from its planet's spare power.
--   * Planet power receiver (orange): only feeds power into its planet.
-- control.lua connects them through a shared pool of energy.

-- Each building has its own item and recipe. The transmitter keeps the old name so old
-- saves keep working.
local TX = "ppl-power-link"      -- transmitter
local RX = "ppl-power-receiver"  -- receiver

local TX_TINT = { r = 0.55, g = 0.85, b = 1.0 }
local RX_TINT = { r = 1.0, g = 0.72, b = 0.4 }

local buffer_gj = settings.startup["ppl-buffer-gj"].value
local flow_mw = settings.startup["ppl-flow-mw"].value
local scale_recipe = settings.startup["ppl-scale-recipe"].value

-- A node that moves more power costs proportionally more, so one big node is never cheaper
-- than the same capacity in small ones. 1000 MW is the base (x1); 10000 MW costs x10.
local cost_multiplier = scale_recipe and math.max(1, flow_mw / 1000) or 1

-- Tint every visible layer of a sprite/animation table (skips shadows and glow layers).
local function tint_all(t, tint)
  if type(t) ~= "table" then return end
  if (t.filename or t.stripes) and not t.draw_as_shadow and not t.draw_as_light then
    t.tint = tint
  end
  for key, value in pairs(t) do
    if key ~= "stripes" and type(value) == "table" then
      tint_all(value, tint)
    end
  end
end

-- Turn a single icon into a tinted icons list.
local function tint_icon(proto, tint)
  if proto.icon then
    proto.icons = {
      {
        icon = proto.icon,
        icon_size = proto.icon_size,
        icon_mipmaps = proto.icon_mipmaps,
        tint = tint,
      },
    }
    proto.icon = nil
    proto.icon_size = nil
    proto.icon_mipmaps = nil
  elseif proto.icons then
    for _, layer in pairs(proto.icons) do
      layer.tint = tint
    end
  end
end

-- Size: 4x4 tiles instead of the vanilla accumulator's 2x2.
local SIZE_SCALE = 2

local function scale_shift(shift)
  if not shift then return end
  if shift[1] then
    shift[1] = shift[1] * SIZE_SCALE
    shift[2] = shift[2] * SIZE_SCALE
  elseif shift.x then
    shift.x = shift.x * SIZE_SCALE
    shift.y = shift.y * SIZE_SCALE
  end
end

-- Enlarge every sprite/animation layer, and the lights, by SIZE_SCALE.
local function scale_all(t)
  if type(t) ~= "table" then return end
  if t.filename or t.stripes then
    t.scale = (t.scale or 1) * SIZE_SCALE
    scale_shift(t.shift)
  elseif t.intensity and t.size then
    t.size = t.size * SIZE_SCALE
  end
  for key, value in pairs(t) do
    if key ~= "stripes" and key ~= "shift" and type(value) == "table" then
      scale_all(value)
    end
  end
end

local function make_entity(name, tint, input_flow, output_flow)
  local entity = table.deepcopy(data.raw["accumulator"]["accumulator"])
  entity.name = name
  entity.minable = { mining_time = 0.2, result = name }
  -- Same size and group, so one can be dragged over the other to swap it in place.
  entity.fast_replaceable_group = "ppl-power-node"
  entity.energy_source = {
    type = "electric",
    buffer_capacity = string.format("%.3fGJ", buffer_gj),
    usage_priority = "tertiary",
    input_flow_limit = input_flow,
    output_flow_limit = output_flow,
  }
  tint_icon(entity, tint)
  tint_all(entity.chargable_graphics, tint)
  scale_all(entity.chargable_graphics)
  entity.collision_box = { { -1.9, -1.9 }, { 1.9, 1.9 } }
  entity.selection_box = { { -2, -2 }, { 2, 2 } }
  entity.drawing_box = nil
  entity.max_health = 500
  -- The vanilla circuit connector and water reflection are sized for a 2x2 entity.
  entity.circuit_connector = nil
  entity.water_reflection = nil
  return entity
end

local flow = string.format("%.3fMW", flow_mw)
-- The transmitter can only charge (take power from its planet), never discharge.
local transmitter = make_entity(TX, TX_TINT, flow, "0W")
-- The receiver can only discharge (give power to its planet), never charge.
local receiver = make_entity(RX, RX_TINT, "0W", flow)

-- Items: one for each building.
local function make_item(name, tint, order)
  local item = table.deepcopy(data.raw["item"]["accumulator"])
  item.name = name
  item.place_result = name
  item.order = order
  tint_icon(item, tint)
  return item
end

local tx_item = make_item(TX, TX_TINT, "e[accumulator]-b[" .. TX .. "]")
local rx_item = make_item(RX, RX_TINT, "e[accumulator]-c[" .. RX .. "]")

-- Recipes: unlocked from the start of the game, but expensive. Every ingredient can be
-- made from Nauvis resources only (no other planet needed). Both buildings cost the same.
local BASE_INGREDIENTS = {
  { "steel-plate", 100 },
  { "copper-plate", 100 },
  { "accumulator", 20 },
  { "advanced-circuit", 20 },
  { "processing-unit", 20 },
  { "low-density-structure", 10 },
  { "uranium-fuel-cell", 10 },
  { "uranium-235", 10 },
}

local function make_recipe(name)
  local ingredients = {}
  for _, entry in ipairs(BASE_INGREDIENTS) do
    ingredients[#ingredients + 1] = {
      type = "item",
      name = entry[1],
      amount = math.max(1, math.ceil(entry[2] * cost_multiplier - 1e-9)),
    }
  end
  return {
    type = "recipe",
    name = name,
    enabled = true,
    -- "crafting-with-fluid" is not one of the categories the player character can
    -- handcraft, so this can only be made in an assembling machine 2 or better.
    category = "crafting-with-fluid",
    energy_required = 180,
    ingredients = ingredients,
    results = { { type = "item", name = name, amount = 1 } },
  }
end

data:extend({ transmitter, receiver, tx_item, rx_item, make_recipe(TX), make_recipe(RX) })
