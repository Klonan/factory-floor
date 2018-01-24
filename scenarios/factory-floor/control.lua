require ("mod-gui")
require ("production-score")
require ("tile_data")


--[[

TODO

 - Make player charactesr + give some equipment they can sell
 - Fix map so you can see bases on the minimap
 - Fix unoptimisation
 - Fix all ugly guis + bumpyness
 - Tweak electrcity price
 - fix 1 craft item bug
]]
--if true then return end
script.on_init(function (event)
  game.map_settings.pollution.enabled = false
  local surface = game.surfaces[1]
  surface.always_day = true
  global.sell_rate = 1.00
  global.buy_rate = 1.00
  global.price_per_energy = 1/200000
  global.bounding_limit = 60 --Don't let the player go out further than 60x square
  global.average_period = 2*60*60
  global.buy_chests = {}
  global.sell_chests = {}
  global.accumulators = {}
  global.income = {}
  global.expenses = {}
  global.average_expense = {}
  global.average_income = {}
  global.profit = {}
  global.areas = {}
  global.initial_price_list = production_score.generate_price_list()
  local new = {}
  for name, price in spairs (global.initial_price_list, function(t,a,b) return t[a] < t[b] end) do
    new[name] = price
  end
  global.price_list = new
  --save_map_data(100)
  set_research()
  global.cash = {}
  for k, entity in pairs (game.surfaces[1].find_entities()) do
    entity.destroy()
  end
  local tiles = {}
  local i = 1
  for x = -100,100 do
    for y = -100,100 do
      tiles[i] = {name = "out-of-map", position = {x,y}}
      i = i + 1
    end
  end
  game.surfaces[1].set_tiles(tiles)
  game.surfaces[1].set_tiles({{name = "grass-1", position = {0,0}}})
end)

function force_init(force, index)
  force.manual_crafting_speed_modifier = -1 --Disable handcrafting 
  global.cash[force.name] = 10000
  force.research_all_technologies()
  local spawn_position = get_spawn_coordinate(index)
  recreate_map(tiles, entities, spawn_position, force)
  force.set_spawn_position(spawn_position, game.surfaces[1])
  global.areas[force.name] = {{spawn_position[1] - 40, spawn_position[2] - 40}, {spawn_position[1] + 40, spawn_position[2] + 40}}
end

script.on_event(defines.events.on_built_entity, function(event)
  on_built_entity(event)
end)

function on_built_entity(event)
  local entity = event.created_entity
  local player = game.players[event.player_index]
  local area = global.areas[player.force.name]
  if entity.position.x < area[1][1] or
    entity.position.x > area[2][1] or
    entity.position.y < area[1][2] or
    entity.position.y > area[2][2] then
    if entity.name ~= "entity-ghost" then
      player.insert{name = entity.name, count = 1}
    end
    entity.destroy()
  end
end

script.on_configuration_changed(generate_price_list)

