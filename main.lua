-- Lutro BIOS Checker
--
-- Walks resources/System.dat (libretro's BIOS/firmware database) and reports which
-- listed files are present in the libretro system directory and which are missing.
-- Runs as a three-phase state machine so the progress bar animates while checking.
local datparser = require 'src/datparser'
local checker   = require 'src/checker'
local report    = require 'src/report'
local text      = require 'src/text'

local PHASE = { LOADING = 1, CHECKING = 2, REPORT = 3 }

local app = { phase = PHASE.LOADING, holdTimer = 0, mouseHold = 0, mouseDown = false }

-- Layout is finalized in lutro.load() once the real framebuffer size is known;
-- width/height here are fallbacks matching conf.lua.
local layout = {
    x = 4,
    lineHeight = 18, -- font.png is 17px tall
    width = 480,
    height = 360,
}

local WHEEL_STEP = 3 -- lines scrolled per mouse-wheel notch

local function drawProgress(g)
    local p = app.checker:progress()
    local bw = math.floor(layout.width * 0.6)
    local bh = 16
    local bx = math.floor((layout.width - bw) / 2)
    local by = math.floor(layout.height / 2) - bh

    g.setColor(255, 255, 255)
    g.print("Checking BIOS files", bx, by - 22)

    g.setColor(90, 92, 110)
    g.rectangle("line", bx, by, bw, bh)

    g.setColor(120, 200, 120)
    g.rectangle("fill", bx + 1, by + 1, math.floor((bw - 2) * p), bh - 2)

    g.setColor(220, 220, 220)
    local c = app.checker.counts
    g.print(c.checked .. " / " .. c.total, bx, by + bh + 6)
end

function lutro.load()
    font = lutro.graphics.newImageFont("resources/font.png", text.FONT_CHARS)
    lutro.graphics.setFont(font)
    lutro.graphics.setBackgroundColor(40, 42, 54)

    local w = lutro.graphics.getWidth()
    local h = lutro.graphics.getHeight()
    if w and w > 0 then layout.width = w end
    if h and h > 0 then layout.height = h end
    screenWidth = layout.width
    screenHeight = layout.height

    -- One header line (summary on the left, checkbox at the top-right) above the list.
    layout.headerY = 2
    layout.top = 2 + layout.lineHeight
    layout.visibleLines = math.floor((layout.height - layout.top) / layout.lineHeight)

    app.phase = PHASE.LOADING
end

function lutro.update(dt)
    if app.phase == PHASE.LOADING then
        local contents = love.filesystem.read("resources/System.dat")
        app.entries = datparser.parse(contents or "")
        app.checker = checker.new(app.entries, love.filesystem.getAppdataDirectory())
        app.phase = PHASE.CHECKING
    elseif app.phase == PHASE.CHECKING then
        if app.checker:update() then
            app.report = report.build(app.entries, app.checker.results, app.checker.counts, {
                visibleLines = layout.visibleLines,
                noSystemDir = app.checker.noSystemDir,
                width = layout.width,
                x = layout.x,
            })
            app.phase = PHASE.REPORT
        end
    elseif app.phase == PHASE.REPORT then
        local r = app.report

        -- Auto-repeat while the d-pad is held (player 1). The first step is handled
        -- by lutro.joystickpressed; this kicks in after a short delay for held scroll.
        local dir = 0
        if lutro.input.joypad("up") == 1 then
            dir = -1
        elseif lutro.input.joypad("down") == 1 then
            dir = 1
        end
        if dir ~= 0 then
            app.holdTimer = app.holdTimer + 1
            if app.holdTimer > 12 and app.holdTimer % 3 == 0 then
                r:scroll(dir)
            end
        else
            app.holdTimer = 0
        end

        -- Mouse buttons 4 (scroll up) and 5 (scroll down), polled so holding a
        -- button keeps scrolling. The rising edge gives an immediate first step;
        -- holding then auto-repeats on the same cadence as the d-pad.
        local mdir = 0
        if lutro.mouse.isDown(4) then
            mdir = -1
        elseif lutro.mouse.isDown(5) then
            mdir = 1
        end
        if mdir ~= 0 then
            if app.mouseHold == 0 then r:scroll(mdir) end
            app.mouseHold = app.mouseHold + 1
            if app.mouseHold > 12 and app.mouseHold % 3 == 0 then
                r:scroll(mdir)
            end
        else
            app.mouseHold = 0
        end

        -- Scrollbar drag with the left button: grab on press, follow while held,
        -- release on let-go.
        local down = lutro.mouse.isDown(1)
        if down then
            local mx, my = lutro.mouse.getX(), lutro.mouse.getY()
            if not app.mouseDown then
                r:beginDrag(mx, my, layout)
            elseif r.dragging then
                r:dragTo(my, layout)
            end
        else
            r:endDrag()
        end
        app.mouseDown = down
    end
end

function lutro.draw()
    local g = lutro.graphics
    g.clear()

    if app.phase == PHASE.LOADING then
        g.setColor(255, 255, 255)
        g.print("Loading System.dat", layout.x, math.floor(layout.height / 2))
    elseif app.phase == PHASE.CHECKING then
        drawProgress(g)
    else
        app.report:draw(g, layout)
    end
end

function lutro.keypressed(key)
    if app.phase ~= PHASE.REPORT then return end
    local r = app.report
    if key == "up" then
        r:scroll(-1)
    elseif key == "down" then
        r:scroll(1)
    elseif key == "pageup" then
        r:page(-1)
    elseif key == "pagedown" then
        r:page(1)
    elseif key == "home" then
        r:home()
    elseif key == "end" then
        r:toEnd()
    elseif key == "left" then
        r:jumpCategory(-1)
    elseif key == "right" then
        r:jumpCategory(1)
    elseif key == "return" or key == "space" then
        r:toggleFilter()
    end
end

-- Gamepad input. Lutro passes a raw RETRO_DEVICE_JOYPAD button index:
-- b=0 up=4 down=5 left=6 right=7 a=8. D-pad scrolls/pages, A or B toggles.
function lutro.joystickpressed(joystick, button)
    if app.phase ~= PHASE.REPORT then return end
    local r = app.report
    if button == 4 then
        r:scroll(-1)
    elseif button == 5 then
        r:scroll(1)
    elseif button == 6 then
        r:jumpCategory(-1)
    elseif button == 7 then
        r:jumpCategory(1)
    elseif button == 10 then
        r:jumpCategory(-1)
    elseif button == 11 then
        r:jumpCategory(1)
    elseif button == 0 or button == 8 then -- B or A
        r:toggleFilter()
    end
end

-- Mouse-wheel scrolling. y is positive when the wheel rolls up (toward the top).
function lutro.wheelmoved(x, y)
    if app.phase ~= PHASE.REPORT or not app.report then return end
    if y > 0 then
        app.report:scroll(-WHEEL_STEP)
    elseif y < 0 then
        app.report:scroll(WHEEL_STEP)
    end
end
