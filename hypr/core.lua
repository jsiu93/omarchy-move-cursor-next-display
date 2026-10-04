-- Display geometry: picks the target display and maps the cursor onto it.
-- Plain Lua with no Hyprland dependency, so the tests can run it directly.

local M = {}

-- ---- Geometry --------------------------------------------------------------
function M.logical_rect(mon)
    local w, h = mon.width / (mon.scale or 1), mon.height / (mon.scale or 1)
    if (mon.transform or 0) % 2 == 1 then w, h = h, w end
    return { name = mon.name, x = mon.x, y = mon.y, w = w, h = h }
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function contains(rect, point)
    return point.x >= rect.x and point.x < rect.x + rect.w
        and point.y >= rect.y and point.y < rect.y + rect.h
end

local function distance(rect, point)
    local dx = math.max(rect.x - point.x, 0, point.x - rect.x - rect.w)
    local dy = math.max(rect.y - point.y, 0, point.y - rect.y - rect.h)
    return dx * dx + dy * dy
end

local function map_axis(value, origin, size, target_origin, target_size)
    -- Addressable endpoints map exactly, including across extreme scale ratios.
    local fraction = size > 1 and (value - origin) / (size - 1) or 0
    return target_origin + fraction * math.max(0, target_size - 1)
end

-- ---- Selection and placement -----------------------------------------------
function M.destination(monitors, cursor, direction, placement)
    assert(direction == "next" or direction == "prev", "Unknown direction")
    assert(placement == "relative" or placement == "center", "Unknown placement")
    if #monitors < 2 then return nil end

    local rects = {}
    for i, mon in ipairs(monitors) do
        rects[i] = M.logical_rect(mon)
        rects[i].order = i
    end
    table.sort(rects, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        return a.order < b.order
    end)

    local current, best = 1, math.huge
    for i, rect in ipairs(rects) do
        if contains(rect, cursor) then current = i; break end
        local d = distance(rect, cursor)
        if d < best then current, best = i, d end
    end
    local offset = direction == "next" and 1 or -1
    local source, target = rects[current], rects[(current - 1 + offset) % #rects + 1]
    local x, y = target.x + target.w / 2, target.y + target.h / 2
    if placement == "relative" then
        x = map_axis(cursor.x, source.x, source.w, target.x, target.w)
        y = map_axis(cursor.y, source.y, source.h, target.y, target.h)
    end
    -- Keep subpixel precision; early integer rounding accumulates over a cycle.
    return {
        x = clamp(x, target.x, target.x + math.max(0, target.w - 1)),
        y = clamp(y, target.y, target.y + math.max(0, target.h - 1)),
    }
end

return M
