ingredient_exponent = 1.07 --The exponent for increase in value for each additional ingredient forumula exponent^#ingredients
base_multiplier = 1.1 --The value increase for every additional production tier or something
base_price = 3.14 --Used if a item has no recipe. Shouldn't really be used
raw_resource_price = 2.5 --If a raw resource isn't given a price, it uses this price

function generate_price_list()
  log("Price list generation Begun")
  price_list = {
    ["iron-ore"] = 3.1,
    ["copper-ore"] = 3.6,
    ["coal"] = 2.1,
    ["stone"] = 4.1,
    ["crude-oil"] = 1.5,
    ["water"] = 0,
    ["raw-wood"] = 3.2,
    ["raw-fish"] = 100,
    ["energy"] = 1,
    ["uranium-ore"] = 6.2
  }
  local resource_list = get_raw_resources()
  for name, k in pairs (resource_list) do
    if not price_list[name] then
      price_list[name] = raw_resource_price
    end
  end
  local product_list = get_product_list()
  local current_loop = {}
  local ln = math.log
  --game.write_file("pricelist-log.txt", "Fuckin balls")
  get_price_recursive = function(name)
    local price = price_list[name]
    if price then return price else price = 0 end
    if current_loop[name] then return 0 end
    current_loop[name] = true
    local entry = product_list[name]
    if not entry then return 0 end
    local recipe_cost
    for k, recipe in pairs (entry) do
      local this_recipe_cost = 0
      for ingredient_name, cost in pairs (recipe) do
        if ingredient_name ~= "energy" then
          local addition = get_price_recursive(ingredient_name)
          if addition and addition >= 0 then
            this_recipe_cost = this_recipe_cost + (addition*cost)
          else
            this_recipe_cost = 0
            break
          end
        end
      end
      if this_recipe_cost > 0 then
        this_recipe_cost = this_recipe_cost+((ln(recipe.energy+0.5)*this_recipe_cost^0.5))
        this_recipe_cost = this_recipe_cost*(ingredient_exponent^(#recipe-2))
        if recipe_cost then
          recipe_cost = math.min(recipe_cost, this_recipe_cost)
        else
          recipe_cost = this_recipe_cost
        end
      end
    end
    if recipe_cost then
      price = price + recipe_cost
    end
    if price > 0 then
      price = price ^ base_multiplier
    else
      price = nil
    end
    price_list[name] = price
    return price
  end
  local items = game.item_prototypes
  for name, item in pairs (items) do
    current_loop = {}
    get_price_recursive(name)
  end
  --price_list["space-science-pack"] = price_list["rocket-part"]/9.75
  --game.write_file("new_price_list_export.lua", serpent.block(price_list))
  log("Price list generation ended")
  return price_list
end

function get_raw_resources()
  local raw_resources = {}
  local entities = game.entity_prototypes
  for name, entity_prototype in pairs (entities) do
    if entity_prototype.resource_category then
      if entity_prototype.mineable_properties then
        for k, product in pairs (entity_prototype.mineable_properties.products) do
          raw_resources[product.name] = true
        end
      end
    end
  end
  --game.write_file("new_price_list_export.lua", serpent.block(raw_resources))
  return raw_resources
end

function get_product_list()
  local product_list = {}
  local recipes = game.recipe_prototypes
  for recipe_name, recipe_prototype in pairs (recipes) do
    if not recipe_prototype.hidden or recipe_name == "rocket-part" then
      local ingredients = recipe_prototype.ingredients
      local products = recipe_prototype.products
      for k, product in pairs (products) do
        if not product_list[product.name] then
          product_list[product.name] = {}
        end
        local recipe_ingredients = {}
        for j, ingredient in pairs (ingredients) do
          local product_amount = product.amount or  product.probability * ((product.amount_min + product.amount_max) / 2) or 1
          recipe_ingredients[ingredient.name] = ((ingredient.amount)/#products) / product_amount
        end
        recipe_ingredients.energy = recipe_prototype.energy
        table.insert(product_list[product.name], recipe_ingredients)
      end
    end
  end
  --game.write_file("product_list_export.lua", serpent.block(product_list))
  return product_list
end
