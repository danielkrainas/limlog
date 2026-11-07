_addon.name = 'limlog'
_addon.author = 'danny'
_addon.version = '1.0.0'
_addon.commands = { 'limlog', 'lim' }

local config = require('config')
local texts = require('texts')
local res = require('resources')
local limbus = require('limbus')

local defaults = {
    show_floor_time = true,
    min_floor_seconds = 15, -- shorter stays are passing through a floor, not clearing it
    display = {
        pos = { x = 300, y = 120 },
        bg = { alpha = 170, red = 0, green = 0, blue = 0 },
        text = {
            font = 'Consolas',
            size = 10,
            stroke = { alpha = 255, red = 0, green = 0, blue = 0, width = 1 },
        },
        flags = { draggable = true },
    },
}

local settings = config.load(defaults)
local box = texts.new('', settings.display, settings)

local WEEK = 7 * 24 * 60 * 60
local JST = 9 * 60 * 60
local TALLY_ANCHOR = 3 * 24 * 60 * 60 + 15 * 60 * 60 -- 1970-01-05 00:00 JST, a Monday: the Conquest tally

local TICK_SECONDS = 0.25
local WARP_DISTANCE = 40    -- yalms moved in one tick that can only be a warp
local LANDING_RADIUS = 20   -- how far from a known landing we can still say which floor we're on
local TOUCH_TIMEOUT = 30    -- seconds to wait for a touched chest to actually open
local REWARD_DELAY = 5      -- seconds after opening for rewards to land
local UNITS_DELAY = 2       -- seconds to wait for the final units reply

local CSV_HEADER = 'date_time,week_of,character,zone,tower,floor,chest_no,units_gained,units_total,'
    .. 'matter,material,shards,crafting,source'
local CSV_COLUMNS = 14

local ON = '\\cs(100,255,100)'
local OFF = '\\cs(110,110,110)'
local END = '\\cr'

local character = nil
local week = nil        -- this week's chests: { key, opened[tower] = times opened, count[zone] }
local chest = nil       -- the chest being opened, until its outcome is known
local position = nil    -- player x/y at the last tick
local floor = nil       -- the floor we're on: { name, arrived }
local last_clear = nil  -- { name, seconds }
local next_tick = 0

local function say(msg)
    windower.add_to_chat(207, '[limlog] ' .. msg)
end

local function current_zone()
    local info = windower.ffxi.get_info()
    return info.logged_in and info.zone or nil
end

local function u16(data, offset)
    local a, b = data:byte(offset + 1, offset + 2)
    return a + b * 0x100
end

local function u32(data, offset)
    local a, b, c, d = data:byte(offset + 1, offset + 4)
    return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

local function commas(n)
    local s = tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (s:gsub('^,', ''))
end

local function clock_text(seconds)
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

-- The Monday (JST) that began the week containing `now`, which also keys that week's CSV rows.
local function week_key(now)
    local start = now - (now - TALLY_ANCHOR) % WEEK
    return os.date('!%Y-%m-%d', start + JST)
end

-- Status ------------------------------------------------------------------------------------------

local function find_chest(tower)
    for _, info in pairs(limbus.chests) do
        if info.tower == tower then
            return info
        end
    end
end

local function status_path()
    return windower.addon_path .. 'data/' .. character .. '_status.json'
end

-- Status only ever covers the current week, so a file from an earlier week reads as empty.
local function load_week()
    week = { key = week_key(os.time()), opened = {}, count = { [37] = 0, [38] = 0 } }
    if not character then
        return
    end
    local file = io.open(status_path(), 'r')
    if not file then
        return
    end
    local content = file:read('*a')
    file:close()

    local key = content:match('"week"%s*:%s*"([^"]*)"')
    local opened = content:match('"opened"%s*:%s*(%b{})')
    if not key or not opened then
        say('Could not read ' .. status_path() .. ', so this week\'s status starts empty.')
        return
    end
    if key ~= week.key then
        return
    end
    for tower, count in opened:gmatch('"(%w+)"%s*:%s*(%d+)') do
        local info = find_chest(tower)
        if info then
            week.opened[tower] = tonumber(count)
            week.count[info.zone] = week.count[info.zone] + tonumber(count)
        end
    end
end

