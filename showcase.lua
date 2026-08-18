local Lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua"))() or INSUI

local Players = game:GetService("Players")

local win = Lib:CreateWindow({
    title    = "INSUI",
    subtitle = "auto",
    size     = Vector2.new(700, 520),
    menuKey  = "p",
    smartFps = false,
    checkboxStyle = true,
    opacity  = 98,
    logo     = "https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/assets/logo.png",
})

win:AddSettingsTab("gear")
Lib:Notify("INSUI", "Press P to toggle the menu", 4, "info")

Lib:Category("COMBAT")
local combat = win:Tab("Combat", "sword")

local aim = combat:Section("Aimbot", "Left", "silent + legit aim assist")
local aimOn = aim:Toggle("Enabled", false, function(on)
    Lib:Notify("Aimbot", on and "enabled" or "disabled", 2, on and "success" or "warning")
end)
aimOn:AddKeybind("e", "Hold")
aimOn:AddColorpicker("FOV color", Color3.fromRGB(120, 255, 140))

aim:Divider("Targeting")
aim:Dropdown("Target part", {"Head"}, {"Head", "Torso", "Neck", "Random"}, false, function(v) end)
aim:Dropdown("Hitboxes", {"Head"}, {"Head", "Torso", "Neck", "Stomach", "Legs"}, true, function(v) end, "multi-select", true)
aim:Slider("FOV", 120, 1, 10, 500, "px", function(v) end)
aim:Toggle("Sticky target", true, nil, "keep the same target while it stays in FOV")

aim:Divider("Smoothing")
aim:Slider("Smoothness", 0.30, 0.01, 0, 1, "", function(v) end)
aim:Slider("Reaction time", 120, 5, 0, 400, "ms", function(v) end)

aim:Divider("Safety")
local wall = aim:Toggle("Wall check", true)
aim:Toggle("Visible only", false):DependsOn(wall)
aim:RangeSlider("Distance", 0, 150, 1, 0, 500, "m", function(lo, hi) end)

local trig = combat:Section("Triggerbot", "Right")
trig:Toggle("Enabled", false):AddKeybind("t", "Toggle")

trig:Divider("Timing")
trig:Slider("Delay", 80, 1, 0, 500, "ms", function(v) end)
trig:Slider("Hit chance", 100, 1, 1, 100, "%", function(v) end)

trig:Divider("Filters")
trig:Toggle("Team check", true)
trig:Toggle("Wall check", true)
trig:Toggle("Scoped only", false, nil, "fire only while aiming down sights")

local wep = combat:Section("Weapon", "Right")
wep:Toggle("No recoil", false)
wep:Toggle("No spread", false)
wep:Slider("Fire rate", 1.0, 0.1, 0.5, 3, "x", function(v) end)

wep:Divider("Ammo")
wep:Toggle("Fast reload", false)
wep:Toggle("Infinite ammo", false, function(on) end):SetRisk():Tooltip("server-sided games will flag this")

Lib:Category("VISUALS")
local vis = win:Tab("Visuals", "eye")

local esp = vis:Section("Player ESP", "Left", "see players through walls")
esp:Toggle("Enabled", true):AddKeybind("h", "Toggle")

esp:Divider("Boxes")
esp:Dropdown("Box style", {"Corner"}, {"2D", "Corner", "3D", "Off"}, false, function(v) end)
esp:Colorpicker("Box color", Color3.fromRGB(122, 134, 255), function(c, a) end, 1)
esp:Colorpicker("Fill color", Color3.fromRGB(122, 134, 255), function(c, a) end, 0.35)

esp:Divider("Info")
esp:Toggle("Name", true)
esp:Toggle("Distance", true)
esp:Toggle("Health bar", true)
esp:Toggle("Weapon", false)
esp:Slider("Text size", 13, 1, 8, 24, "px", function(v) end)

esp:Divider("Filters")
esp:RangeSlider("Render distance", 0, 300, 5, 0, 1000, "m", function(lo, hi) end)
esp:Toggle("Team check", true)

local hud = vis:Section("Overlay", "Left")
hud:Label(function() return "Local time: " .. os.date("%X") end)
hud:Toggle("Watermark", true)
hud:Toggle("FPS counter", false)
hud:Info("overlay drawings stay when the menu is closed")

local ch = vis:Section("Chams", "Right")
ch:Toggle("Enabled", false)
ch:Dropdown("Material", {"ForceField"}, {"ForceField", "Neon", "Flat"}, false, function(v) end)
ch:Colorpicker("Visible color", Color3.fromRGB(140, 255, 160))
ch:Colorpicker("Hidden color", Color3.fromRGB(255, 120, 120))
ch:Slider("Transparency", 0.3, 0.05, 0, 1, "", function(v) end)

local world = vis:Section("World", "Right")
world:Toggle("Fullbright", false, function(on) end)
world:Slider("Time of day", 14, 0.1, 0, 24, "h", function(v) end)
world:Toggle("No fog", false)
world:Colorpicker("Ambient", Color3.fromRGB(255, 255, 255), function(c) end)

world:Divider("Extras")
world:Dropdown("Weather", {"Clear"}, {"Clear", "Rain", "Snow"}, false, function(v) end)
world:Toggle("No shadows", false)

Lib:Category("SYSTEM")
local world = win:Tab("World", "globe")

