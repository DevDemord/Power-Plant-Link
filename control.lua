-- Planet Power Link
--
-- Transmitters take spare power from their planet and put it into a shared pool.
-- Receivers take power out of the pool and feed it to their planet when it runs short.
-- Every transmitter and receiver with the same network ID (and force) shares one pool,
-- on any planet or space platform. Click a building to open its window, or use the
-- button at the top of the screen for an overview of every network.
--
-- How power moves: each building is an accumulator on its planet's grid. The script
-- empties/refills those buffers every update and keeps the energy in a central pool,
-- so the flow in and out of the pool can be measured exactly.

-- The game's own helper for the button row at the top of the screen. If it is ever
-- missing, the button is added straight to the top of the screen instead.
local has_mod_gui, mod_gui = pcall(require, "mod-gui")
if not has_mod_gui then mod_gui = nil end

local TX = "ppl-power-link"      -- transmitter (the old entity name, so old saves keep working)
local RX = "ppl-power-receiver"  -- receiver
local TX_COLOR = { r = 0.55, g = 0.85, b = 1.0 }
local RX_COLOR = { r = 1.0, g = 0.72, b = 0.4 }
local SEND, RECEIVE = "send", "receive"
local WINDOW = "ppl_window"
local OVERVIEW = "ppl_overview"

-- Storage -----------------------------------------------------------------

local function ensure_storage()
  storage.nodes = storage.nodes or {}     -- unit_number -> node
  storage.pools = storage.pools or {}     -- "force:network" -> { energy, cap }
  storage.names = storage.names or {}     -- "force:network" -> custom network name
  storage.gui = storage.gui or {}         -- player_index -> unit_number of the node shown
  storage.overview = storage.overview or {} -- player_index -> true while the overview is open
  storage.spots = storage.spots or {}     -- "surface:x:y" -> unit_number of the node standing there
  storage.limits = storage.limits or {}   -- "force:network" -> most power (W) the transmitters may take in total
  storage.view = storage.view or {}       -- player_index -> filters of the Nodes tab
end

local function key_of(force_index, network)
  return force_index .. ":" .. network
end

local function pool_for(key)
  local pool = storage.pools[key]
  if not pool then
    pool = { energy = 0, cap = 0 }
    storage.pools[key] = pool
  end
  return pool
end

local function network_name(force_index, network)
  return storage.names[key_of(force_index, network)] or ("Network " .. network)
end

local function mode_of(entity)
  return (entity.name == RX) and RECEIVE or SEND
end

-- Work cache. It is rebuilt from `storage` whenever a node is added, removed or moved to
-- another network, or when the update interval changes, so it is not saved.
local cache = nil
local cache_dirty = true

local function mark_dirty()
  cache_dirty = true
end

local function new_node(entity, network)
  return {
    entity = entity,
    network = network or 1,
    mode = mode_of(entity),
    cap = 0,        -- buffer size (J), filled in when the cache is built
    key = "",       -- "force:network", filled in when the cache is built
    last_set = 0,   -- energy we left in the buffer at the last update
    acc_in = 0,     -- joules sent into the pool since the last flow figure
    acc_out = 0,    -- joules delivered from the pool since the last flow figure
    acc_ticks = 0,  -- ticks covered by acc_in / acc_out
    flow_in = 0,    -- watts, averaged over about a second
    flow_out = 0,
  }
end

local function spot_key(entity)
  local position = entity.position
  return string.format("%d:%.1f:%.1f", entity.surface_index, position.x, position.y)
end

local function register(entity, network)
  if not (entity and entity.valid) then return nil end
  if entity.name ~= TX and entity.name ~= RX then return nil end
  local id = entity.unit_number
  if not id then return nil end
  local node = storage.nodes[id]
  if not node then
    -- A building placed over another one (fast replace) keeps the old one's network.
    local spot = spot_key(entity)
    local previous_id = storage.spots[spot]
    local previous = previous_id and storage.nodes[previous_id]
    if previous and not (previous.entity and previous.entity.valid) then
      network = network or previous.network
      storage.nodes[previous_id] = nil
    end
    node = new_node(entity, network)
    node.spot = spot
    storage.nodes[id] = node
    storage.spots[spot] = id
    mark_dirty()
  elseif not node.spot then
    node.spot = spot_key(entity)
    storage.spots[node.spot] = id
  end
  node.entity = entity
  node.mode = mode_of(entity)
  node.acc_ticks = node.acc_ticks or 0 -- nodes from older saves
  return node
end

local function drop_node(id)
  local node = storage.nodes[id]
  if node and node.spot and storage.spots[node.spot] == id then
    storage.spots[node.spot] = nil
  end
  storage.nodes[id] = nil
  mark_dirty()
end

local function rescan()
  local old = storage.nodes or {}
  storage.nodes = {}
  storage.spots = {}
  storage.links = nil  -- from versions before 0.5.0
  storage.window = nil -- from versions before 0.8.0
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = { TX, RX } })) do
      local previous = old[entity.unit_number]
      if previous and previous.entity and previous.entity.valid then
        previous.spot = nil
        storage.nodes[entity.unit_number] = previous
        register(entity)
      else
        local node = register(entity)
        if node then entity.energy = 0 end
      end
    end
  end
  mark_dirty()
