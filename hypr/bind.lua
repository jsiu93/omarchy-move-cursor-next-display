-- Hyprland adapter: registers the shortcut actions and keeps the cursor visible
-- after the shortcut is released. core.lua is loaded once and captured, so key
-- presses read no files.

local path = debug.getinfo(1, "S").source:sub(2)
local core = dofile(assert(path:match("^(.*[/])"), "Expected a file path") .. "core.lua")
local previous = rawget(_G, "__move_cursor_display")
if previous then previous.clear() end
local M, registered = {}, {}
local warned_single = false
local release_listener
local reveal_after_release = false
local generation = 0

-- ---- Shortcut release visibility -------------------------------------------
local function on_key(_, _, state)
    if state ~= 0 then
        -- Ordinary typing resumes the user's hide-on-key behavior.
        generation = generation + 1
        reveal_after_release = false
    elseif reveal_after_release then
        local current = generation
        -- The renderer also hides on release. Run after every event listener.
        hl.timer(function()
            if current == generation and reveal_after_release
                and hl.get_config("cursor.hide_on_key_press") then
                -- Refresh at the current position, including any intervening mouse motion.
                hl.dispatch(hl.dsp.cursor.move(hl.get_cursor_pos()))
            end
        end, { timeout = 1, type = "oneshot" })
    end
end

-- ---- Runtime actions -------------------------------------------------------
local function move(direction, placement)
    local monitors = {}
    for _, mon in ipairs(hl.get_monitors()) do
        monitors[#monitors + 1] = {
            name = mon.name, x = mon.x, y = mon.y,
            width = mon.width, height = mon.height,
            scale = mon.scale, transform = mon.transform,
        }
    end
    local point = core.destination(monitors, hl.get_cursor_pos(), direction, placement)
    if not point then
        if not warned_single then
            hl.notification.create({ text = "Move cursor: connect another display.", timeout = 3000, icon = "info" })
            warned_single = true
        end
        return
    end
    warned_single = false
    generation = generation + 1
    reveal_after_release = hl.get_config("cursor.hide_on_key_press")
    hl.dispatch(hl.dsp.cursor.move({ x = point.x, y = point.y }))
end

local actions = {
    { "next", "next", "relative", "next display" },
    { "prev", "prev", "relative", "previous display" },
    { "next_center", "next", "center", "next display center" },
    { "prev_center", "prev", "center", "previous display center" },
}
for _, action in ipairs(actions) do
    M[action[1]] = function() move(action[2], action[3]) end
end

-- ---- Binding ownership -----------------------------------------------------
function M.clear()
    generation = generation + 1
    reveal_after_release = false
    if release_listener then release_listener:remove(); release_listener = nil end
    for _, key in ipairs(registered) do hl.unbind(key) end
    registered = {}
end

function M.apply(keymap)
    M.clear()
    for _, action in ipairs(actions) do
        local key = keymap[action[1]]
        if key then
            hl.bind(key, M[action[1]], { description = "Move cursor: " .. action[4] })
            registered[#registered + 1] = key
        end
    end
    if #registered > 0 then release_listener = hl.on("input.keyboard.key", on_key) end
end

_G.__move_cursor_display = M
return M
