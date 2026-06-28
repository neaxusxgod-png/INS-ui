--[[ INS ui — showcase / demo
     Run:
       loadstring(game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/showcase.lua"))()
     Press P to open/close the menu. Every widget below is live.
]]

local Lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua"))() or INSui

local win = Lib:CreateWindow({
    title    = "INS ui",
    subtitle = "showcase",
    size     = Vector2.new(720, 560),
    menuKey  = "p",
})

win:AddSettingsTab("cog")                 -- built-in themes / fonts / configs / performance
Lib:Notify("INS ui", "Press P to toggle the menu", 4, "info")

-- ===================== COMBAT =====================
local combat = win:Tab("Combat", "swords")

local aim   = combat:Section("Aimbot", "Left", "silent + legit aim assist")
local aimOn = aim:Toggle("Enabled", false, function(on)
    Lib:Notify("Aimbot", on and "enabled" or "disabled", 2, on and "success" or "warning")
end)
aimOn:AddKeybind("e", "Hold")
aimOn:AddColorpicker("FOV color", Color3.fromRGB(120, 255, 140), function(c, a) end)
aim:Slider("FOV", 120, 1, 10, 500, "px", function(v) end)
aim:Slider("Smoothness", 0.30, 0.01, 0, 1, "", function(v) end)
aim:Dropdown("Target part", {"Head"}, {"Head", "Torso", "Neck", "Random"}, false, function(v) end)
aim:Dropdown("Hitboxes", {"Head"}, {"Head", "Torso", "Neck", "Stomach", "Legs"}, true, function(v) end, "multi-select", true)
local wall = aim:Toggle("Wall check", true)
aim:Toggle("Visible only", false):DependsOn(wall)

local trig = combat:Section("Triggerbot", "Right")
trig:Toggle("Enabled", false):AddKeybind("t", "Toggle")
trig:Slider("Delay", 80, 1, 0, 500, "ms", function(v) end)
trig:Slider("Hit chance", 100, 1, 1, 100, "%", function(v) end)
trig:RangeSlider("Distance", 0, 150, 1, 0, 500, "m", function(lo, hi) end)

-- ===================== VISUALS =====================
local vis = win:Tab("Visuals", "eye")

local esp = vis:Section("Player ESP", "Left", "see players through walls")
esp:Toggle("Enabled", true)
esp:Dropdown("Box style", {"Corner"}, {"2D", "Corner", "3D", "Off"}, false, function(v) end)
esp:Colorpicker("Box color", Color3.fromRGB(122, 134, 255), function(c, a) end, 1)
esp:Colorpicker("Fill color", Color3.fromRGB(122, 134, 255), function(c, a) end, 0.35)
esp:Toggle("Name", true)
esp:Toggle("Distance", true)
esp:Slider("Text size", 13, 1, 8, 24, "px", function(v) end)

local world = vis:Section("World", "Right")
world:Toggle("Fullbright", false, function(on) end)
world:Slider("Time of day", 14, 0.1, 0, 24, "h", function(v) end)
world:Toggle("No fog", false)
world:Colorpicker("Ambient", Color3.fromRGB(255, 255, 255), function(c) end)

vis:Section("Notes", "Full"):Info("This whole menu is drawn with Matcha's Drawing API only — no Roblox GUI instances. Everything here is triangles, squares and text.")

-- ===================== MISC =====================
local misc = win:Tab("Misc", "gauge")

local mv = misc:Section("Movement", "Left")
mv:Slider("Walk speed", 16, 1, 16, 250, "", function(v) end)
mv:Slider("Jump power", 50, 1, 50, 300, "", function(v) end)
mv:Toggle("Fly", false):AddKeybind("g", "Toggle", function(on) Lib:Notify("Fly", on and "on" or "off", 1) end)
mv:Toggle("Infinite jump", false)
mv:Keybind("Panic key", "k", function(key) Lib:Notify("Panic", "rebound to " .. tostring(key), 2) end)

local srv = misc:Section("Server", "Right")
srv:Button("Rejoin", function() Lib:Notify("Server", "rejoining...", 2) end)
   :AddButton("Server hop", function() Lib:Notify("Server", "hopping...", 2) end)
srv:Textbox("Webhook URL", "", function(text) end)
srv:Divider("Danger zone")
srv:Button("Unload menu", function()
    Lib:Dialog({
        title     = "Unload?",
        text      = "Remove the INS ui menu from the game?",
        confirm   = "Unload",
        onConfirm = function() Lib:Destroy() end,
    })
end):SetRisk()

-- a custom card dropped into the built-in Settings tab
local mine = win:SettingsSection("Showcase", "Right")
mine:Toggle("Streamer mode", false)
mine:Slider("UI scale", 100, 5, 50, 150, "%", function(v) end)

-- ===================== floating HUD box =====================
local box = Lib:CreateBox({ title = "Stats", position = Vector2.new(24, 150), width = 190 })
box:Stat("Kills: 0")
box:Stat("Ping: 42 ms")
box:Bar(0.7)

Lib:Notify("Loaded", "INS ui showcase ready", 3, "success")