end

local function unlock_recipe()
  for _, force in pairs(game.forces) do
    for _, name in ipairs({ TX, RX }) do
      local recipe = force.recipes[name]
      if recipe then recipe.enabled = true end
    end
  end
end

-- Give back whatever a node is holding to its pool (used before it is changed or swapped).
local function settle(node)
  local entity = node.entity
  if not (entity and entity.valid) then return end
  local pool = storage.pools[key_of(entity.force_index, node.network)]
  if not pool then return end
  if node.mode == SEND then
    local charged = entity.energy - node.last_set
    if charged > 0 then pool.energy = pool.energy + charged end
  else
    pool.energy = pool.energy + entity.energy
  end
  entity.energy = 0
  node.last_set = 0
end

-- Power sharing -----------------------------------------------------------
--
-- Every node is updated once every `interval` ticks, and the nodes are spread over those
-- ticks (a node's slot is its unit number modulo the interval), so no single tick does all
-- the work. A node's update: collect what it moved since its last update, pay its upkeep,
-- then re-arm it (a transmitter may take more, a receiver is loaded from the pool).

local AUTO_MARGIN = 1.25 -- the automatic send limit allows this much above what is drawn

-- Builds the per-network figures and the update slots. Deterministic: nodes are visited in
-- unit-number order, so every machine in a multiplayer game gets the same result.
local function rebuild(interval)
  local nodes = storage.nodes
  local default_cap = settings.startup["ppl-buffer-gj"].value * 1e9
  local ids = {}
  for id in pairs(nodes) do ids[#ids + 1] = id end
  table.sort(ids)

  local groups, buckets = {}, {}
  for slot = 1, interval do buckets[slot] = {} end

  for _, id in ipairs(ids) do
    local node = nodes[id]
    local entity = node.entity
    if entity and entity.valid then
      node.key = key_of(entity.force_index, node.network)
      node.cap = entity.electric_buffer_size or default_cap
      local group = groups[node.key]
      if not group then
        group = { key = node.key, tx = 0, rx = 0, n = 0, cap = 0, receivers = {} }
        groups[node.key] = group
      end
      group.n = group.n + 1
      group.cap = group.cap + node.cap
      if node.mode == SEND then
        group.tx = group.tx + 1
      else
        group.rx = group.rx + 1
        group.receivers[#group.receivers + 1] = node
      end
      local bucket = buckets[id % interval + 1]
      bucket[#bucket + 1] = id
    else
      drop_node(id)
    end
  end

  for key, pool in pairs(storage.pools) do
    if not groups[key] then pool.cap = 0 end
  end
  for key, group in pairs(groups) do
    pool_for(key).cap = group.cap
  end

  cache = { interval = interval, groups = groups, buckets = buckets, flow_w = settings.startup["ppl-flow-mw"].value * 1e6 }
  cache_dirty = false
end

-- The automatic send limit of every network: what its receivers are drawing, plus upkeep,
-- plus enough to refill the pool in the chosen time. Recomputed about once a second.
local function update_auto_limits()
  if not cache then return end
  local minutes = settings.global["ppl-refill-minutes"].value
  local upkeep_each = settings.global["ppl-upkeep-mw"].value * 1e6
  for _, group in pairs(cache.groups) do
    local pool = pool_for(group.key)
    if minutes <= 0 then
      pool.auto_w = nil
    else
      local drawn = 0
      for _, node in ipairs(group.receivers) do drawn = drawn + node.flow_out end
      local room = pool.cap - pool.energy
      if room < 0 then room = 0 end
      pool.auto_w = (drawn + group.n * upkeep_each) * AUTO_MARGIN + room / (minutes * 60)
    end
  end
end

local function update_node(node, group, interval, upkeep, per_cycle_max, limits)
  local entity = node.entity
  local pool = storage.pools[group.key]
  if not pool then
    pool = pool_for(group.key)
    pool.cap = group.cap
  end
  local energy = pool.energy

  -- 1. Collect what happened since the last update.
  local now = entity.energy
  if node.mode == SEND then
    local charged = now - node.last_set
    if charged < 0 then charged = 0 end
    energy = energy + charged
    node.acc_in = node.acc_in + charged
  else
    local delivered = node.last_set - now
    if delivered < 0 then delivered = 0 end
    energy = energy + now -- unused energy goes back into the pool
    node.acc_out = node.acc_out + delivered
  end

  -- 2. Upkeep is paid from the pool.
  energy = energy - upkeep
  if energy < 0 then energy = 0 end

  -- 3. Re-arm.
  if node.mode == SEND then
    -- A transmitter may only take its share of the room the pool has. The send limit (the
    -- player's own, or the automatic one) also caps what all transmitters take together.
    local room = pool.cap - energy
    if room < 0 then room = 0 end
    local allowance = room / group.tx
    local limit_w = limits[group.key] or pool.auto_w
    if limit_w then
      local share = limit_w * interval / 60 / group.tx
      if share < allowance then allowance = share end
    end
    local take = allowance
    if node.cap < take then take = node.cap end
    if per_cycle_max < take then take = per_cycle_max end
    node.last_set = node.cap - take
    entity.energy = node.last_set
  else
    -- A receiver is loaded with its share of what the pool holds.
    local load = energy / group.rx
    if node.cap < load then load = node.cap end
    if per_cycle_max < load then load = per_cycle_max end
    node.last_set = load
    entity.energy = load
    energy = energy - load
  end
  pool.energy = energy

  -- 4. Flow figures, averaged over about a second (each node keeps its own window).
  node.acc_ticks = node.acc_ticks + interval
  if node.acc_ticks >= 60 then
    local scale = 60 / node.acc_ticks
    node.flow_in = node.acc_in * scale
    node.flow_out = node.acc_out * scale
    node.acc_in = 0
    node.acc_out = 0
    node.acc_ticks = 0
  end
end

local function share_power(tick)
  local nodes = storage.nodes
  if not nodes then return end
  local interval = settings.global["ppl-update-interval"].value
  if cache_dirty or not cache or cache.interval ~= interval then
    rebuild(interval)
    update_auto_limits()
  end

  local bucket = cache.buckets[tick % interval + 1]
  local count = #bucket
  if count == 0 then return end

  local upkeep = settings.global["ppl-upkeep-mw"].value * 1e6 * interval / 60
  local per_cycle_max = cache.flow_w * interval / 60
  local groups, limits = cache.groups, storage.limits

  for i = 1, count do
    local id = bucket[i]
    local node = nodes[id]
    local entity = node and node.entity
    if entity and entity.valid then
      update_node(node, groups[node.key], interval, upkeep, per_cycle_max, limits)
    else
      drop_node(id) -- the building is gone; the cache is rebuilt on the next tick
    end
  end
end

-- Changing a node --------------------------------------------------------

local function set_network(node, network)
  settle(node)
  node.network = network
  mark_dirty()
end

-- Formatting --------------------------------------------------------------

local function fmt_power(w)
  if w >= 1e12 then return string.format("%.2f TW", w / 1e12) end
  if w >= 1e9 then return string.format("%.2f GW", w / 1e9) end
  if w >= 1e6 then return string.format("%.1f MW", w / 1e6) end
  if w >= 1e3 then return string.format("%.0f kW", w / 1e3) end
  return string.format("%.0f W", w)
end

local function fmt_energy(j)
  if j >= 1e12 then return string.format("%.2f TJ", j / 1e12) end
  if j >= 1e9 then return string.format("%.1f GJ", j / 1e9) end
  if j >= 1e6 then return string.format("%.1f MJ", j / 1e6) end
  return string.format("%.0f kJ", j / 1e3)
end

local function fmt_duration(seconds)
  if seconds < 60 then return string.format("%d s", math.floor(seconds)) end
  if seconds < 3600 then return string.format("%d min", math.floor(seconds / 60)) end
  if seconds < 86400 then
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds - hours * 3600) / 60)
    return string.format("%d h %d min", hours, minutes)
  end
  return string.format("%.1f days", seconds / 86400)
end

local function surface_label(surface_index)
  local surface = game.get_surface(surface_index)
  if not surface then return "?" end
  local platform = surface.platform
  if platform then return platform.name end
  return (surface.name:gsub("^%l", string.upper))
end

-- Network figures ----------------------------------------------------------

local function network_stats(force_index, network)
  local stats = { planets = {}, order = {}, tx = 0, rx = 0, n = 0, in_w = 0, out_w = 0 }
  for _, node in pairs(storage.nodes) do
    local entity = node.entity
    if entity and entity.valid and entity.force_index == force_index and node.network == network then
      local index = entity.surface_index
      local planet = stats.planets[index]
      if not planet then
        planet = { tx = 0, rx = 0, in_w = 0, out_w = 0 }
        stats.planets[index] = planet
        stats.order[#stats.order + 1] = index
      end
      stats.n = stats.n + 1
      if node.mode == SEND then
        planet.tx = planet.tx + 1
        stats.tx = stats.tx + 1
      else
        planet.rx = planet.rx + 1
        stats.rx = stats.rx + 1
      end
      planet.in_w = planet.in_w + node.flow_in
      planet.out_w = planet.out_w + node.flow_out
      stats.in_w = stats.in_w + node.flow_in
      stats.out_w = stats.out_w + node.flow_out
    end
  end
  table.sort(stats.order)
  local pool = storage.pools[key_of(force_index, network)]
  stats.pool = pool and pool.energy or 0
  stats.cap = pool and pool.cap or 0
  stats.upkeep_w = stats.n * settings.global["ppl-upkeep-mw"].value * 1e6
  return stats
end

-- How long the pool lasts if no power comes in.
local function reserve_text(stats)
  if stats.pool <= 0 then return "Reserve: the pool is empty" end
  local drain = stats.out_w + stats.upkeep_w
  if drain <= 0 then return "Reserve: nothing is drawing from the pool" end
  return "Reserve: lasts " .. fmt_duration(stats.pool / drain) .. " if no power comes in"
end

-- The send limit the player set for a network in watts, or nil when there is none.
local function send_limit(force_index, network)
  return storage.limits[key_of(force_index, network)]
end

-- The limit that applies right now: the player's own, else the automatic one (or nil).
local function effective_limit(force_index, network)
  local key = key_of(force_index, network)
  local manual = storage.limits[key]
  if manual then return manual end
  local pool = storage.pools[key]
  return pool and pool.auto_w or nil
end

local function limit_field_text(force_index, network)
  local limit = send_limit(force_index, network)
  return limit and string.format("%g", limit / 1e6) or "0"
end

local function limit_text(force_index, network)
  local manual = send_limit(force_index, network)
  if manual then return "Send limit: " .. fmt_power(manual) .. " in total for all transmitters" end
  local automatic = effective_limit(force_index, network)
  if automatic then
    return "Send limit: automatic, " .. fmt_power(automatic) .. " now (what is drawn plus a "
      .. settings.global["ppl-refill-minutes"].value .. " min refill)"
  end
  return "Send limit: none"
end

-- Whether a building is wired into a power network. If the game cannot tell, assume it is.
local function is_connected(entity)
  local ok, id = pcall(function() return entity.electric_network_id end)
  if not ok then return true end
  return id ~= nil
end

-- A short reason for what a building is doing right now. `stats` is its network's figures.
local function status_text(node, stats)
  local entity = node.entity
  if not is_connected(entity) then return "Not connected to a power pole" end
  if node.mode == SEND then
    if node.flow_in > 0 then return "Sending" end
    if stats.cap > 0 and stats.pool >= stats.cap * 0.999 then return "Idle: the pool is full" end
    local limit = effective_limit(entity.force_index, node.network)
    if limit and stats.in_w >= limit * 0.95 then return "Idle: the network is at its send limit" end
    return "Idle: no spare power on this planet"
  end
  if node.flow_out > 0 then return "Delivering" end
  if stats.pool <= 0 then return "Idle: the pool is empty" end
  return "Standing by: this planet covers its own load"
end

-- Whether the pool is filling, draining or steady right now.
local function trend_text(stats)
  local net = stats.in_w - stats.out_w - stats.upkeep_w
  if stats.cap > 0 and stats.pool >= stats.cap * 0.999 and net > -1e6 then
    return "Trend: the pool is full"
  end
  if net > 1e6 then
    local text = "Trend: filling at " .. fmt_power(net)
    if stats.cap > stats.pool then
      text = text .. ", full in " .. fmt_duration((stats.cap - stats.pool) / net)
    end
    return text
  end
  if net < -1e6 then
    return "Trend: draining at " .. fmt_power(-net)
  end
  return "Trend: steady"
end

-- Window building blocks ---------------------------------------------------

local function find_child(element, name)
  if element.name == name then return element end
  for _, child in pairs(element.children) do
    local found = find_child(child, name)
    if found then return found end
  end
  return nil
end

local function add_titlebar(frame, title, close_name)
  local titlebar = frame.add({ type = "flow", direction = "horizontal" })
  titlebar.drag_target = frame
  titlebar.add({
    type = "label", caption = title,
    style = "frame_title", ignored_by_interaction = true,
  })
  local filler = titlebar.add({ type = "empty-widget", style = "draggable_space_header" })
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  filler.drag_target = frame
  titlebar.add({
    type = "sprite-button", name = close_name, style = "frame_action_button",
    sprite = "utility/close",
  })
end

local function add_bar(parent, label, value_text, fraction)
  local row = parent.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  local name = row.add({ type = "label", caption = label })
  name.style.width = 150
  local bar = row.add({ type = "progressbar", value = math.max(0, math.min(1, fraction)) })
  bar.style.horizontally_stretchable = true
  local value = row.add({ type = "label", caption = value_text })
  value.style.minimal_width = 130
  value.style.horizontal_align = "right"
end

-- Totals for a network: power sent and delivered, the pool, its reserve and trend.
local function add_network_summary(parent, stats, force_index, network)
  local flow_w = settings.startup["ppl-flow-mw"].value * 1e6
  add_bar(parent, "Total sent into pool", fmt_power(stats.in_w),
    stats.tx > 0 and stats.in_w / (stats.tx * flow_w) or 0)
  add_bar(parent, "Total delivered", fmt_power(stats.out_w),
    stats.rx > 0 and stats.out_w / (stats.rx * flow_w) or 0)
  add_bar(parent, "Stored in pool", fmt_energy(stats.pool) .. " / " .. fmt_energy(stats.cap),
    stats.cap > 0 and stats.pool / stats.cap or 0)
  parent.add({ type = "label", caption = reserve_text(stats) })
  parent.add({ type = "label", caption = trend_text(stats) })
  parent.add({ type = "label", caption = limit_text(force_index, network) })
  parent.add({
    type = "label",
    caption = "Upkeep: " .. fmt_power(stats.upkeep_w) .. " for " .. stats.n .. " buildings, paid from the pool",
  })
end

local function add_planet_table(parent, stats)
  local grid = parent.add({ type = "table", column_count = 5 })
  grid.style.horizontal_spacing = 18
  for _, header in ipairs({ "Planet", "Transmitters", "Receivers", "Sending", "Receiving" }) do
    local label = grid.add({ type = "label", caption = header })
    label.style.font = "default-bold"
  end
  for _, index in ipairs(stats.order) do
    local planet = stats.planets[index]
    grid.add({ type = "label", caption = surface_label(index) })
    grid.add({ type = "label", caption = tostring(planet.tx) })
    grid.add({ type = "label", caption = tostring(planet.rx) })
    grid.add({ type = "label", caption = fmt_power(planet.in_w) })
    grid.add({ type = "label", caption = fmt_power(planet.out_w) })
  end
  local total = grid.add({ type = "label", caption = "Total" })
  total.style.font = "default-bold"
  grid.add({ type = "label", caption = tostring(stats.tx) })
  grid.add({ type = "label", caption = tostring(stats.rx) })
  grid.add({ type = "label", caption = fmt_power(stats.in_w) })
  grid.add({ type = "label", caption = fmt_power(stats.out_w) })
end

-- Building window ------------------------------------------------------------

local function close_gui(player)
  local window = player.gui.screen[WINDOW]
  if window then window.destroy() end
  storage.gui[player.index] = nil
end

local function refresh_gui(player)
  local window = player.gui.screen[WINDOW]
  local id = storage.gui[player.index]
  if not (window and id) then return end
  local node = storage.nodes[id]
  if not (node and node.entity and node.entity.valid) then
    close_gui(player)
    return
  end

  local box = find_child(window, "ppl_stats")
  if not box then return end
  box.clear()

  local entity = node.entity
  local stats = network_stats(entity.force_index, node.network)
  local flow_w = settings.startup["ppl-flow-mw"].value * 1e6

  local title = box.add({
    type = "label",
    caption = network_name(entity.force_index, node.network) .. "  (ID " .. node.network .. ")",
  })
  title.style.font = "default-large-bold"

  if node.mode == SEND then
    box.add({ type = "label", caption = "This transmitter: sending " .. fmt_power(node.flow_in) .. " into the pool" })
  else
    box.add({ type = "label", caption = "This receiver: delivering " .. fmt_power(node.flow_out) .. " from the pool" })
  end
  box.add({ type = "label", caption = "Status: " .. status_text(node, stats) })
  box.add({ type = "line" })

  -- This planet: what its receivers can pull from the pool and its transmitters can push in.
  local here = stats.planets[entity.surface_index] or { tx = 0, rx = 0, in_w = 0, out_w = 0 }
  local planet_name = surface_label(entity.surface_index)
  local heading = box.add({ type = "label", caption = "On " .. planet_name .. " (this planet)" })
  heading.style.font = "default-bold"

  if here.rx > 0 then
    local receive_cap = here.rx * flow_w
    -- The pool can hand out at most what it has stored, counted over one second.
    local available = math.min(receive_cap, stats.pool)
    local detail = here.rx .. " receivers x " .. fmt_power(flow_w)
    if stats.pool < receive_cap then detail = detail .. ", limited by what is stored in the pool" end
    box.add({ type = "label", caption = "Available to this planet: " .. fmt_power(available) .. " (" .. detail .. ")" })
    add_bar(box, "Receiving now", fmt_power(here.out_w) .. " / " .. fmt_power(available),
      available > 0 and here.out_w / available or 0)
  else
    box.add({ type = "label", caption = "No receivers on " .. planet_name })
  end
  if here.tx > 0 then
    local send_cap = here.tx * flow_w
    add_bar(box, "Sending now", fmt_power(here.in_w) .. " / " .. fmt_power(send_cap),
      here.in_w / send_cap)
  end

  box.add({ type = "line" })
  local network_heading = box.add({ type = "label", caption = "Whole network" })
  network_heading.style.font = "default-bold"
  add_network_summary(box, stats, entity.force_index, node.network)

  box.add({ type = "line" })
  add_planet_table(box, stats)
end

local function open_gui(player, node)
  close_gui(player)

  local frame = player.gui.screen.add({ type = "frame", name = WINDOW, direction = "vertical" })
  frame.auto_center = true
  add_titlebar(frame, "Planet power network", "ppl_close")

  local body = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  body.style.minimal_width = 480

  local controls = body.add({ type = "flow", direction = "horizontal" })
  controls.style.vertical_align = "center"
  controls.add({ type = "label", caption = "This building:" })
  local kind = controls.add({
    type = "label",
    caption = (node.mode == SEND) and "Transmitter" or "Receiver",
    tooltip = "Drag the other kind of building over this one to swap it in place.",
  })
  kind.style.font = "default-bold"
  kind.style.font_color = (node.mode == SEND) and TX_COLOR or RX_COLOR
  local spacer = controls.add({ type = "empty-widget" })
  spacer.style.width = 20
  controls.add({ type = "label", caption = "Network ID:" })
  local field = controls.add({
    type = "textfield", name = "ppl_network", text = tostring(node.network),
    numeric = true, allow_decimal = false, allow_negative = false,
  })
  field.style.width = 70

  local name_row = body.add({ type = "flow", direction = "horizontal" })
  name_row.style.vertical_align = "center"
  name_row.add({ type = "label", caption = "Network name:" })
  local name_field = name_row.add({
    type = "textfield", name = "ppl_name",
    text = network_name(node.entity.force_index, node.network),
  })
  name_field.style.width = 240

  local limit_row = body.add({ type = "flow", direction = "horizontal" })
  limit_row.style.vertical_align = "center"
  limit_row.add({
    type = "label", caption = "Send limit (MW, 0 = automatic):",
    tooltip = "The most power all transmitters of this network may take together. " ..
      "0 uses the automatic limit (see the pool refill time setting).",
  })
  local limit_field = limit_row.add({
    type = "textfield", name = "ppl_limit",
    text = limit_field_text(node.entity.force_index, node.network),
    numeric = true, allow_decimal = true, allow_negative = false,
  })
  limit_field.style.width = 90

  body.add({ type = "line" })
  body.add({ type = "flow", name = "ppl_stats", direction = "vertical" })

  player.opened = frame
  storage.gui[player.index] = node.entity.unit_number
  refresh_gui(player)
end

-- Overview window (the button at the top of the screen) ------------------------

local function close_overview(player)
  local window = player.gui.screen[OVERVIEW]
  if window then window.destroy() end
  storage.overview[player.index] = nil
end

-- "Networks" tab: totals and the planet table for every network.
local function refresh_networks_tab(window, player)
  local body = find_child(window, "ppl_overview_body")
  if not body then return end
  body.clear()

  local force_index = player.force_index
  local ids, seen = {}, {}
  for _, node in pairs(storage.nodes) do
    local entity = node.entity
    if entity and entity.valid and entity.force_index == force_index and not seen[node.network] then
      seen[node.network] = true
      ids[#ids + 1] = node.network
    end
  end
  table.sort(ids)

  if #ids == 0 then
    body.add({ type = "label", caption = "No transmitters or receivers built yet." })
    return
  end

  for position, network in ipairs(ids) do
    if position > 1 then body.add({ type = "line" }) end
    local stats = network_stats(force_index, network)
    local heading = body.add({
      type = "label",
      caption = network_name(force_index, network) .. "  (ID " .. network .. ")",
    })
    heading.style.font = "default-large-bold"
    add_network_summary(body, stats, force_index, network)
    add_planet_table(body, stats)
  end
end

-- "Nodes" tab: one row per building, with a button that shows it on the map.
local function refresh_nodes_tab(window, player)
  local body = find_child(window, "ppl_nodes_body")
  local planet_dropdown = find_child(window, "ppl_filter_planet")
  local kind_dropdown = find_child(window, "ppl_filter_kind")
  if not (body and planet_dropdown and kind_dropdown) then return end

  local view = storage.view[player.index]
  if not view then
    view = {}
    storage.view[player.index] = view
  end
  local force_index = player.force_index

  -- Collect this force's buildings and the planets they are on.
  local rows, planets, seen = {}, {}, {}
  for id, node in pairs(storage.nodes) do
    local entity = node.entity
    if entity and entity.valid and entity.force_index == force_index then
      local label = surface_label(entity.surface_index)
      rows[#rows + 1] = { id = id, node = node, planet = label }
      if not seen[entity.surface_index] then
        seen[entity.surface_index] = true
        planets[#planets + 1] = { index = entity.surface_index, label = label }
      end
    end
  end
  table.sort(planets, function(a, b) return a.label < b.label end)

  -- Keep the planet filter in step with the planets that have buildings.
  local items, selected, ids = { "All planets" }, 1, {}
  for position, planet in ipairs(planets) do
    items[#items + 1] = planet.label
    ids[#ids + 1] = planet.index
    if view.planet == planet.index then selected = position + 1 end
  end
  if view.planet and selected == 1 then view.planet = nil end
  view.planet_ids = ids
  local signature = table.concat(items, "|")
  if view.signature ~= signature then
    planet_dropdown.items = items
    view.signature = signature
  end
  if planet_dropdown.selected_index ~= selected then planet_dropdown.selected_index = selected end
  local wanted_kind = (view.kind == SEND and 2) or (view.kind == RECEIVE and 3) or 1
  if kind_dropdown.selected_index ~= wanted_kind then kind_dropdown.selected_index = wanted_kind end

  -- Apply the filters and sort: planet name, transmitters before receivers, then build order.
  local shown = {}
  for _, row in ipairs(rows) do
    local on_planet = (not view.planet) or row.node.entity.surface_index == view.planet
    local of_kind = (not view.kind) or row.node.mode == view.kind
    if on_planet and of_kind then shown[#shown + 1] = row end
  end
  local function rank(row) return row.node.mode == SEND and 1 or 2 end
  table.sort(shown, function(a, b)
    if a.planet ~= b.planet then return a.planet < b.planet end
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return a.id < b.id
  end)

  body.clear()
  body.add({
    type = "label",
    caption = "Showing " .. #shown .. " of " .. #rows .. " buildings",
  })
  if #shown == 0 then return end

  -- Fixed column widths, so the table does not change shape when the status text changes.
  local WIDTHS = { 100, 90, 100, 100, 80, 300, 70 }
  local grid = body.add({ type = "table", column_count = 7 })
  grid.style.horizontal_spacing = 10
  local function cell(caption, column, bold)
    local label = grid.add({ type = "label", caption = caption })
    label.style.width = WIDTHS[column]
    if bold then label.style.font = "default-bold" end
    return label
  end
  for column, header in ipairs({ "Planet", "Type", "Network", "Position", "Power now", "Status" }) do
    cell(header, column, true)
  end
  grid.add({ type = "empty-widget" }).style.width = WIDTHS[7]

  local stats_by_key = {}
  for _, row in ipairs(shown) do
    local node, entity = row.node, row.node.entity
    local key = key_of(entity.force_index, node.network)
    local stats = stats_by_key[key]
    if not stats then
      stats = network_stats(entity.force_index, node.network)
      stats_by_key[key] = stats
    end
    cell(row.planet, 1)
    cell(node.mode == SEND and "Transmitter" or "Receiver", 2)
    cell(network_name(entity.force_index, node.network), 3)
    cell(string.format("%d, %d", math.floor(entity.position.x), math.floor(entity.position.y)), 4)
    cell(fmt_power(node.mode == SEND and node.flow_in or node.flow_out), 5)
    cell(status_text(node, stats), 6)
    -- Buttons in one table cannot share a name, so the building is kept in the tags.
    local show = grid.add({ type = "button", caption = "Show", tags = { ppl_show = row.id } })
    show.style.width = WIDTHS[7]
  end
end

local function refresh_overview(player)
  local window = player.gui.screen[OVERVIEW]
  if not window then return end
  local tabs = find_child(window, "ppl_tabs")
  if tabs and tabs.selected_tab_index == 2 then
    refresh_nodes_tab(window, player)
  else
    refresh_networks_tab(window, player)
  end
end

-- Opens the map on a building, even when it is on another planet, and circles it.
local function show_node(player, id)
  local node = storage.nodes[id]
  local entity = node and node.entity
  if not (entity and entity.valid) then
    player.print("That building no longer exists.")
    return
  end
  local position, surface = entity.position, entity.surface

  local ok = pcall(function() player.zoom_to_world(position, nil, surface) end)
  if not ok then
    ok = pcall(function()
      player.set_controller({ type = defines.controllers.remote, position = position, surface = surface })
    end)
  end
  if not ok then
    player.print(string.format("Could not open the map. It is on %s at %d, %d.",
      surface_label(entity.surface_index), math.floor(position.x), math.floor(position.y)))
  end

  pcall(function()
    rendering.draw_circle({
      color = { r = 1, g = 0.8, b = 0.1 }, radius = 3.5, width = 4,
      target = entity, surface = surface, time_to_live = 600, players = { player },
    })
  end)
end

local function open_overview(player)
  close_overview(player)

  local frame = player.gui.screen.add({ type = "frame", name = OVERVIEW, direction = "vertical" })
  frame.auto_center = true
  add_titlebar(frame, "Planet power networks", "ppl_overview_close")

  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local tabs = inner.add({ type = "tabbed-pane", name = "ppl_tabs" })

  -- Tab 1: networks
  local networks_tab = tabs.add({ type = "tab", caption = "Networks" })
  local networks_scroll = tabs.add({ type = "scroll-pane" })
  networks_scroll.style.maximal_height = 640
  networks_scroll.style.minimal_width = 640
  networks_scroll.add({ type = "flow", name = "ppl_overview_body", direction = "vertical" })
  tabs.add_tab(networks_tab, networks_scroll)

  -- Tab 2: nodes
  local nodes_tab = tabs.add({ type = "tab", caption = "Nodes" })
  local nodes_flow = tabs.add({ type = "flow", direction = "vertical" })
  local filters = nodes_flow.add({ type = "flow", direction = "horizontal" })
  filters.style.vertical_align = "center"
  filters.add({ type = "label", caption = "Planet:" })
  filters.add({
    type = "drop-down", name = "ppl_filter_planet", items = { "All planets" }, selected_index = 1,
  })
  filters.add({ type = "label", caption = "Type:" })
  filters.add({
    type = "drop-down", name = "ppl_filter_kind",
    items = { "All", "Transmitters", "Receivers" }, selected_index = 1,
  })
  local nodes_scroll = nodes_flow.add({ type = "scroll-pane" })
  nodes_scroll.style.maximal_height = 600
  nodes_scroll.style.minimal_width = 840
  nodes_scroll.style.maximal_width = 840
  nodes_scroll.add({ type = "flow", name = "ppl_nodes_body", direction = "vertical" })
  tabs.add_tab(nodes_tab, nodes_flow)

  player.opened = frame
  storage.overview[player.index] = true
  refresh_overview(player)
end

-- The button at the top of the screen
local function ensure_button(player)
  local flow = mod_gui and mod_gui.get_button_flow(player) or player.gui.top
  if not flow.ppl_toggle then
    flow.add({
      type = "sprite-button", name = "ppl_toggle", sprite = "item/ppl-power-link",
      style = mod_gui and mod_gui.button_style or nil, tooltip = "Planet power networks",
    })
  end
end

local function ensure_buttons()
  for _, player in pairs(game.players) do
    ensure_button(player)
  end
end

-- Events ------------------------------------------------------------------

script.on_init(function()
  ensure_storage()
  rescan()
  unlock_recipe()
  ensure_buttons()
end)

script.on_configuration_changed(function()
  ensure_storage()
  rescan()
  unlock_recipe()
  ensure_buttons()
end)

script.on_event({ defines.events.on_player_created, defines.events.on_player_joined_game }, function(event)
  local player = game.get_player(event.player_index)
  if player then ensure_button(player) end
end)

script.on_event(defines.events.on_tick, function(event)
  share_power(event.tick)
end)

script.on_nth_tick(60, update_auto_limits)

script.on_nth_tick(30, function()
  if not storage.gui then return end
  for player_index in pairs(storage.gui) do
    local player = game.get_player(player_index)
    if player and player.valid and player.connected then
      refresh_gui(player)
    else
      storage.gui[player_index] = nil
    end
  end
  for player_index in pairs(storage.overview) do
    local player = game.get_player(player_index)
    if player and player.valid and player.connected then
      refresh_overview(player)
    else
      storage.overview[player_index] = nil
    end
  end
end)

local built_events = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
  defines.events.on_entity_cloned,
}
if defines.events.on_space_platform_built_entity then
  table.insert(built_events, defines.events.on_space_platform_built_entity)
end

script.on_event(built_events, function(event)
  ensure_storage()
  register(event.entity or event.destination)
end)

-- Opening one of our buildings (the normal accumulator window) is replaced by our window.
script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type ~= defines.gui_type.entity then return end
  local entity = event.entity
  if not (entity and entity.valid and (entity.name == TX or entity.name == RX)) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  ensure_storage()
  local node = register(entity)
  if node then open_gui(player, node) end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if element.name == "ppl_close" then
    close_gui(player)
  elseif element.name == "ppl_overview_close" then
    close_overview(player)
  elseif element.name == "ppl_toggle" then
    ensure_storage()
    if player.gui.screen[OVERVIEW] then
      close_overview(player)
    else
      open_overview(player)
    end
  else
    local tags = element.tags
    if tags and tags.ppl_show then
      ensure_storage()
      show_node(player, tags.ppl_show)
    end
  end
end)

-- The Nodes tab filters.
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name ~= "ppl_filter_planet" and element.name ~= "ppl_filter_kind" then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  ensure_storage()
  local view = storage.view[player.index]
  if not view then
    view = {}
    storage.view[player.index] = view
  end
  if element.name == "ppl_filter_planet" then
    local ids = view.planet_ids or {}
    view.planet = element.selected_index > 1 and ids[element.selected_index - 1] or nil
  else
    view.kind = (element.selected_index == 2 and SEND) or (element.selected_index == 3 and RECEIVE) or nil
  end
  refresh_overview(player)
end)

script.on_event(defines.events.on_gui_selected_tab_changed, function(event)
  local player = game.get_player(event.player_index)
  if player then refresh_overview(player) end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if element.name == WINDOW then
    close_gui(player)
  elseif element.name == OVERVIEW then
    close_overview(player)
  end
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  local id = storage.gui[player.index]
  local node = id and storage.nodes[id]
  if not node then return end
  local force_index = node.entity.force_index

  if element.name == "ppl_network" then
    local network = tonumber(element.text)
    if network and network >= 0 then
      set_network(node, math.floor(network))
    end
    element.text = tostring(node.network)
    -- The name and limit boxes show the values of whichever network the building is in now.
    local name_field = find_child(player.gui.screen[WINDOW], "ppl_name")
    if name_field then name_field.text = network_name(force_index, node.network) end
    local limit_field = find_child(player.gui.screen[WINDOW], "ppl_limit")
    if limit_field then limit_field.text = limit_field_text(force_index, node.network) end
    refresh_gui(player)
  elseif element.name == "ppl_name" then
    local text = element.text:match("^%s*(.-)%s*$")
    local key = key_of(force_index, node.network)
    if text == "" then
      storage.names[key] = nil
    else
      storage.names[key] = text
    end
    element.text = network_name(force_index, node.network)
    refresh_gui(player)
    if player.gui.screen[OVERVIEW] then refresh_overview(player) end
  elseif element.name == "ppl_limit" then
    -- Megawatts typed by the player; 0 or a blank box means no limit.
    local megawatts = tonumber(element.text) or 0
    local key = key_of(force_index, node.network)
    if megawatts > 0 then
      storage.limits[key] = megawatts * 1e6
    else
      storage.limits[key] = nil
    end
    element.text = limit_field_text(force_index, node.network)
    refresh_gui(player)
    if player.gui.screen[OVERVIEW] then refresh_overview(player) end
  end
end)

-- /ppl-status prints a short summary of every network.
commands.add_command("ppl-status", "Shows every planet power network: nodes, pool and flow.", function(command)
  local out = command.player_index and game.get_player(command.player_index) or game
  ensure_storage()
  local seen = {}
  for _, node in pairs(storage.nodes) do
    local entity = node.entity
    if entity and entity.valid then
      seen[key_of(entity.force_index, node.network)] = { entity.force_index, node.network }
    end
  end
  if not next(seen) then
    out.print("No planet power transmitters or receivers built yet.")
    return
  end
  for _, pair in pairs(seen) do
    local stats = network_stats(pair[1], pair[2])
    out.print(string.format(
      "%s, %s (ID %d): %d transmitters, %d receivers on %d surfaces; pool %s / %s; sending %s, delivering %s; %s",
      game.forces[pair[1]].name, network_name(pair[1], pair[2]), pair[2], stats.tx, stats.rx, #stats.order,
      fmt_energy(stats.pool), fmt_energy(stats.cap), fmt_power(stats.in_w), fmt_power(stats.out_w),
      limit_text(pair[1], pair[2])
    ))
  end
end)
