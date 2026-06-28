-- Scrollable report view.
local text = require 'src/text'
local STATUS = require('src/checker').STATUS

local M = {}
local COLOR = {
    summary  = { 255, 255, 255 },
    category = { 120, 160, 255 },
    ok       = { 120, 200, 120 },
    missing  = { 235, 100, 100 },
    track    = { 70, 72, 90 },
    thumb    = { 150, 152, 170 },
}

local ICON_SIZE = 9
local ICON_GAP = 5 -- gap between the left-hand status icon and the filename
-- Approximate average glyph width; font.png is 605px for 73 glyphs (≈8.3px each).
-- Lutro's ImageFont uses per-glyph widths so there is no single exact value; 8.5 is
-- a safe ceiling that avoids clipping while keeping filenames as long as possible.
local CHAR_W = 8.5
local SCROLLBAR_W = 12 -- scrollbar width in pixels

local Report = {}
Report.__index = Report

local function tallyCounts(entries, results)
    local counts = {}
    for i = 1, #entries do
        local cat = entries[i].category or "Uncategorized"
        if not counts[cat] then
            counts[cat] = { present = 0, total = 0 }
        end
        counts[cat].total = counts[cat].total + 1
        if results[i].status == STATUS.OK then
            counts[cat].present = counts[cat].present + 1
        end
    end
    return counts
end

