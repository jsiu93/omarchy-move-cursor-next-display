-- Adapter tests for hypr/bind.lua against a stubbed Hyprland API that replays
-- key press and release ordering. Run from the repository root:
--   lua test/bind_test.lua

local cursor, listener, pending, bindings
local hide_on_key, hidden, moves, removed
local monitors = {
    { name = "a", x = 0, y = 0, width = 100, height = 100, scale = 1, transform = 0 },
    { name = "b", x = 100, y = 0, width = 100, height = 100, scale = 1, transform = 0 },
}

-- ---- Compositor boundary ---------------------------------------------------
hl = {
    get_monitors = function() return monitors end,
    get_cursor_pos = function() return { x = cursor.x, y = cursor.y } end,
    get_config = function(key)
        assert(key == "cursor.hide_on_key_press")
        return hide_on_key
    end,
    config = function() error("The adapter must leave configuration untouched") end,
    dispatch = function(action) action() end,
    dsp = { cursor = { move = function(point)
        return function()
            cursor = { x = point.x, y = point.y }
            hidden = false
            moves = moves + 1
        end
    end } },
    bind = function(key, action) bindings[key] = action end,
    unbind = function(key) bindings[key] = nil end,
    on = function(event, callback)
        assert(event == "input.keyboard.key" and listener == nil)
        listener = callback
        return { remove = function() listener = nil; removed = removed + 1 end }
    end,
    timer = function(callback, options)
        assert(options.type == "oneshot" and options.timeout == 1)
        pending[#pending + 1] = callback
    end,
    notification = { create = function() end },
}

local function key(state)
    if listener then listener(49, 1, state) end
    -- Model the renderer running after the Lua listener, including on release.
    hidden = hide_on_key
end
local function flush()
    local callbacks = pending
    pending = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local count = 0
local function test(name, body)
    if __move_cursor_display then __move_cursor_display.clear() end
    cursor, pending, bindings = { x = 20, y = 30 }, {}, {}
    hide_on_key, hidden, moves, removed = true, false, 0, 0
    local adapter = dofile("hypr/bind.lua")
    adapter.apply({ next = "ALT + grave" })
    body(adapter)
    count = count + 1
    print("ok " .. count .. " - " .. name)
end

-- ---- Visibility and cancellation -------------------------------------------
for _, action in ipairs({ "next", "prev", "next_center", "prev_center" }) do
    test(action .. " stays visible after key and modifier release", function(m)
        key(1); m[action]()
        local x, y = cursor.x, cursor.y
        assert(not hidden)
        key(0); assert(hidden); flush()
        assert(not hidden, "Shortcut release hid the cursor")
        key(0); flush()
        assert(not hidden and cursor.x == x and cursor.y == y)
        assert(hide_on_key == true)
    end)
end
test("ordinary typing cancels pending reveal", function(m)
    key(1); m.next(); key(0); key(1); flush()
    assert(hidden and moves == 1)
    key(0); flush(); assert(hidden and moves == 1)
end)
test("false setting produces no deferred movement or config writes", function(m)
    hide_on_key = false
    key(1); m.next(); key(0); flush()
    assert(not hidden and moves == 1 and hide_on_key == false)
end)
test("runtime setting change to false skips an already queued refresh", function(m)
    key(1); m.next(); key(0)
    hide_on_key = false; flush()
    assert(moves == 1 and hide_on_key == false)
end)
test("refresh uses the latest mouse position", function(m)
    key(1); m.next(); key(0)
    cursor = { x = 150, y = 70 }; flush()
    assert(cursor.x == 150 and cursor.y == 70 and not hidden)
end)
test("clear removes listener and cancels queued refresh", function(m)
    key(1); m.next(); key(0); m.clear(); flush()
    assert(listener == nil and removed == 1 and moves == 1 and next(bindings) == nil)
end)
test("reapply cancels callbacks from the previous registration", function(m)
    key(1); m.next(); key(0)
    m.apply({ next = "ALT + F8" }); flush()
    assert(moves == 1 and bindings["ALT + grave"] == nil and bindings["ALT + F8"])
    key(1); m.next(); key(0); flush(); assert(not hidden)
end)
test("empty keymap leaves no keyboard listener", function(m)
    m.apply({}); assert(listener == nil and next(bindings) == nil)
end)
print(string.format("PASS: %d adapter tests", count))
