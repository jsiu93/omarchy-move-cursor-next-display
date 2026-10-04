-- Geometry tests for hypr/core.lua. Run from the repository root:
--   lua test/core_test.lua

local core = dofile("hypr/core.lua")
local count = 0
local function near(actual, expected, epsilon)
    assert(math.abs(actual - expected) <= (epsilon or 1e-8),
        string.format("expected %.12f, got %.12f", expected, actual))
end
local function point(actual, x, y)
    assert(actual, "Expected a destination")
    near(actual.x, x); near(actual.y, y)
end
local function mon(name, x, y, width, height, scale, transform)
    return { name = name, x = x, y = y, width = width or 100,
        height = height or 100, scale = scale or 1, transform = transform or 0 }
end
local function move(ms, x, y, direction, placement)
    return core.destination(ms, { x = x, y = y }, direction or "next", placement or "relative")
end
local function test(name, run)
    run(); count = count + 1; print("ok " .. count .. " - " .. name)
end

-- ---- Layout and current-display selection ----------------------------------
test("horizontal order, wrap and input immutability", function()
    local ms = { mon("right", 100, 0), mon("left", 0, 0) }
    point(move(ms, 20, 30), 120, 30)
    point(move(ms, 120, 30), 20, 30)
    point(move(ms, 20, 30, "prev"), 120, 30)
    assert(ms[1].name == "right" and ms[1].w == nil)
end)
test("vertical order", function()
    local ms = { mon("bottom", 0, 100), mon("top", 0, 0) }
    point(move(ms, 20, 30), 20, 130)
end)
test("L-shaped layout uses x then y", function()
    local ms = { mon("right", 100, 0), mon("bottom", 0, 100), mon("top", 0, 0) }
    point(move(ms, 20, 30), 20, 130)
    point(move(ms, 20, 130), 120, 30)
    point(move(ms, 120, 30), 20, 30)
end)
test("negative monitor origins", function()
    point(move({ mon("left", -100, -100), mon("right", 0, 0) }, -80, -70), 20, 30)
end)
test("half-open horizontal boundary belongs to the right display", function()
    point(move({ mon("left", 0, 0), mon("right", 100, 0) }, 100, 30), 0, 30)
end)
test("half-open vertical boundary belongs to the lower display", function()
    point(move({ mon("top", 0, 0), mon("bottom", 0, 100) }, 20, 100), 20, 0)
end)
test("outside selects nearest rectangle", function()
    point(move({ mon("a", 0, 0), mon("b", 200, 0), mon("c", 400, 0) }, 190, 50), 400, 50)
end)
test("outside distance ties use sorted order", function()
    point(move({ mon("b", 200, 0), mon("a", 0, 0), mon("c", 400, 0) }, 150, 50), 299, 50)
end)
test("overlap and identical origins keep deterministic input order", function()
    local ms = { mon("a", 0, 0), mon("b", 0, 0, 200, 200), mon("c", 300, 0) }
    point(move(ms, 20, 30, "next", "center"), 100, 100)
end)

-- ---- Logical geometry and placement ----------------------------------------
test("mixed scaling and relative addressable spans", function()
    local ms = { mon("a", 0, 0, 1920, 1080, 1.5), mon("b", 1280, 0, 3840, 2160, 2) }
    point(move(ms, 319.75, 179.75), 1280 + 1919 / 4, 1079 / 4)
end)
test("90 and 270 degrees exchange logical axes", function()
    for _, transform in ipairs({ 1, 3, 5, 7 }) do
        local m = mon("portrait", 100, 0, 300, 200, 2, transform)
        local r = core.logical_rect(m)
        near(r.w, 100); near(r.h, 150)
        point(move({ mon("a", 0, 0), m }, 49.5, 49.5), 149.5, 74.5)
    end
end)
test("even transforms preserve logical axes", function()
    for _, transform in ipairs({ 0, 2, 4, 6 }) do
        local r = core.logical_rect(mon("a", 0, 0, 300, 200, 2, transform))
        near(r.w, 150); near(r.h, 100)
    end
end)
test("center is the exact logical midpoint", function()
    point(move({ mon("a", 0, 0), mon("b", 100, -50, 303, 201, 2) }, 10, 20, "next", "center"), 175.75, 0.25)
end)
test("previous center selects the previous display", function()
    point(move({ mon("a", 0, 0), mon("b", 100, 0), mon("c", 200, 0) }, 20, 30, "prev", "center"), 250, 50)
end)
test("out-of-bounds coordinates clamp to destination endpoints", function()
    local ms = { mon("a", 0, 0), mon("b", 100, 0) }
    point(move(ms, -50, -50), 100, 0)
    point(move(ms, 400, 400), 99, 99)
end)
test("fractional coordinates retain precision without integer rounding", function()
    point(move({ mon("a", 0, 0), mon("b", 100, 0) }, 20.125, 30.875), 120.125, 30.875)
end)
test("empty and single-display layouts return nil", function()
    assert(move({}, 0, 0) == nil)
    assert(move({ mon("a", 0, 0) }, 20, 30) == nil)
end)
test("one-pixel spans have defined clamped destinations", function()
    point(move({ mon("a", 0, 0, 1, 1), mon("b", 2, 0) }, 0, 0), 2, 0)
    point(move({ mon("a", 0, 0), mon("b", 100, 0, 1, 1) }, 20, 30, "next", "center"), 100, 0)
end)

-- ---- Round-trip invariants --------------------------------------------------
local cycle = { mon("c", 1800, 100, 3000, 2000, 2, 3),
    mon("a", -1200, -100, 1800, 1200, 1.5), mon("b", 0, 0, 2560, 1440, 2) }
for _, direction in ipairs({ "next", "prev" }) do
    test("three-display " .. direction .. " cycle preserves subpixels and edges", function()
        for _, m in ipairs(cycle) do
            local r = core.logical_rect(m)
            for _, f in ipairs({ 0, 0.001, 0.25, 0.5, 0.999, 1 }) do
                local start = { x = r.x + (r.w - 1) * f, y = r.y + (r.h - 1) * f }
                local p = start
                for _ = 1, #cycle do p = core.destination(cycle, p, direction, "relative") end
                point(p, start.x, start.y)
            end
        end
    end)
end
test("next then previous restores fractional starting point", function()
    local p = move(cycle, -810.123, 150.456)
    point(core.destination(cycle, p, "prev", "relative"), -810.123, 150.456)
end)
test("extreme size differences preserve last addressable pixel", function()
    local ms = { mon("large", 0, 0, 8000, 4000), mon("small", 8000, 0, 100, 100) }
    local p = move(ms, 7999, 3999)
    point(p, 8099, 99)
    point(core.destination(ms, p, "next", "relative"), 7999, 3999)
end)
test("fractional strip beyond final addressable pixel loses at most one pixel", function()
    local ms = { mon("a", 0, 0), mon("b", 100, 0, 1000, 1000) }
    local p = move(ms, 99.75, 99.9)
    local back = core.destination(ms, p, "next", "relative")
    near(back.x, 99.75, 1); near(back.y, 99.9, 1)
end)
print(string.format("PASS: %d tests", count))