local function buildRows(entries, results, mode, nameChars, catCounts)
    local rows = {}
    local lastCategory = nil
    local pendingHeader = nil

    for i = 1, #entries do
        local entry = entries[i]
        local result = results[i]
        local include = (mode == "all") or (result.status ~= STATUS.OK)

        if entry.category ~= lastCategory then
            lastCategory = entry.category
            pendingHeader = entry.category or "Uncategorized"
        end

        if include then
            if pendingHeader then
                if #rows > 0 then
                    rows[#rows + 1] = { kind = "spacer" }
                end
                local cc = catCounts[pendingHeader]
                local countStr = cc and (cc.present .. "/" .. cc.total) or ""
                rows[#rows + 1] = { kind = "header", display = text.sanitize(pendingHeader), countStr = countStr }
                pendingHeader = nil
            end
            rows[#rows + 1] = {
                kind = "file",
                status = result.status,
                name = text.truncate(entry.name, nameChars),
            }
        end
    end

    return rows
end

function M.build(entries, results, counts, opts)
    opts = opts or {}
    local width = opts.width or 320
    local x = opts.x or 4
    -- The status icon sits at the left; the name fills the rest, leaving room for the
    -- scrollbar (and a small gap) on the right.
    local nameChars = math.floor((width - x - ICON_SIZE - ICON_GAP - SCROLLBAR_W - 6) / CHAR_W)
    if nameChars < 8 then nameChars = 8 end

    local self = setmetatable({}, Report)
    self.counts = counts
    self.noSystemDir = opts.noSystemDir
    self.visibleLines = opts.visibleLines or 12
    local catCounts = tallyCounts(entries, results)
    self.allRows = buildRows(entries, results, "all", nameChars, catCounts)
    self.missingRows = buildRows(entries, results, "missing", nameChars, catCounts)
    self.filter = "all"
    self.rows = self.allRows
    self.scrollOffset = 0
    self.dragging = false
    self.dragGrab = 0 -- cursor offset within the thumb at grab time
    return self
end

function Report:maxOffset()
    return math.max(0, #self.rows - self.visibleLines)
end

function Report:scroll(delta)
    self.scrollOffset = self.scrollOffset + delta
    local maxOff = self:maxOffset()
    if self.scrollOffset < 0 then self.scrollOffset = 0 end
    if self.scrollOffset > maxOff then self.scrollOffset = maxOff end
end

function Report:page(dir)
    self:scroll(dir * self.visibleLines)
end

function Report:home()
    self.scrollOffset = 0
end

function Report:toEnd()
    self.scrollOffset = self:maxOffset()
end

function Report:toggleFilter()
    if self.filter == "all" then
        self.filter = "missing"
        self.rows = self.missingRows
    else
        self.filter = "all"
        self.rows = self.allRows
    end
    self.scrollOffset = 0
end

function Report:jumpCategory(dir)
    local headers = {}
    for i = 1, #self.rows do
        if self.rows[i].kind == "header" then
            headers[#headers + 1] = i - 1
        end
    end
    if #headers == 0 then return end

    if dir > 0 then
        for _, pos in ipairs(headers) do
            if pos > self.scrollOffset then
                self.scrollOffset = math.min(pos, self:maxOffset())
                return
            end
        end
    else
        for i = #headers, 1, -1 do
            if headers[i] < self.scrollOffset then
                self.scrollOffset = headers[i]
                return
            end
        end
        self.scrollOffset = 0
    end
end

-- Scrollbar geometry for the given layout, or nil when the list fits (no bar).
-- Returns trackX, trackY, trackH, thumbH, thumbY so drawing and hit-testing agree.
function Report:scrollbarRect(layout)
    if #self.rows <= self.visibleLines then return nil end
    local trackX = layout.width - SCROLLBAR_W - 2
    local trackY = layout.top
    local trackH = layout.height - layout.top
    local thumbH = math.max(6, math.floor(trackH * self.visibleLines / #self.rows))
    local maxOff = math.max(1, self:maxOffset())
    local thumbY = trackY + math.floor((trackH - thumbH) * (self.scrollOffset / maxOff))
    return trackX, trackY, trackH, thumbH, thumbY
end

-- Start a scrollbar drag if (mx, my) lands on the bar. Grabbing the thumb keeps
-- the cursor's position within it; clicking the track jumps the thumb under the
-- cursor. Returns true when a drag began.
function Report:beginDrag(mx, my, layout)
    local trackX, trackY, trackH, thumbH, thumbY = self:scrollbarRect(layout)
    if not trackX then return false end
    if mx < trackX or mx >= trackX + SCROLLBAR_W then return false end
    if my < trackY or my >= trackY + trackH then return false end

    if my >= thumbY and my < thumbY + thumbH then
        self.dragGrab = my - thumbY
    else
        self.dragGrab = math.floor(thumbH / 2)
    end
    self.dragging = true
    self:dragTo(my, layout)
    return true
end

-- Map a cursor Y to a scroll offset while dragging the scrollbar.
function Report:dragTo(my, layout)
    local trackX, trackY, trackH, thumbH = self:scrollbarRect(layout)
    if not trackX then return end
    local span = trackH - thumbH
    if span <= 0 then return end
    local t = (my - self.dragGrab - trackY) / span
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    self.scrollOffset = math.floor(t * self:maxOffset() + 0.5)
end

function Report:endDrag()
    self.dragging = false
end

function Report:summaryLine()
    if self.noSystemDir then
        return "System dir not set - all missing"
    end
    local c = self.counts
    return "BIOS Check - " .. c.present .. "/" .. c.total
end

-- Draw a bolder line by doubling the 1px stroke one pixel to the side.
local function stroke(g, x1, y1, x2, y2)
    g.line(x1, y1, x2, y2)
    g.line(x1 + 1, y1, x2 + 1, y2)
end

-- Checkmark and X primitives, built from lutro.graphics.line inside a size x size
-- box anchored at (x, y). The caller sets the colour first.
local function drawCheckmark(g, x, y, size)
    local vx = x + math.floor(size * 0.4)
    stroke(g, x + 1, y + math.floor(size * 0.55), vx, y + size - 1)
    stroke(g, vx, y + size - 1, x + size - 1, y + 1)
end

local function drawCross(g, x, y, size)
    stroke(g, x + 1, y + 1, x + size - 2, y + size - 2)
    stroke(g, x + size - 2, y + 1, x + 1, y + size - 2)
end

local function drawStatusIcon(g, status, x, y, size)
    if status == STATUS.OK then
        g.setColor(COLOR.ok[1], COLOR.ok[2], COLOR.ok[3])
        drawCheckmark(g, x, y, size)
    else
        g.setColor(COLOR.missing[1], COLOR.missing[2], COLOR.missing[3])
        drawCross(g, x, y, size)
    end
end

function Report:draw(g, layout)
    g.setColor(COLOR.summary[1], COLOR.summary[2], COLOR.summary[3])
    g.print(self:summaryLine(), layout.x, layout.headerY)

    -- Checkbox (top-right) toggling visibility of present (OK) files; checked = shown.
    local boxSize = 12
    local boxX = layout.width - boxSize - 4
    g.setColor(COLOR.summary[1], COLOR.summary[2], COLOR.summary[3])
    g.rectangle("line", boxX, layout.headerY, boxSize, boxSize)
    if self.filter == "all" then
        g.setColor(COLOR.ok[1], COLOR.ok[2], COLOR.ok[3])
        drawCheckmark(g, boxX + 1, layout.headerY + 1, boxSize - 2)
    end

    if #self.rows == 0 and self.filter == "missing" then
        g.setColor(COLOR.ok[1], COLOR.ok[2], COLOR.ok[3])
        g.print("All BIOS present", layout.x, layout.top)
        return
    end

    local iconDY = math.floor((layout.lineHeight - ICON_SIZE) / 2)
    local nameX = layout.x + ICON_SIZE + ICON_GAP
    local first = self.scrollOffset
    for row = 0, self.visibleLines - 1 do
        local item = self.rows[first + row + 1]
        if not item then break end
        local y = layout.top + row * layout.lineHeight
        if item.kind == "header" then
            g.setColor(COLOR.category[1], COLOR.category[2], COLOR.category[3])
            g.print(item.display, layout.x, y)
            if item.countStr then
                local cx = layout.width - SCROLLBAR_W - 4 - math.floor(#item.countStr * CHAR_W)
                g.print(item.countStr, cx, y)
            end
        elseif item.kind == "file" then
            drawStatusIcon(g, item.status, layout.x, y + iconDY, ICON_SIZE)
            local c = (item.status == STATUS.OK) and COLOR.ok or COLOR.missing
            g.setColor(c[1], c[2], c[3])
            g.print(item.name, nameX, y)
        end
    end

    -- Scrollbar, drawn only when the list overflows the window.
    local trackX, trackY, trackH, thumbH, thumbY = self:scrollbarRect(layout)
    if trackX then
        g.setColor(COLOR.track[1], COLOR.track[2], COLOR.track[3])
        g.rectangle("fill", trackX, trackY, SCROLLBAR_W, trackH)
        g.setColor(COLOR.thumb[1], COLOR.thumb[2], COLOR.thumb[3])
        g.rectangle("fill", trackX, thumbY, SCROLLBAR_W, thumbH)
    end
end

return M
