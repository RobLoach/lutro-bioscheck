function updateReport()
    -- Load the files
    contents, size = love.filesystem.read("resources/System.dat", 0)

    local systemDirectory = love.filesystem.getAppdataDirectory()
    print("System Directory: " .. systemDirectory)

    print("File: " .. systemDirectory .. "/5200.rom")
    local s = love.filesystem.exists(systemDirectory .. "/5200.rom")
    print("Exists: " .. tostring(s))

    -- TODO: Fix access to systemDirectory.
end

function lutro.load()
    -- Vendor libraries
    md5 = require 'vendor/md5'

    -- Load the font
    font = lutro.graphics.newImageFont("resources/font.png", " abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!?-+/")
    lutro.graphics.setFont(font)

    -- Set up the display
    lutro.graphics.setBackgroundColor(40, 42, 54)
    screenWidth = 320
    screenHeight = 240

    updateReport()
end

function lutro.update(dt)
end

function lutro.draw()
	lutro.graphics.clear()
    lutro.graphics.print("System Checker", 10, 10)


    local md5_as_hex   = md5.sumhexa("Hello, World!")
    lutro.graphics.print("MD5: " .. md5_as_hex, 10, 100)
end