-- Written to a temp file first, so a crash mid-write can't leave a half-written status behind.
local function save_week()
    local towers = {}
    for _, id in ipairs({ 37, 38 }) do
        for _, tower in ipairs(limbus.zones[id].towers) do
            if week.opened[tower] then
                towers[#towers + 1] = ('"%s":%d'):format(tower, week.opened[tower])
            end
        end
    end

    local path = status_path()
    local temp = path .. '.tmp'
    local file, err = io.open(temp, 'w')
    if not file then
        say('Could not write ' .. temp .. ': ' .. tostring(err))
        return
    end
    file:write(('{"week":"%s","opened":{%s}}\n'):format(week.key, table.concat(towers, ',')))
    file:close()

    os.remove(path) -- Windows can't rename onto an existing file
    local renamed, rename_err = os.rename(temp, path)
    if not renamed then
        say('Could not write ' .. path .. ': ' .. tostring(rename_err))
    end
end

-- CSV ---------------------------------------------------------------------------------------------

local function csv_path()
    return windower.addon_path .. 'data/' .. character .. '_chests.csv'
end

local function csv_field(value)
    local s = tostring(value == nil and '' or value)
    if s:find('[,"\n]') then
        return '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

-- The CSV is an append-only log: nothing here reads it back or rewrites it.
local function append_row(row)
    local path = csv_path()
    local existing = io.open(path, 'r')
    if existing then
        existing:close()
    end
    local file, err = io.open(path, 'a')
    if not file then
        say('Could not write ' .. path .. ': ' .. tostring(err))
        return
    end
    if not existing then
        file:write(CSV_HEADER, '\n')
    end
    local fields = {}
    for i = 1, CSV_COLUMNS do
        fields[i] = csv_field(row[i])
    end
    file:write(table.concat(fields, ','), '\n')
    file:close()
end

-- Display -----------------------------------------------------------------------------------------

local function refresh()
    local id = current_zone()
    local zone = limbus.zones[id]
    if not zone or not week then
        box:hide()
        return
    end

    local towers = {}
    for i, tower in ipairs(zone.towers) do
        towers[i] = (week.opened[tower] and ON or OFF) .. tower .. END
    end
    local text = ('%s  %s  %d/%d'):format(zone.name, table.concat(towers, ' '), week.count[id], limbus.max_chests)

    if settings.show_floor_time then
        local clear = last_clear and (last_clear.name .. ' ' .. clock_text(last_clear.seconds)) or '--'
        text = text .. '\nLast clear: ' .. clear
    end

    box:text(text)
    box:show()
end

local function record(info, row)
    week.opened[info.tower] = (week.opened[info.tower] or 0) + 1
    week.count[info.zone] = week.count[info.zone] + 1
    save_week()
    append_row(row)
    refresh()
end

-- Chests ------------------------------------------------------------------------------------------

local function bag_counts(bag)
    local counts = {}
    for _, item in ipairs(windower.ffxi.get_items(bag)) do
        if item.id ~= 0 then
            counts[item.id] = (counts[item.id] or 0) + item.count
        end
    end
    return counts
end

local function chest_key_count()
    local total = 0
    for id, count in pairs(bag_counts(3)) do
        if limbus.is_chest_key(id) then
            total = total + count
        end
    end
    return total
end

-- Asks the server for Currencies 2. The client ignores the reply when its menu is closed.
local function request_units()
    windower.packets.inject_outgoing(0x115, string.char(0x15, 0x03, 0x00, 0x00))
end

local function touch_chest(id)
    if chest and chest.opened_at then
        return
    end
    chest = {
        id = id,
        info = limbus.chests[id],
        touched_at = os.time(),
        items = bag_counts(0),
        keys = chest_key_count(),
        pool = {},
    }
    request_units()
end

local function open_chest(id)
    if not chest or chest.id ~= id then
        touch_chest(id)
    end
    chest.opened_at = os.time()
end

local function item_name(id)
    local item = res.items[id]
    return item and item.en or ('Item ' .. id)
end

-- Items sort by name per category: { matter = 'Murky Matter', shard = 'Shard of Hope x2', crafting = 'Hydro Oil' }.
local function sort_rewards(gained)
    local lists = { matter = {}, material = {}, shard = {}, crafting = {} }
    local found = false
    for id, count in pairs(gained) do
        local category = limbus.reward_category(id) or (chest.pool[id] and 'crafting')
        if category then
            local list = lists[category]
            list[#list + 1] = item_name(id) .. (count > 1 and ' x' .. count or '')
            found = true
        end
    end
    for category, list in pairs(lists) do
        table.sort(list)
        lists[category] = table.concat(list, '; ')
    end
    return lists, found
end

-- Rewards may arrive in the inventory, the treasure pool, or both once a pool item is lotted.
local function gained_items()
    local gained = {}
    for id, count in pairs(bag_counts(0)) do
        local diff = count - (chest.items[id] or 0)
        if diff > 0 then
            gained[id] = diff
        end
    end
    for id, count in pairs(chest.pool) do
        gained[id] = math.max(gained[id] or 0, count)
    end
    return gained
end

local function finish_chest()
    local info = chest.info
    local units = chest.units_gained
    local rewards, has_rewards = sort_rewards(gained_items())

    -- A cancelled menu looks like an open until now: nothing changed, so nothing was opened.
    if not (has_rewards or chest_key_count() < chest.keys or (units and units > 0)) then
        say(('%s chest did not open, so it was not recorded. If it did, use //limlog mark %s.'):format(
            info.tower, info.tower))
        chest = nil
        return
    end

    local number = week.count[info.zone] + 1
    record(info, {
        os.date('%Y-%m-%d %H:%M:%S'), week.key, character, limbus.zones[info.zone].name, info.tower, info.floor,
        number, units, chest.units_total, rewards.matter, rewards.material, rewards.shard, rewards.crafting, 'auto',
    })

    local parts = {}
    if units then
        parts[#parts + 1] = ('+%s units (%s total)'):format(commas(units), commas(chest.units_total))
    end
    for _, category in ipairs({ 'matter', 'material', 'shard', 'crafting' }) do
        if rewards[category] ~= '' then
            parts[#parts + 1] = rewards[category]
        end
    end
    say(('%s%d chest %d/%d: %s'):format(info.tower, info.floor, number, limbus.max_chests,
        #parts > 0 and table.concat(parts, ', ') or 'nothing detected'))
    chest = nil
end

local function update_chest()
    if not chest then
        return
    end
    local now = os.time()
    if not chest.opened_at then
        if now - chest.touched_at >= TOUCH_TIMEOUT then
            chest = nil
        end
    elseif not chest.units_requested_at then
        if now - chest.opened_at >= REWARD_DELAY then
            chest.units_requested_at = now
            request_units()
        end
    elseif now - chest.units_requested_at >= UNITS_DELAY then
        finish_chest()
    end
end

local function receive_units(data)
    if not chest or #data < 0xA0 then
        return
    end
    local total = u32(data, chest.info.zone == 37 and 0x98 or 0x9C)
    if chest.units_requested_at then
        chest.units_total = total
        chest.units_gained = chest.units_before and total - chest.units_before or nil
    elseif not chest.units_before then
        chest.units_before = total
    end
end

-- Floors ------------------------------------------------------------------------------------------

local function landing_at(zone, x, y)
    for _, landing in ipairs(limbus.landings[zone]) do
        local dx, dy = landing.x - x, landing.y - y
        if dx * dx + dy * dy <= LANDING_RADIUS * LANDING_RADIUS then
            return landing
        end
    end
end

local function warped(zone, x, y)
    local landing = landing_at(zone, x, y)
    if floor and landing and landing.name == floor.name then
        return
    end

    local now = os.time()
    if floor and now - floor.arrived >= settings.min_floor_seconds then
        last_clear = { name = floor.name, seconds = now - floor.arrived }
        refresh()
    end

    floor = landing and not landing.entrance and { name = landing.name, arrived = now } or nil
end

local function update_position(zone)
    local me = windower.ffxi.get_mob_by_target('me')
    if not me then
        return
    end
    local last = position
    position = { x = me.x, y = me.y }
    if last then
        local dx, dy = me.x - last.x, me.y - last.y
        if dx * dx + dy * dy >= WARP_DISTANCE * WARP_DISTANCE then
            warped(zone, me.x, me.y)
        end
    end
end

-- Lifecycle ---------------------------------------------------------------------------------------

local function start(name)
    character = name
    if character then
        windower.create_dir(windower.addon_path .. 'data')
    end
    load_week()
    refresh()
end

windower.register_event('load', function()
    local player = windower.ffxi.get_player()
    start(player and player.name)
end)

windower.register_event('login', start)

windower.register_event('logout', function()
    character, chest, position, floor = nil, nil, nil, nil
    box:hide()
end)

windower.register_event('zone change', function()
    if chest and chest.opened_at then
        finish_chest()
    end
    chest, position, floor = nil, nil, nil
    refresh()
end)

windower.register_event('prerender', function()
    local now = os.clock()
    if now < next_tick then
        return
    end
    next_tick = now + TICK_SECONDS

    -- Login and zoning don't always give a usable zone at event time, so visibility is kept in sync here.
    local zone = current_zone()
    local in_limbus = character ~= nil and limbus.zones[zone] ~= nil
    if box:visible() ~= in_limbus then
        refresh()
    end
    if not in_limbus then
        return
    end
    if week.key ~= week_key(os.time()) then
        load_week()
        refresh()
    end
    update_position(zone)
    update_chest()
end)

windower.register_event('outgoing chunk', function(id, data)
    if id == 0x01A then
        local target = u32(data, 0x04)
        if limbus.chests[target] then
            touch_chest(target)
        end
    elseif id == 0x05B then
        -- Superwarp's filter: the automated reply is the open, and the rest are repeats and interrupts.
        local target = u32(data, 0x04)
        if limbus.chests[target] and data:byte(0x0E + 1) ~= 0 then
            open_chest(target)
        end
    end
end)

windower.register_event('incoming chunk', function(id, data)
    if id == 0x118 then
        receive_units(data)
    elseif id == 0x0D2 and chest and u32(data, 0x08) == chest.id and data:byte(0x15 + 1) == 0 then
        local item = u16(data, 0x10)
        chest.pool[item] = (chest.pool[item] or 0) + 1
    end
end)

-- Commands ----------------------------------------------------------------------------------------

local function print_status()
    for _, id in ipairs({ 37, 38 }) do
        local zone = limbus.zones[id]
        local opened = {}
        for _, tower in ipairs(zone.towers) do
            if week.opened[tower] then
                opened[#opened + 1] = tower
            end
        end
        say(('%s %d/%d: %s'):format(zone.name, week.count[id], limbus.max_chests,
            #opened > 0 and table.concat(opened, ' ') or 'none'))
    end
end

local function mark(tower)
    local info = find_chest(tower)
    if not info then
        say('Unknown tower. Use N, W, E, C, NW, SW, NE or SE.')
        return
    end
    local number = week.count[info.zone] + 1
    record(info, {
        os.date('%Y-%m-%d %H:%M:%S'), week.key, character, limbus.zones[info.zone].name, info.tower, info.floor,
        number, nil, nil, '', '', '', '', 'manual',
    })
    say(('%s marked as opened (%d/%d).'):format(tower, number, limbus.max_chests))
end

local function unmark(tower)
    local info = find_chest(tower)
    if not info then
        say('Unknown tower. Use N, W, E, C, NW, SW, NE or SE.')
    elseif not week.opened[tower] then
        say('No ' .. tower .. ' chest recorded this week.')
    else
        week.opened[tower] = week.opened[tower] > 1 and week.opened[tower] - 1 or nil
        week.count[info.zone] = week.count[info.zone] - 1
        save_week()
        refresh()
        say('Removed one ' .. tower .. ' chest from this week\'s status. The CSV is unchanged.')
    end
end

local function print_help()
    say('//limlog status - this week\'s chests in both zones')
    say('//limlog mark <tower> - record a chest the addon missed')
    say('//limlog unmark <tower> - take one chest off this week\'s status')
    say('//limlog floortime - show or hide the last floor clear time')
    say('//limlog csv - show where the CSV is saved')
end

windower.register_event('addon command', function(command, arg)
    command = command and command:lower() or 'help'
    if command == 'floortime' then
        settings.show_floor_time = not settings.show_floor_time
        config.save(settings)
        refresh()
        say('Floor clear time ' .. (settings.show_floor_time and 'shown.' or 'hidden.'))
    elseif command == 'status' or command == 'mark' or command == 'unmark' or command == 'csv' then
        if not character then
            say('Log in first.')
        elseif command == 'status' then
            print_status()
        elseif command == 'csv' then
            say(csv_path())
        elseif command == 'mark' then
            mark((arg or ''):upper())
        else
            unmark((arg or ''):upper())
        end
    else
        print_help()
    end
end)
