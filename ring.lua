-- A ring drawn on the ground around a world position, ported from recroom's target ring.
--
-- Prims are flat screen squares that can't rotate, so the ring is a set of dots placed around a circle in world
-- space, each projected to the screen on its own. That gives perspective and tilt for free.
--
-- The projection settings are the ones recroom measured in game with //rr solve: row vectors (v * M), get_camera's
-- `matrix` used as world -> view directly, and Windower's (x, y, z = height) passed to the engine as (x, z, y).
--
-- The Lua API has no depth buffer, so the ring shows through walls. The distance cap, distance fade and height
-- check below keep that from being misleading.

local ring = {}

local SEGMENTS = 72     -- enough dots to overlap into a solid line
local DOT_SIZE = 8      -- pixels at about 8 yalms from the camera
local MIN_DOT_SIZE = 4  -- pixels; keeps the ring readable from far away
local MAX_DISTANCE = 50 -- yalms; hidden beyond this
local FADE_START = 30   -- yalms; fades out from here to MAX_DISTANCE
local MAX_HEIGHT = 20   -- yalms above or below you before the spot counts as another floor

local pool = 0

local function name(i)
    return ('limlog_ring_%03d'):format(i)
end

-- DirectX row vectors: v' = v * M, with m[row][column].
local function mul4(x, y, z, w, m)
    return x * m[1][1] + y * m[2][1] + z * m[3][1] + w * m[4][1],
        x * m[1][2] + y * m[2][2] + z * m[3][2] + w * m[4][2],
        x * m[1][3] + y * m[2][3] + z * m[3][3] + w * m[4][3],
        x * m[1][4] + y * m[2][4] + z * m[3][4] + w * m[4][4]
end

local function camera()
    local get_camera = windower.get_camera or (windower.ffxi and windower.ffxi.get_camera)
    if not get_camera then
        return nil
    end
    local ok, cam = pcall(get_camera)
    if not ok or type(cam) ~= 'table' or cam.valid == false
        or type(cam.matrix) ~= 'table' or type(cam.projection_matrix) ~= 'table' then
        return nil
    end
    return cam
end

-- Prims are placed in Windower's UI coordinates, which can differ from the game's render resolution.
local function viewport()
    local s = windower.get_windower_settings()
    return s.ui_x_res or s.x_res, s.ui_y_res or s.y_res
end

-- Returns screen x, y and depth, or nil for a point behind the camera.
local function project(cam, x, y, z, vw, vh)
    local vx, vy, vz, vwc = mul4(x, z, y, 1, cam.matrix)
    local cx, cy, _, cw = mul4(vx, vy, vz, vwc, cam.projection_matrix)
    if cw <= 0.0001 then
        return nil
    end
    return (cx / cw * 0.5 + 0.5) * vw, (0.5 - cy / cw * 0.5) * vh, cw
end

function ring.hide()
    for i = 1, pool do
        windower.prim.set_visibility(name(i), false)
    end
end

function ring.destroy()
    for i = 1, pool do
        windower.prim.delete(name(i))
    end
    pool = 0
end

local function grow()
    for i = pool + 1, SEGMENTS do
        windower.prim.create(name(i))
        windower.prim.set_fit_to_texture(name(i), false)
        windower.prim.set_visibility(name(i), false)
    end
    pool = math.max(pool, SEGMENTS)
end

-- Draws the ring around `spot` as seen from `me`, both mob tables. Returns true if anything was drawn.
function ring.draw(spot, me, radius, color)
    if not (spot and spot.x and spot.y and spot.z and me and me.x and me.y and me.z) then
        ring.hide()
        return false
    end

    local dx, dy = spot.x - me.x, spot.y - me.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > MAX_DISTANCE or math.abs(spot.z - me.z) > MAX_HEIGHT then
        ring.hide()
        return false
    end

    local cam = camera()
    if not cam then
        ring.hide()
        return false
    end

    local fade = distance <= FADE_START and 1 or 1 - (distance - FADE_START) / (MAX_DISTANCE - FADE_START)
    local alpha = math.floor(color.alpha * fade)
    if alpha <= 0 then
        ring.hide()
        return false
    end

    grow()
    local vw, vh = viewport()
    local step = 2 * math.pi / SEGMENTS
    local drawn = false

    for i = 1, SEGMENTS do
        local angle = step * i
        local sx, sy, depth = project(cam, spot.x + radius * math.cos(angle), spot.y + radius * math.sin(angle),
            spot.z, vw, vh)
        if sx then
            -- Shrink with depth so the ring keeps a steady thickness instead of ballooning up close.
            local size = math.max(MIN_DOT_SIZE, math.min(DOT_SIZE * 8 / depth, DOT_SIZE * 3))
            windower.prim.set_position(name(i), sx - size / 2, sy - size / 2)
            windower.prim.set_size(name(i), size, size)
            windower.prim.set_color(name(i), alpha, color.red, color.green, color.blue)
            windower.prim.set_visibility(name(i), true)
            drawn = true
        else
            windower.prim.set_visibility(name(i), false)
        end
    end

    return drawn
end

return ring