local wPlayers = world:Sub("Players", "users")
local plist = wPlayers:Section("Player list", "Left", "everyone in the server")
plist:Toggle("Highlight friends", true)
plist:Toggle("Highlight enemies", false)
plist:Dropdown("Sort by", {"Distance"}, {"Distance", "Name", "Team", "Health"}, false, function(v) end)
plist:Slider("List rows", 10, 1, 3, 30, "", function(v) end)
plist:Divider("Actions")
plist:Button("Refresh list", function() Lib:Notify("Players", "list refreshed", 1) end)
   :AddButton("Copy IDs", function() Lib:Notify("Players", "copied", 1) end)
plist:Toggle("Auto refresh", true, nil, "repopulate as players join or leave")

local ptrack = wPlayers:Section("Tracking", "Right")
ptrack:Toggle("Track nearest", false):AddKeybind("y", "Toggle")
ptrack:Toggle("Off-screen arrows", true)
ptrack:Colorpicker("Friend color", Color3.fromRGB(120, 255, 140))
ptrack:Colorpicker("Enemy color", Color3.fromRGB(255, 110, 110))
ptrack:Slider("Update rate", 30, 1, 5, 60, "hz", function(v) end)
ptrack:Divider("Filters")
ptrack:Toggle("Ignore teammates", true)
ptrack:RangeSlider("Level range", 1, 50, 1, 1, 100, "", function(lo, hi) end)

local wEnv = world:Sub("Environment", "sun")
local wl = wEnv:Section("Lighting", "Left", "time, brightness, fog")
wl:Toggle("Fullbright", false, function(on) end)
wl:Slider("Brightness", 2, 0.1, 0, 10, "", function(v) end)
wl:Slider("Time of day", 14, 0.1, 0, 24, "h", function(v) end)
wl:Toggle("No fog", false)
wl:Toggle("No shadows", false)
wl:Colorpicker("Ambient", Color3.fromRGB(255, 255, 255), function(c) end)

local wt = wEnv:Section("Terrain", "Right")
wt:Toggle("Wireframe", false)
wt:Toggle("Remove grass", false)
wt:Dropdown("Skybox", {"Default"}, {"Default", "Night", "Space", "Sunset"}, false, function(v) end)
wt:Divider("Weather")
wt:Dropdown("Weather", {"Clear"}, {"Clear", "Rain", "Snow", "Storm"}, false, function(v) end)
wt:Slider("Wind", 0, 1, 0, 100, "%", function(v) end)
wt:Toggle("Freeze time", false)

local misc = win:Tab("Misc", "three-dots-horizontal")

local mv = misc:Section("Movement", "Left")
mv:Slider("Walk speed", 16, 1, 16, 250, "", function(v) end)
mv:Slider("Jump power", 50, 1, 50, 300, "", function(v) end)

mv:Divider("Air")
local fly = mv:Toggle("Fly", false)
fly:AddKeybind("g", "Toggle", function(on) Lib:Notify("Fly", on and "on" or "off", 1) end)
mv:Slider("Fly speed", 60, 5, 10, 300, "", function(v) end):DependsOn(fly)
mv:Toggle("Infinite jump", false)

mv:Divider("Ground")
mv:Toggle("Bunny hop", false)
mv:Toggle("No fall damage", false)
mv:Keybind("Panic key", "k", function(key) Lib:Notify("Panic", "rebound to " .. tostring(key), 2) end)

local srv = misc:Section("Server", "Right")
srv:Label(function() return "Players online: " .. #Players:GetPlayers() end)
srv:Button("Rejoin", function() Lib:Notify("Server", "rejoining...", 2) end)
   :AddButton("Server hop", function() Lib:Notify("Server", "hopping...", 2) end)
srv:Dropdown("Teleport to", {}, function()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do names[#names + 1] = tostring(p.Name) end
    return names
end, false, function(v) if v[1] then Lib:Notify("Teleport", "to " .. v[1], 2) end end, "auto-refreshes: new players appear without reloading", true)

srv:Divider("Automation")
srv:Toggle("Anti afk", true)
srv:Toggle("Auto rejoin", false, nil, "rejoin the same server after a kick")

srv:Divider("Danger zone")
srv:Button("Unload menu", function()
    Lib:Dialog({
        title     = "Unload?",
        text      = "Remove the INSUI menu from the game?",
        confirm   = "Unload",
        onConfirm = function() Lib:Destroy() end,
    })
end):SetRisk()

local share = misc:Section("Sharing", "Right")
share:Textbox("Webhook URL", "", function(text) end)
share:Textbox("Status text", "playing", function(text) end)
share:Button("Test webhook", function() Lib:Notify("Webhook", "test sent", 2, "success") end)

share:Divider("Config")
share:Info("configs save from the Settings tab")

local mine = win:SettingsSection("Showcase", "Right")
mine:Toggle("Streamer mode", false)
mine:Slider("UI scale", 100, 5, 50, 150, "%", function(v) end)

local box = Lib:CreateBox({ title = "Stats", position = Vector2.new(24, 150), width = 190 })
box:Stat("Kills: 0")
box:Stat("Ping: 42 ms")
box:Bar(0.7)

Lib:Notify("Loaded", "INSUI showcase ready", 3, "success")
