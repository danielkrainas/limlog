-- Static Limbus data. Chest ids, floor landings and floor data item ids come from superwarp's Limbus map.

local limbus = {}

limbus.max_chests = 5 -- chests per zone per week, not counting Unique Data

limbus.zones = {
    [37] = { name = 'Temenos', towers = { 'N', 'W', 'E', 'C' } },
    [38] = { name = 'Apollyon', towers = { 'NW', 'SW', 'NE', 'SE' } },
}

-- Tower names are unique across both zones, so a tower alone identifies a chest.
limbus.chests = {
    [16929362] = { zone = 37, tower = 'N', floor = 4 },
    [16929363] = { zone = 37, tower = 'W', floor = 4 },
    [16929364] = { zone = 37, tower = 'E', floor = 4 },
    [16929365] = { zone = 37, tower = 'C', floor = 3 },
    [16933563] = { zone = 38, tower = 'NW', floor = 5 },
    [16933564] = { zone = 38, tower = 'SW', floor = 4 },
    [16933565] = { zone = 38, tower = 'NE', floor = 5 },
    [16933566] = { zone = 38, tower = 'SE', floor = 4 },
}

-- Mob index (the low 12 bits of the NPC id) of each zone's special code location.
limbus.code_locations = {
    [37] = 0x1F5,
    [38] = 0x289,
}

-- Where a floor warp puts you. Windower axes: x and y are horizontal, z is height. No two landings in a zone
-- share a horizontal position, so height is left out.
limbus.landings = {
    [37] = {
        { name = 'Entrance', x = 580, y = 86, entrance = true },
        { name = 'N1', x = -140, y = 376 },
        { name = 'N2', x = -260, y = 376 },
        { name = 'N3', x = -460, y = 376 },
        { name = 'N4', x = -580, y = 376 },
        { name = 'W1', x = -140, y = 96 },
        { name = 'W2', x = -260, y = 96 },
        { name = 'W3', x = -460, y = 96 },
        { name = 'W4', x = -580, y = 96 },
        { name = 'E1', x = -140, y = -184 },
        { name = 'E2', x = -260, y = -184 },
        { name = 'E3', x = -460, y = -184 },
        { name = 'E4', x = -580, y = -184 },
        { name = 'C1', x = 260, y = -504 },
        { name = 'C2', x = 20, y = -544 },
        { name = 'C3', x = -296, y = -500 },
        { name = 'CN', x = -540, y = -584 },
    },
    [38] = {
        { name = 'Entrance', x = -608, y = -600, entrance = true },
        { name = 'Entrance', x = 608, y = -600, entrance = true },
        { name = 'NW1', x = -440, y = -88 },
        { name = 'NW2', x = -534, y = 171 },
        { name = 'NW3', x = -294, y = 171 },
        { name = 'NW4', x = -628, y = 497 },
        { name = 'NW5', x = -388, y = 498 },
        { name = 'SW1', x = -468, y = -625 },
        { name = 'SW2', x = -576, y = -428 },
        { name = 'SW3', x = -428, y = -385 },
        { name = 'SW4', x = -176, y = -628 },
        { name = 'NE1', x = 440, y = -88 },
        { name = 'NE2', x = 534, y = 171 },
        { name = 'NE3', x = 294, y = 171 },
        { name = 'NE4', x = 628, y = 497 },
        { name = 'NE5', x = 388, y = 498 },
        { name = 'SE1', x = 468, y = -625 },
        { name = 'SE2', x = 576, y = -428 },
        { name = 'SE3', x = 428, y = -385 },
        { name = 'SE4', x = 176, y = -628 },
        { name = 'CN', x = 0, y = 196 },
    },
}

-- Floor data and Codes, which sit in the temporary bag until a chest consumes them.
function limbus.is_chest_key(id)
    return (id >= 9956 and id <= 9998) or id == 10044 or id == 10045
end

-- Returns 'matter', 'material', 'shard', 'crafting', or nil for anything that isn't a known Limbus reward.
function limbus.reward_category(id)
    if id == 9999 or id == 10000 then
        return 'matter'
    elseif id == 10046 or id == 10047 then
        return 'material'
    elseif id >= 10006 and id <= 10010 then
        return 'shard'
    elseif (id >= 10001 and id <= 10005) or (id >= 10011 and id <= 10023) or (id >= 10028 and id <= 10032)
        or (id >= 10036 and id <= 10039) then
        return 'crafting' -- jewels, synthesis materials, Alabaster/Murky parts and cores
    end
end

return limbus