script.on_event(defines.events.on_player_created, function (event)
  
  local player = game.players[event.player_index]
  local character = player.character
  player.character = nil
  if character then 
    character.destroy()
  end
  player.cheat_mode = true
  
  if (#game.players <= 1) then
    --game.show_message_dialog{text = {"factory-intro"}}
  end
  if player.name ~= "" then
    player.force = game.create_force(player.name)  
    force_init(player.force, player.index)
    player.teleport(player.force.get_spawn_position(game.surfaces[1]))
  end
  add_toggle_buttons(player)
end)

script.on_event(defines.events.on_tick, function(event)
  -- if true and event.tick > 0 then
    -- game.surfaces[1].create_entity{name = "logistic-robot", position = get_spawn_coordinate(event.tick)}
    -- return
  -- end
  index = (game.tick%global.average_period)+1
  reset_income(index)
  reset_expenses(index)
  electric_exchange(index)
  sell_items(index)
  buy_items(index)
  calculate_income_and_expenses(index)
  if game.tick % 3 == 0 then
    for k, player in pairs (game.players) do
      update_cash(player)
    end
  end
  --check_bounding(global.bounding_limit)
  remove_next_tick_items()
  update_leaderboard()
  --tend_prices_back()
  --update_prices()
end)

function update_leaderboard()
  if game.tick % 60 ~= 0 then return end
  for k, player in pairs (game.players) do
    local gui = mod_gui.get_frame_flow(player)
    local leaderboard = gui.leaderboard_frame
    if leaderboard then
      leaderboard.leaderboard_table.clear()
      fill_leaderboard_table(leaderboard.leaderboard_table)
    end
  end
end

function sell_items(index)
  local sell_roster = {}
  local price_list = global.price_list
  local chest_inventory = defines.inventory.chest
  local sell_rate = global.sell_rate
  local cash = global.cash
  local income = global.income
  local index = index
  local flow_statistics = {}
  local update_chest = function(chest)
    local force_name = chest.force
    local chest = chest.entity
    if not chest.valid then return end
    local inventory = chest.get_inventory(chest_inventory)
    for item_name, item_count in pairs (inventory.get_contents()) do
      if price_list[item_name] then
        local cost = (item_count*price_list[item_name])*sell_rate
        chest.remove_item{name = item_name, count = item_count}
        sell_roster[item_name] = sell_roster[item_name] or 0
        sell_roster[item_name] = sell_roster[item_name] - item_count
        cash[force_name] = cash[force_name] + cost
        income[force_name][index] = income[force_name][index] or 0
        income[force_name][index] = income[force_name][index] + cost
        flow_statistics[force_name] = flow_statistics[force_name] or 0
        flow_statistics[force_name] = flow_statistics[force_name] + cost
      end
    end
    return true
  end
  local chests = global.sell_chests
  local tick = game.tick
  for k, chest in pairs (chests) do
    --if (k + tick) % 60 == 0 then
      if not update_chest(chest) then
        chests[k] = nil
      end
    --end
  end
  for force_name, coin in pairs (flow_statistics) do
    game.forces[force_name].item_production_statistics.on_flow("coin", coin)
  end
  update_roster(sell_roster)
end

function buy_items(index)
  local buy_roster = {}
  local chest_inventory = defines.inventory.chest
  local price_list = global.price_list
  local cash = global.cash
  local buy_rate = global.buy_rate
  local expenses = global.expenses
  local index = index
  local flow_statistics = {}
  local update_chest = function(chest)
    local force_name = chest.force
    local chest = chest.entity
    if not chest.valid then return end
    local inventory = chest.get_inventory(chest_inventory)
    for k = 1,10 do
      local stack = chest.get_request_slot(k)
      if stack then
        local stack_name = stack.name
        local stack_count = stack.count
        if inventory.get_item_count(stack_name) < stack_count then 
          local buy_count = stack_count - inventory.get_item_count(stack_name)
          if price_list[stack_name] then
            local price = price_list[stack_name]
            local cost = round(buy_count*price*buy_rate)
            if cash[force_name] > cost and inventory.can_insert(stack) then
              cash[force_name] = cash[force_name] - cost
              chest.insert{name = stack_name, count = buy_count}
              buy_roster[stack_name] = buy_roster[stack_name] or 0
              buy_roster[stack_name] = buy_roster[stack_name] + buy_count
              expenses[force_name][index] = expenses[force_name][index] or 0
              expenses[force_name][index] = expenses[force_name][index] + cost
              flow_statistics[force_name] = flow_statistics[force_name] or 0
              flow_statistics[force_name] = flow_statistics[force_name] - cost
            end
          end
        end
      end
    end
    return true
  end
  local chests = global.buy_chests
  local tick = game.tick
  for k, chest in pairs (chests) do
    --if (k + tick) % 60 == 0 then
      if not update_chest(chest) then
        chests[k] = nil
      end
    --end
  end
  for force_name, coin in pairs (flow_statistics) do
    game.forces[force_name].item_production_statistics.on_flow("coin", coin)
  end
  update_roster(buy_roster)
end

function update_roster(roster_update)
  local roster = global.roster
  if not roster then roster = {} end
  for name, count in pairs (roster_update) do
    if not roster[name] then
      roster[name] = count
    else
      roster[name] = roster[name] + count
    end
  end
  --game.print(serpent.block(roster))
  global.roster = roster
end

function update_prices()
  if game.tick % 60*60 ~= 0 then return end
  local roster = global.roster
  if not roster then return end
  --local initial_price_list = global.initial_price_list
  local price_list = global.price_list
  local abs = math.abs
  local log = math.log
  for name, count in pairs (roster) do
    if count ~= 0 then
      local original_price = initial_price_list[name]
      local sign = 1
      if count < 0 then 
        sign = -1
      end
      local current_price = price_list[name]
      local elasticity = 0.01*log(original_price+1)
      local difference = (1 + abs(original_price-current_price)/original_price)^2
      local something = 1.15-difference
      local change = ((elasticity/difference)*(log(abs(count))*sign))*something
      local new_price = current_price + (change*original_price)
      --game.print("name - "..name)
      --game.print("count - "..count)
      --game.print("sign - "..sign)
      --game.print(">  original - "..original_price)
      --game.print(">  current - "..current_price)
      --game.print("elasticity - "..elasticity)
      --game.print("difference - "..difference)
      --game.print(">  new - "..new_price)
      --game.print(">  change - "..new_price-current_price)
      --game.print(">  something - "..something)
      price_list[name] = new_price
    end
  end
  global.price_list = price_list
  global.roster = {}
  update_price_list()
end

function electric_exchange(index)
  local index = index
  local cash = global.cash
  local sell_rate = global.sell_rate or 1
  local buy_rate = global.buy_rate or 1
  local price_per_energy = global.price_per_energy
  local flow_statistics = {}
  local expenses = global.expenses
  local income = global.income
  local energy_amount = 2.5*10^9
  local update_accumulator = function (accumulator)
  end
  local accumulators = global.accumulators
  for k, accumulator in pairs (accumulators) do
    if accumulator.valid then 
      local force_name = accumulator.force.name
      local difference = accumulator.energy - energy_amount
      if difference ~= 0 then 
        local cost = difference*price_per_energy
        if cost > 0 then
          cash[force_name] = cash[force_name] + (cost*sell_rate)
          accumulator.energy = energy_amount
          income[force_name][index] = income[force_name][index] or 0
          income[force_name][index] = income[force_name][index] + cost
          flow_statistics[force_name] = flow_statistics[force_name] or 0
          flow_statistics[force_name] = flow_statistics[force_name] + cost
        elseif cost < 0 then
          cash[force_name] = cash[force_name] + (cost*buy_rate)
          accumulator.energy = energy_amount
          expenses[force_name][index] = expenses[force_name][index] or 0
          expenses[force_name][index] = expenses[force_name][index] + cost
          flow_statistics[force_name] = flow_statistics[force_name] or 0
          flow_statistics[force_name] = flow_statistics[force_name] + cost
        end
      end
    end
  end
  for force_name, coin in pairs (flow_statistics) do
    game.forces[force_name].item_production_statistics.on_flow("coin", coin)
  end
end

function update_cash(player)
  local gui = mod_gui.get_frame_flow(player)
  if gui.cash == nil then
    local frame = gui.add{name = "cash", type = "frame", direction = "vertical"}
    frame.style.minimal_width = 150
    frame.style.left_padding = 10
    frame.style.top_padding = 8
    frame.add
      {
        name="cash_amount",
        type = "label",
        caption={"", {"cash"}, " ", comma_value(round(global.cash[player.force.name])) }
      } 
    frame.add
      {
        name="income_amount",
        type = "label",
        caption={"", {"income"}, " ", comma_value(round((global.average_income[player.force.name]/global.average_period)*60)),"/m" }
      } 
    frame.add
      {
        name="expense_amount",
        type = "label",
        caption={"", {"expense"}, " ", comma_value(round((global.average_expense[player.force.name]/global.average_period)*60)),"/m" }
      }
    frame.add
      {
        name="profit_amount",
        type = "label",
        caption={"", {"profit"}, " ", comma_value(round(global.profit[player.force.name]*60)),"/m" }
      }
  else
    gui.cash.cash_amount.caption = {"", {"cash"}, " ", comma_value(round(global.cash[player.force.name])) }
    gui.cash.income_amount.caption = {"", {"income"}, " ", comma_value(round((global.average_income[player.force.name]/global.average_period)*60*60)),"/m" }    gui.cash.expense_amount.caption = {"", {"expense"}, " ", comma_value(round((global.average_expense[player.force.name]/global.average_period)*60*60)),"/m" }gui.cash.profit_amount.caption = {"", {"profit"}, " ", get_profit(player.force.name),"/m" }
  end
end

function get_profit(name)
  return comma_value(round((global.profit[name]/global.average_period)*60*60))
end

script.on_event(defines.events.on_gui_click, function(event)
  local gui = event.element
  local name = gui.name
  local player = game.players[event.player_index]
  if name == "toggle_price_list" then
    generate_price_table(player)
    return
  end
  if name == "toggle_leaderboard" then
    toggle_leaderboard(player)
    return
  end
end)

function add_toggle_buttons(player)
  local gui = mod_gui.get_button_flow(player)
  gui.add{type = "button", name = "toggle_leaderboard", caption = "Leaderboard"} 
  gui.add
  {
    name = "toggle_price_list",
    type = "button",
    caption = {"toggle-price-list"}
  }
end

function toggle_leaderboard(player)
  local gui = mod_gui.get_frame_flow(player)
  if gui.leaderboard_frame then
    gui.leaderboard_frame.style.visible = not gui.leaderboard_frame.style.visible 
    return
  end
  create_leaderboard(gui)
end

function create_leaderboard(gui)
  local frame = gui.add{type = "frame", name = "leaderboard_frame", caption = "Leaderboard"}
  frame.style.visible = true
  local leaderboard_table = frame.add{type = "table", name = "leaderboard_table", column_count = 2}
  fill_leaderboard_table(leaderboard_table)
end

function fill_leaderboard_table(leaderboard_table)
  leaderboard_table.add{type = "label", caption = "Name"}
  leaderboard_table.add{type = "label", caption = "Profit"}
  for player_name, profit in spairs (global.profit, function(t,a,b) return t[a] > t[b] end) do
    leaderboard_table.add{type = "label", caption = player_name}
    leaderboard_table.add{name = player_name, type = "label", caption = get_profit(player_name).."/m"}
  end
end

function player_buy(player, stack)
  --if not stack.valid then return end
  --if not stack.valid_for_read then return end
  local price = global.price_list[stack.name]
  if not price then return end
  local count = stack.count
  local name = stack.name
  price = price*count
  if global.cash[player.force.name] >= price then 
    global.cash[player.force.name] = global.cash[player.force.name] - price
  else
    player.print({"", "Not enough money for ", game.item_prototypes[name].localised_name})
    local removed = player.remove_item{name = name, count = count}
    if removed ~= count then
      remove_next_tick(player, {name = name, count = count - removed})
    end
  end
end

script.on_event(defines.events.on_player_crafted_item, function(event)
  player_buy(game.players[event.player_index], event.item_stack)
end)

script.on_event(defines.events.on_player_pipette, function(event)
  if not event.used_cheat_mode then return end
  local player = game.players[event.player_index]
  if not player.cursor_stack.valid then return end
  if not player.cursor_stack.valid_for_read then return end
  player_buy(player, player.cursor_stack)
end)

function remove_next_tick(player, stack)
  --game.print("Setup to remove next tick")
  if not global.remove_next_tick then
    global.remove_next_tick = {}
  end
  if not global.remove_next_tick[player.name] then
    global.remove_next_tick[player.name] = {}
  end
  next_tick = game.tick -- Turns out we don't even need to defer for a tick, just move it to some other event call or something
  global.remove_next_tick[player.name][next_tick] = {}
  table.insert(global.remove_next_tick[player.name][next_tick], stack)
end

function remove_next_tick_items()
  if not global.remove_next_tick then return end
  local tick = game.tick
  local listing = global.remove_next_tick
  local all_finished = true
  for k, player in pairs (game.players) do
    --game.print("Checking player "..k)
    local player_list = listing[player.name]
    if player_list then
      if player_list[tick] then
        for k, stack in pairs (player_list[tick]) do
          player.remove_item(stack)
          --game.print("removed - "..stack.name)
        end
        player_list[tick] = nil
      end
      for k, ticks in pairs (player_list) do
        all_finished = false
        break
      end
    end
  end
  if all_finished then
    global.remove_next_tick = nil
  end
end

function comma_value(amount)
  local formatted = amount
  while true do  
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end
  return formatted
end

function check_bounding(limit)
  for k, player in pairs(game.players) do
    if player.position.x > limit then 
      player.teleport{limit, player.position.y}
    end
    if player.position.x < -limit then 
      player.teleport{-limit, player.position.y}
    end
    if player.position.y > limit then 
      player.teleport{player.position.x, limit}
    end
    if player.position.y < -limit then 
      player.teleport{player.position.x, -limit}
    end
  end
end



function save_map_data(distance)

--This exports current map data as an array of entities and tiles

local data = "tiles = \n{\n"
  for X = -distance,distance do
    for Y = -distance, distance do
      local tile = game.surfaces[1].get_tile(X,Y)
      local name = tile.name
      if name ~= "out-of-map" then
      local position = tile.position
      data = data.."  {name = \""..name.."\", position = {"..position.x..","..position.y.."}},\n"
      end
    end
  end
  data = data.."\n}\n\n".."entities = \n{\n"
  for k, entity in pairs (game.surfaces[1].find_entities({{-distance,-distance},{distance,distance}})) do
    local name = entity.name
    local position = entity.position
    local direction = entity.direction
    local force = entity.force
    if entity.name == "express-loader" then
      local loader_type = entity.loader_type
      data = data.."  {name = \""..name.."\", position = {"..position.x..","..position.y.."}, force = \""..force.name.."\", direction = "..direction..", type = \""..loader_type.."\"},\n"
    else
    data = data.."  {name = \""..name.."\", position = {"..position.x..","..position.y.."}, force = \""..force.name.."\", direction = "..direction.."},\n"
    end
  end
  data = data.."\n}"
  game.write_file("tile_data.lua",data)
end



function recreate_map(tiles,entities, offset, force)

--This creates a section of map using an array of tiles and entities
  local offset_tiles = {}
  
  for k, tile in pairs (tiles) do
    offset_tiles[k] = {name = "grass-1", position = {tile.position[1]+offset[1], tile.position[2]+offset[2]}}
  end
  game.surfaces[1].set_tiles(offset_tiles,true)
  for k, entity in pairs (entities) do
    local original_position = {entity.position[1], entity.position[2]}
    entity.position = {entity.position[1]+offset[1], entity.position[2]+offset[2]}
    local v = game.surfaces[1].create_entity(entity)
    entity.position = original_position
    if v then
      v.force = force or "neutral"
      v.destructible = false
      v.minable = false
      v.rotatable = false
      if v.name == "logistic-chest-requester" then
        v.force = force or "neutral"
        table.insert(global.buy_chests, {entity = v, force = force.name})
      end
      if v.name == "logistic-chest-passive-provider" then
        v.force = force or "neutral"
        table.insert(global.sell_chests, {entity = v, force = force.name})
      end
      if v.name =="electric-energy-interface" then
        v.power_production = 0
        v.power_usage = 0
        v.electric_buffer_size = 5*10^9
        v.energy = 2.5*10^9
        v.operable = false
        table.insert(global.accumulators, v)
      end
    end
  end

end

function set_research()

--[=[
Because we don't want research like shooting speed or damage upgrades,
we use this to disable everything and only enabled certain types of research
]=]--

  for i, force in pairs (game.forces) do
    for k, research in pairs (force.technologies) do
      research.enabled = false
    end
  end
  
  for k, research in pairs (game.forces.player.technologies) do
    local unlock_this = false
    for j, effect in pairs (research.effects) do
      if effect.type == "unlock-recipe"
      or effect.type == "inserter-stack-size-bonus"
      or effect.type == "stack-inserter-size-bonus"
      or effect.type == "worker-robot-storage"
      or effect.type == "worker-robot-speed" then
        unlock_this = true
      end
    end
    if unlock_this then
      for i, force in pairs (game.forces) do
        force.technologies[research.name].enabled = true
      end
      unlock_prerequisite(research)
    end
  end
end

function unlock_prerequisite(research)
--This enables the prerequisite technologies for the given research
  for k, prerequisite in pairs (research.prerequisites) do
    for i, force in pairs (game.forces) do
      force.technologies[prerequisite.name].enabled = true
    end
  unlock_prerequisite(prerequisite) --Loops back to enabled the prerequisite of the prerequisite
  end
end


function round(n)
  local v = 0.01*math.floor((n*100)+0.5)
  return v
end

function generate_price_table(player)
  --local comma_value = comma_value
  --local round = round
  local items = game.item_prototypes
  local gui = mod_gui.get_frame_flow(player)
  if gui.price_list then
    gui.price_list.destroy()
    return
  end
  local frame = gui.add{type = "frame", name = "price_list", caption = {"",{"price-list"},""}, direction = "vertical"}
  --frame.style.maximal_height = 600
  --frame.add{type = "label", name = "purchase_amount_5", caption = {"",{"buy-5"},""}}
  --frame.add{type = "checkbox", name = "purchase_amount_5_check", state = false}
  --frame.add{type = "label", name = "purchase_amount_stack", caption = {"",{"buy-stack"},""}}
  --frame.add{type = "checkbox", name = "purchase_amount_stack_check", state = false}
  local scroll_pane = frame.add{type = "scroll-pane", name = "price_scrollpane", vertical_scroll_policy = "auto"}
  scroll_pane.style.maximal_height = 450
  local price_table = scroll_pane.add{type = "table", column_count = 4, name = "price_table"}
  price_table.style.cell_spacing = 0
  price_table.style.vertical_spacing = 2
  --price_table.left_padding = 5

  for name, price in pairs(global.price_list) do
    if price > 0 then
      if items[name] then
        local icon = price_table.add{type = "sprite-button", name = name, sprite = "item/"..name, style = "slot_button", tooltip = items[name].localised_name}
        --icon.style.minimal_width = 40
        --icon.style.minimal_height = 40
        --price_table.add{type = "label", name = name.."name", caption = items[name].localised_name}
        price_table.add{type = "label", name = name.."_price", caption = comma_value(round(global.price_list[name]))}
      end
    end
  end
  --game.print(#price_table.children)
end

function update_price_list()
  local price_list = global.price_list
  for k, player in pairs (game.players) do
    local gui = mod_gui.get_frame_flow(player)
    if gui.price_list then
      local table = gui.price_list.price_scrollpane.price_table
      if table then
        for name, price in pairs (price_list) do
          local entry = table[name.."_price"]
          if entry then
            entry.caption = comma_value(round(global.price_list[name]))
          end
        end
      end
    end
  end
end

function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys 
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

function player_purchase(player,name,amount)
  local price = global.price_list[name]
  local cost = round(price*global.buy_rate*amount)
  if global.cash[player.force.name] > cost and player.can_insert({name = name, count = amount}) then
    global.cash[player.force.name] = global.cash[player.force.name] - cost
    player.insert{name = name, count = amount}
  end
end

function reset_income(index)
  for name, cash in pairs (global.cash) do
    if global.income[name] == nil then 
      global.income[name] = {} 
      for i = 1, global.average_period do
        global.income[name][i] = 0
      end
    end
    if not global.average_income[name] then global.average_income[name] = 0 end
    global.average_income[name] = global.average_income[name] - global.income[name][index]
    global.income[name][index] = 0
  end
end

function reset_expenses(index)
  for name, cash in pairs (global.cash) do
    if not global.expenses[name] then 
      global.expenses[name] = {} 
      for i = 1, global.average_period do
        global.expenses[name][i] = 0
      end
    end
    if not global.average_expense[name] then global.average_expense[name] = 0 end
    global.average_expense[name] = global.average_expense[name] - global.expenses[name][index]
    global.expenses[name][index] = 0
  end
end

function update_income(cost, name)
end

function update_expenses(cost, name)
  global.expenses[name][index] = global.expenses[name][index] + cost
end

function calculate_income_and_expenses(index)
  for name, cash in pairs (global.cash) do
    global.average_expense[name] = global.average_expense[name] + global.expenses[name][index]
    global.average_income[name] = global.average_income[name] + global.income[name][index]
    global.profit[name] = global.average_income[name] - global.average_expense[name]
  end
end

function tend_prices_back()
  if game.tick % (60*60*5) ~= 0 then return end
  local initial_prices = global.initial_price_list
  local price_list = global.price_list
  local abs = math.abs
  for name, initial_price in pairs (initial_prices) do
    local current_price = price_list[name]
    local percentage_difference = (initial_price-current_price)/initial_price
    if abs(percentage_difference) > 0.01 then
      local new_price = current_price*(1+(percentage_difference/10))
      price_list[name] = new_price
    end
  end
  global.price_list = price_list
end

function get_spawn_coordinate(n)
  local root = n^0.5
  local nearest_root = math.floor(root+0.5)
  local upper_root = math.ceil(root)
  local root_difference = math.abs(nearest_root^2 - n)
  if nearest_root == upper_root then
    x = upper_root - root_difference
    y = nearest_root
  else
    x = upper_root
    y = root_difference
  end
  --game.print(x.." - "..y)
  return {x*100, y*100}
end





