-- Text helpers for the BIOS checker UI.
-- FONT_CHARS is the single source of truth for the image-font glyph set; it must
-- stay in lockstep with resources/font.png (extend both together via tools/genfont.py).
local M = {}

-- Existing glyphs plus the "_ ( )" added by tools/genfont.py.
M.FONT_CHARS = " abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!?-+/_()"

local allowed = {}
for i = 1, #M.FONT_CHARS do
    allowed[M.FONT_CHARS:sub(i, i)] = true
end

-- Strip any leading "dir/sub/" so a long path renders as just its filename.
function M.basename(s)
    return s:match("[^/]+$") or s
end

-- Replace characters the font can't render with "?" (the font has "?").
-- A no-op for everything in System.dat now that the font covers "_ ( )"; this is
-- a safety net against an unexpected character in a future database.
function M.sanitize(s)
    return (s:gsub(".", function(ch)
        if allowed[ch] then return ch end
        return "?"
    end))
end

-- Sanitize and hard-truncate to maxChars columns (no ellipsis glyph exists).
function M.truncate(s, maxChars)
    s = M.sanitize(s)
    if #s > maxChars then
        s = s:sub(1, maxChars)
    end
    return s
end

return M
