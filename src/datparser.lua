-- Parser for the clrmamepro text format used by libretro's System.dat.
local M = {}

local function parseRom(line)
    -- Quoted form first: names contain spaces/parens, so match must be non-greedy.
    local name = line:match('name%s+"(.-)"')
    if not name then
        name = line:match('name%s+(%S+)')
    end
    if not name then return nil end

    local size = line:match('%ssize%s+(%d+)')
    return {
        name = name,
        size = size and tonumber(size) or nil,
        crc  = line:match('%scrc%s+(%x+)'),
        md5  = line:match('%smd5%s+(%x+)'),
        sha1 = line:match('%ssha1%s+(%x+)'),
    }
end

-- parse(text) -> ordered array of { name, size, crc, md5, sha1, category }
function M.parse(text)
    local entries = {}
    local inGame = false
    local category = nil

    for line in (text .. "\n"):gmatch("(.-)\n") do
        if not inGame and line:match("^%s*game%s*%(") then
            inGame = true -- everything before this is the header block; skip it
        end

        if inGame then
            local comment = line:match('comment%s+"(.-)"')
            if comment then
                category = comment
            elseif line:match("rom%s*%(") then
                local entry = parseRom(line)
                if entry then
                    entry.category = category
                    entries[#entries + 1] = entry
                end
            end
        end
    end

    return entries
end

return M
