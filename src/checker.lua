local M = {}

M.STATUS = { PENDING = "PENDING", OK = "OK", MISSING = "MISSING" }

local Checker = {}
Checker.__index = Checker

function M.new(entries, systemDir, opts)
    opts = opts or {}
    systemDir = systemDir or ""
    local dir = systemDir:gsub("[/\\]+$", "") -- drop any trailing separator

    local self = setmetatable({}, Checker)
    self.entries = entries
    self.dir = dir
    self.noSystemDir = (dir == "")
    self.i = 1
    self.results = {}
    self.counts = { present = 0, missing = 0, checked = 0, total = #entries }
    self.entriesPerTick = opts.entriesPerTick or 24
    self.done = (#entries == 0)
    return self
end

-- Advance one frame's worth of work. Returns true once every entry is checked.
function Checker:update()
    if self.done then return true end

    local budget = self.entriesPerTick
    while self.i <= #self.entries and budget > 0 do
        local entry = self.entries[self.i]
        local status = M.STATUS.MISSING

        if not self.noSystemDir then
            local f = io.open(self.dir .. "/" .. entry.name, "rb")
            if f then
                f:close()
                status = M.STATUS.OK
            end
        end

        if status == M.STATUS.OK then
            self.counts.present = self.counts.present + 1
        else
            self.counts.missing = self.counts.missing + 1
        end

        self.results[self.i] = { status = status, entry = entry }
        self.counts.checked = self.counts.checked + 1
        self.i = self.i + 1
        budget = budget - 1
    end

    if self.i > #self.entries then
        self.done = true
    end
    return self.done
end

function Checker:isDone()
    return self.done
end

function Checker:progress()
    if self.counts.total == 0 then return 1 end
    return self.counts.checked / self.counts.total
end

return M
