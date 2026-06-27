-- ===================== INS ui - Matcha Drawing GUI library =====================
local LIB_NAME = "INSui"

local env = nil
pcall(function() env = (getfenv and getfenv()) or _G end)
if type(env) ~= "table" then env = {} end

local shared = type(shared) == "table" and shared or {}
local function safeWriteGlobal(key, value)
    pcall(function() env[key] = value end)
    pcall(function() getgenv()[key] = value end)
    pcall(function() _G[key] = value end)
    pcall(function() shared[key] = value end)
end
local function safeReadGlobal(key)
    -- must read the SAME tables safeWriteGlobal writes (getgenv/_G/shared/env), or the instance guard can
    -- miss a newer instance on executors where getgenv() is shared but each chunk has a private _G
    local v
    pcall(function() v = getgenv()[key] end); if v ~= nil then return v end
    pcall(function() v = _G[key] end);        if v ~= nil then return v end
    pcall(function() v = shared[key] end);    if v ~= nil then return v end
    pcall(function() v = env[key] end);       return v
end

local function hostFn(name, fallback)
    local f = env[name]
    if type(f) ~= "function" then pcall(function() f = _G[name] end) end
    if type(f) ~= "function" then return fallback end
    return f
end

local iskeypressed   = hostFn("iskeypressed",   function() return false end)
local ismouse1       = hostFn("ismouse1pressed",function() return false end)
local ismouse2       = hostFn("ismouse2pressed",function() return false end)
local isrbxactive    = hostFn("isrbxactive",    function() return true end)
local setrobloxinput = hostFn("setrobloxinput", function() end)
local setclipboard   = hostFn("setclipboard",   function() end)
local base64decode   = hostFn("base64decode")
local base64encode   = hostFn("base64encode")
local httppost       = hostFn("httppost")
local httprequest    = hostFn("request") or hostFn("http_request")
local getclipboard   = hostFn("getclipboard")

local clock = os and os.clock
if type(clock) ~= "function" then clock = hostFn("tick", function() return 0 end) end

local Color3 = Color3
local Vector2 = Vector2
local v2 = Vector2.new
local c3 = Color3.fromRGB
local hsv
pcall(function() hsv = Color3.fromHSV end)
if type(hsv) ~= "function" then hsv = function() return c3(255, 255, 255) end end

local floor, abs, min, max, sin, sqrt = math.floor, math.abs, math.min, math.max, math.sin, math.sqrt
local cos, pi = math.cos, math.pi
local remove, concat = table.remove, table.concat

local writefile = hostFn("writefile")
local readfile  = hostFn("readfile")
local isfile    = hostFn("isfile",   function() return false end)
local isfolder  = hostFn("isfolder", function() return false end)
local makefolder= hostFn("makefolder")
local listfiles = hostFn("listfiles", function() return {} end)
local delfile   = hostFn("delfile")

local HttpService
pcall(function() HttpService = game:GetService("HttpService") end)
local function jsonEncode(t) local ok,r = pcall(function() return HttpService:JSONEncode(t) end); return ok and r or nil end
local function jsonDecode(s) local ok,r = pcall(function() return HttpService:JSONDecode(s) end); return ok and r or nil end

local instanceId = {}
safeWriteGlobal(LIB_NAME .. "InstanceId", instanceId)
pcall(setrobloxinput, true)

-- ===================== small utilities =====================
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function boolv(v) return v == true end

local function copyArray(src)
    local out = {}
    if type(src) == "table" then
        for i = 1, #src do out[i] = src[i] end
    elseif src ~= nil then
        out[1] = src
    end
    return out
end

local function colorChanged(a, b)
    if not a or not b then return a ~= b end
    return abs(a.R - b.R) > 0.001 or abs(a.G - b.G) > 0.001 or abs(a.B - b.B) > 0.001
end

local function parseCombo(str)
    if type(str) == "string" then
        local p = string.find(str, "+", 1, true)
        if p then return string.sub(str, 1, p - 1), string.sub(str, p + 1) end
        return nil, str
    end
    return nil, nil
end

local KEY_ALIASES = {
    rightshift = "rshift", leftshift = "lshift",
    rightcontrol = "rctrl", leftcontrol = "lctrl", rightctrl = "rctrl", leftctrl = "lctrl",
    rightalt = "ralt", leftalt = "lalt",
    control = "ctrl", ["return"] = "enter", escape = "esc", del = "delete",
    backquote = "tilde", grave = "tilde", equals = "plus", equal = "plus",
    leftbracket = "lbracket", rightbracket = "rbracket", backslashkey = "backslash",
    mousebutton3 = "mb3", middlemouse = "mb3", mmb = "mb3", m3 = "mb3", scrollclick = "mb3",
    mousebutton4 = "mb4", mouse4 = "mb4", xbutton1 = "mb4", m4 = "mb4",
    mousebutton5 = "mb5", mouse5 = "mb5", xbutton2 = "mb5", m5 = "mb5",
    mouse1 = "m1", leftmouse = "m1", lmb = "m1", leftclick = "m1", mousebutton1 = "m1", mb1 = "m1",
    mouse2 = "m2", rightmouse = "m2", rmb = "m2", rightclick = "m2", mousebutton2 = "m2", mb2 = "m2",
}
local function normalizeKey(v)
    if v == nil then return nil end
    v = string.lower(tostring(v)):gsub("%s+", "")
    if v == "" or v == "-" or v == "none" or v == "nil" or v == "unbound" then return nil end
    return KEY_ALIASES[v] or v
end
local function normalizeMode(v)
    if v == "Toggle" or v == "Always" then return v end
    return "Hold"
end
local KEY_DISPLAY = { m1 = "MB1", m2 = "MB2", mb3 = "MB3", mb4 = "MB4", mb5 = "MB5" }
local function dispKey(k) return KEY_DISPLAY[k] or string.upper(tostring(k)) end
local function keyLabel(v)
    if v == nil or v == "" then return "none" end
    local mod, k = parseCombo(v)
    if mod then return dispKey(mod) .. "+" .. dispKey(k or "") end
    return dispKey(v)
end

-- ===================== theme, palette, fonts & runtime state =====================
local WHITE = c3(255, 255, 255)
local Theme = {
    bg        = c3(15, 15, 15),
    sidebar   = c3(15, 15, 15),
    white     = WHITE,
    text      = WHITE,
    sub       = WHITE,
    accent    = WHITE,
    accentA   = c3(122, 134, 255),
    accentB   = c3(189, 130, 255),

    tlRed     = c3(250, 93, 86),
    tlYellow  = c3(252, 190, 57),
    tlGreen   = c3(119, 174, 94),

    trackOff  = c3(61, 61, 61),
    trackOn   = c3(87, 86, 86),
    knobOff   = c3(91, 91, 91),
    sliderTrack = c3(87, 86, 86),

    good      = c3(119, 174, 94),
    bad       = c3(250, 93, 86),
    unsafe    = c3(252, 190, 57),

    surface   = c3(24, 24, 24),
    surface2  = c3(28, 28, 28),
    surface3  = c3(38, 38, 38),
    border    = c3(70, 70, 70),
}

local ThemePresets = {
    Indigo    = { c3(122, 134, 255), c3(189, 130, 255) },
    NeverBlox = { c3(82, 122, 246),  c3(120, 150, 255) },
    Lemon     = { c3(252, 211, 49),  c3(240, 165, 25) },
    Mono      = { WHITE,             WHITE },
    Sunset    = { c3(255, 150, 90),  c3(255, 90, 140) },
    Mint      = { c3(110, 230, 180), c3(90, 200, 255) },
    Rose      = { c3(255, 120, 160), c3(200, 120, 255) },
    Gold      = { c3(255, 210, 120), c3(255, 150, 80) },
    Crimson   = { c3(255, 100, 100), c3(255, 60, 140) },
    Ocean     = { c3(90, 200, 255),  c3(120, 140, 255) },
    Toxic     = { c3(150, 255, 120), c3(60, 220, 160) },
    Lavender  = { c3(180, 160, 255), c3(220, 160, 255) },
    Aqua      = { c3(80, 230, 230),  c3(80, 180, 255) },
    Ember     = { c3(255, 120, 60),  c3(255, 70, 70) },
    Cyber     = { c3(0, 255, 200),   c3(120, 100, 255) },
    Bubblegum = { c3(255, 140, 220), c3(150, 180, 255) },
    Forest    = { c3(120, 220, 120), c3(180, 230, 90) },
    Slate     = { c3(150, 170, 200), c3(110, 130, 170) },
    Cherry    = { c3(255, 90, 120),  c3(255, 150, 110) },
    Aurora    = { c3(120, 255, 200), c3(160, 140, 255) },
    Sky       = { c3(120, 200, 255), c3(180, 210, 255) },
    Magma     = { c3(255, 80, 40),   c3(255, 180, 40) },
    Grape     = { c3(170, 110, 255), c3(255, 110, 200) },
    Steel     = { c3(120, 200, 220), c3(150, 160, 200) },
    Peach     = { c3(255, 180, 150), c3(255, 130, 160) },
    Neon      = { c3(0, 240, 255),   c3(180, 0, 255) },
    Waifu     = { c3(150, 205, 120), c3(195, 230, 130) },
}

local AL = {
    hairline = 0.10, card = 0.03, cardStrk = 0.06, tabFill = 0.04,
    text = 0.80, label = 0.50, dim = 0.40, hover = 0.70, field = 0.05,
}
AL.winShadow = { 0.10, 0.07, 0.05, 0.03, 0.015 }

local Fonts = (Drawing and Drawing.Fonts) or {}
local FontSystem = Fonts.System or 0
local FontBold   = Fonts.SystemBold or Fonts.System or 0
local FontUI     = Fonts.UI or Fonts.System or 0
local FontMono   = Fonts.Monospace or 0
local FontWidths = {
    [FontSystem] = 0.48, [FontBold] = 0.52, [FontUI] = 0.50, [FontMono] = 0.60,
    [Fonts.Minecraft or -1] = 0.55, [Fonts.Pixel or -2] = 0.50, [Fonts.Fortnite or -3] = 0.55,
}

local FONT_LIST = {}
do
    local cand = {
        { "Default", FontSystem }, { "Bold", FontBold }, { "Proggy", FontUI },
        { "Minecraft", Fonts.Minecraft }, { "JetBrains", FontMono },
        { "Pixel", Fonts.Pixel }, { "Fortnite", Fonts.Fortnite },
    }
    for _, c in ipairs(cand) do if c[2] ~= nil then FONT_LIST[#FONT_LIST + 1] = c end end
end
local function fontByName(name)
    for _, c in ipairs(FONT_LIST) do if c[1] == name then return c[2] end end
    return FontSystem
end

local ProjectState = {
    alive = true, destroyed = false, open = false, rendering = false,
    x = 0, y = 0, w = 560, h = 460, minimized = false,
    title = "uilib", subtitle = "",
    configName = "default",
    mouseX = 0, mouseY = 0, hasMouse = false, mouseScroll = 0,
    lastFrame = clock() or 0, dt = 1/60,
    inputState = nil,
    drawVisible = 0,
    contentFade = 1,
    tabs = {}, activeTab = nil, activeIndex = 1,
    notifications = {},

    drag = nil, resizeEdge = nil, sliderDrag = nil, scrollDrag = nil,
    dropdown = nil, colorpicker = nil, cpDrag = nil, focus = nil,
    repeatKey = nil, repeatAt = 0,
    tooltipText = nil, tooltipX = 0, tooltipY = 0, tooltipAt = 0, lastTooltipText = nil,

    hoverEffects = true, tooltipsEnabled = true,
    errorCount = 0,
}
local menuKey = "p"
local keybindItems = {}

local Input, InputOrder = {}, {}
-- ===================== drawing pool & primitives (rect / text / circle / gradient) =====================
local function addInput(name, id, char, shifted)
    name = string.lower(tostring(name))
    if not Input[name] then InputOrder[#InputOrder + 1] = name end
    Input[name] = { id = id, held = false, click = false, released = false, char = char, shifted = shifted }
end
addInput("m1", 0x01); addInput("m2", 0x02)
addInput("mb3", 0x04); addInput("mb4", 0x05); addInput("mb5", 0x06)
addInput("backspace", 0x08); addInput("tab", 0x09); addInput("enter", 0x0D)
addInput("shift", 0x10); addInput("ctrl", 0x11); addInput("alt", 0x12)
addInput("esc", 0x1B); addInput("space", 0x20, " ", " ")
addInput("pageup", 0x21); addInput("pagedown", 0x22); addInput("end", 0x23); addInput("home", 0x24)
addInput("left", 0x25); addInput("up", 0x26); addInput("right", 0x27); addInput("down", 0x28)
addInput("insert", 0x2D); addInput("delete", 0x2E)
local shiftedDigits = {")","!","@","#","$","%","^","&","*","("}
for i = 0, 9 do addInput(tostring(i), 0x30 + i, tostring(i), shiftedDigits[i + 1]) end
for i = 0, 25 do local ch = string.char(97 + i); addInput(ch, 0x41 + i, ch, string.upper(ch)) end
for i = 1, 12 do addInput("f" .. i, 0x6F + i) end
addInput("lshift", 0xA0); addInput("rshift", 0xA1); addInput("lctrl", 0xA2); addInput("rctrl", 0xA3); addInput("lalt", 0xA4); addInput("ralt", 0xA5)
addInput("semicolon", 0xBA, ";", ":"); addInput("plus", 0xBB, "=", "+"); addInput("comma", 0xBC, ",", "<")
addInput("minus", 0xBD, "-", "_"); addInput("period", 0xBE, ".", ">"); addInput("slash", 0xBF, "/", "?")
addInput("tilde", 0xC0, "`", "~"); addInput("lbracket", 0xDB, "[", "{"); addInput("backslash", 0xDC, "\\", "|")
addInput("rbracket", 0xDD, "]", "}"); addInput("quote", 0xDE, "'", "\"")

local Pool          = { sq = {}, tx = {}, ln = {}, ci = {}, tr = {}, im = {} }
local PoolC         = { sq = {}, tx = {}, ln = {}, ci = {}, tr = {}, im = {} }   -- per-object property cache for dirty-diff
local PoolIndex     = { sq = 0, tx = 0, ln = 0, ci = 0, tr = 0, im = 0 }
local PoolHigh      = { sq = 0, tx = 0, ln = 0, ci = 0, tr = 0, im = 0 }
local TypeMap       = { sq = "Square", tx = "Text", ln = "Line", ci = "Circle", tr = "Triangle", im = "Image" }

local drawSeq = 0
local function zord(z)
    drawSeq = drawSeq + 1
    return (z or 1) * 10000 + (drawSeq < 10000 and drawSeq or 9999)
end

local function resetPool()
    PoolIndex.sq, PoolIndex.tx, PoolIndex.ln = 0, 0, 0
    PoolIndex.ci, PoolIndex.tr, PoolIndex.im = 0, 0, 0
    drawSeq = 0
end
local function getDrawing(kind)
    if not ProjectState.alive or ProjectState.destroyed then return nil end
    local i = PoolIndex[kind] + 1
    PoolIndex[kind] = i
    local list, clist = Pool[kind], PoolC[kind]
    local obj = list[i]
    local c = clist[i]
    if not obj then
        local ok, made = pcall(function() return Drawing.new(TypeMap[kind]) end)
        if not ok or not made then return nil end
        obj = made; list[i] = obj
        c = {}; clist[i] = c
    end
    if i > PoolHigh[kind] then PoolHigh[kind] = i end
    if c.v ~= true then c.v = true; obj.Visible = true end   -- dirty-diff: only write Visible when it flips
    return obj, c
end
local function hideUnused()
    for kind, list in pairs(Pool) do
        local clist = PoolC[kind]
        local cur, hi = PoolIndex[kind], PoolHigh[kind]
        if cur < hi then for i = cur + 1, hi do local o, c = list[i], clist[i]; if o and c and c.v ~= false then c.v = false; o.Visible = false end end end
        if cur > hi then PoolHigh[kind] = cur end
    end
end
local function hideAll()
    for kind, list in pairs(Pool) do
        local clist = PoolC[kind]
        for i = 1, #list do local o, c = list[i], clist[i]; if o and c and c.v ~= false then c.v = false; o.Visible = false end end
    end
end
local function hideWindowDrawings()

    pcall(function()
        for _, t in ipairs(ProjectState.tabs) do if t._img then t._img.Visible = false end end
        if ProjectState._gearImg then ProjectState._gearImg.Visible = false end
        if ProjectState.bgImg then ProjectState.bgImg.Visible = false end
        if ProjectState.avatarImg then ProjectState.avatarImg.Visible = false end
        if ProjectState.logoImg then ProjectState.logoImg.Visible = false end
        if ProjectState.iconImg then ProjectState.iconImg.Visible = false end
    end)
end
local function removeAllDrawings()
    for kind, list in pairs(Pool) do
        local clist = PoolC[kind]
        for i = 1, #list do
            local o = list[i]
            if o then pcall(function() o.Visible = false; o:Remove() end); list[i] = nil end
            clist[i] = nil
        end
    end
end

local HAS_CORNER, HAS_OUTLINE = false, false
pcall(function() local s = Drawing.new("Square"); s.Corner = 4; HAS_CORNER = true; s:Remove() end)
pcall(function() local t = Drawing.new("Text"); t.Outline = true; HAS_OUTLINE = true; t:Remove() end)

-- slots for "sq": 1 PosX, 2 PosY, 3 SizeW, 4 SizeH, 5/6/7 RGB, 8 Filled, 9 Corner, 10 ZIndex, 11 Transp
local function rect(x, y, w, h, color, z, radius, alpha)
    if w <= 0 or h <= 0 then return end
    local d, c = getDrawing("sq"); if not d then return end
    if c[1] ~= x or c[2] ~= y then c[1], c[2] = x, y; d.Position = v2(x, y) end
    if c[3] ~= w or c[4] ~= h then c[3], c[4] = w, h; d.Size = v2(w, h) end
    local r, g, b = color.R, color.G, color.B
    if c[5] ~= r or c[6] ~= g or c[7] ~= b then c[5], c[6], c[7] = r, g, b; d.Color = color end
    if c[8] ~= true then c[8] = true; d.Filled = true end
    if HAS_CORNER then local cn = (radius or 0) * (ProjectState.roundScale or 1); if c[9] ~= cn then c[9] = cn; d.Corner = cn end end
    local zi = zord(z); if c[10] ~= zi then c[10] = zi; d.ZIndex = zi end
    local a = alpha or 1; if c[11] ~= a then c[11] = a; d.Transparency = a end
end
local function strokeRect(x, y, w, h, color, z, radius, alpha)
    if w <= 0 or h <= 0 then return end
    local d, c = getDrawing("sq"); if not d then return end
    if c[1] ~= x or c[2] ~= y then c[1], c[2] = x, y; d.Position = v2(x, y) end
    if c[3] ~= w or c[4] ~= h then c[3], c[4] = w, h; d.Size = v2(w, h) end
    local r, g, b = color.R, color.G, color.B
    if c[5] ~= r or c[6] ~= g or c[7] ~= b then c[5], c[6], c[7] = r, g, b; d.Color = color end
    if c[8] ~= false then c[8] = false; d.Filled = false end
    if HAS_CORNER then local cn = (radius or 0) * (ProjectState.roundScale or 1); if c[9] ~= cn then c[9] = cn; d.Corner = cn end end
    local zi = zord(z); if c[10] ~= zi then c[10] = zi; d.ZIndex = zi end
    local a = alpha or 1; if c[11] ~= a then c[11] = a; d.Transparency = a end
end
-- slots for "ln": 1/2 From, 3/4 To, 5/6/7 RGB, 8 Thickness, 9 ZIndex, 10 Transp
local function lineD(x1, y1, x2, y2, color, z, thick, alpha)
    local d, c = getDrawing("ln"); if not d then return end
    if c[1] ~= x1 or c[2] ~= y1 then c[1], c[2] = x1, y1; d.From = v2(x1, y1) end
    if c[3] ~= x2 or c[4] ~= y2 then c[3], c[4] = x2, y2; d.To = v2(x2, y2) end
    local r, g, b = color.R, color.G, color.B
    if c[5] ~= r or c[6] ~= g or c[7] ~= b then c[5], c[6], c[7] = r, g, b; d.Color = color end
    local th = thick or 1; if c[8] ~= th then c[8] = th; d.Thickness = th end
    local zi = zord(z); if c[9] ~= zi then c[9] = zi; d.ZIndex = zi end
    local a = alpha or 1; if c[10] ~= a then c[10] = a; d.Transparency = a end
end
-- slots for "ci": 1/2 Pos, 3 Radius, 4/5/6 RGB, 7 Filled, 8 Thickness, 9 NumSides, 10 ZIndex, 11 Transp
local function circ(x, y, r, color, z, filled, thick, sides, alpha)
    local d, c = getDrawing("ci"); if not d then return end
    if c[1] ~= x or c[2] ~= y then c[1], c[2] = x, y; d.Position = v2(x, y) end
    if c[3] ~= r then c[3] = r; d.Radius = r end
    local cr, cg, cb = color.R, color.G, color.B
    if c[4] ~= cr or c[5] ~= cg or c[6] ~= cb then c[4], c[5], c[6] = cr, cg, cb; d.Color = color end
    local fl = filled ~= false; if c[7] ~= fl then c[7] = fl; d.Filled = fl end
    local th = thick or 1; if c[8] ~= th then c[8] = th; d.Thickness = th end
    local ns = sides or 32; if c[9] ~= ns then c[9] = ns; d.NumSides = ns end
    local zi = zord(z); if c[10] ~= zi then c[10] = zi; d.ZIndex = zi end
    local a = alpha or 1; if c[11] ~= a then c[11] = a; d.Transparency = a end
end
-- slots for "tr": 1/2 A, 3/4 B, 5/6 C, 7/8/9 RGB, 10 Filled, 11 ZIndex, 12 Transp, 13 Thickness
local function tri(a, b, c, color, z, filled, alpha)
    local d, k = getDrawing("tr"); if not d then return end
    if k[1] ~= a.X or k[2] ~= a.Y then k[1], k[2] = a.X, a.Y; d.PointA = a end
    if k[3] ~= b.X or k[4] ~= b.Y then k[3], k[4] = b.X, b.Y; d.PointB = b end
    if k[5] ~= c.X or k[6] ~= c.Y then k[5], k[6] = c.X, c.Y; d.PointC = c end
    local cr, cg, cb = color.R, color.G, color.B
    if k[7] ~= cr or k[8] ~= cg or k[9] ~= cb then k[7], k[8], k[9] = cr, cg, cb; d.Color = color end
    local fl = filled ~= false; if k[10] ~= fl then k[10] = fl; d.Filled = fl end
    if k[13] ~= 1 then k[13] = 1; d.Thickness = 1 end
    local zi = zord(z); if k[11] ~= zi then k[11] = zi; d.ZIndex = zi end
    local al = alpha or 1; if k[12] ~= al then k[12] = al; d.Transparency = al end
end

local function resolveFont(f)
    local u = ProjectState.uiFont
    if u and (f == FontSystem or f == FontBold) then return u end
    return f
end

local function textWidth(value, size, font)
    font = resolveFont(font)
    return #tostring(value or "") * ((size or 13) * (FontWidths[font] or 0.48))
end
local function trimText(value, maxW, size, font)
    value = tostring(value or "")
    font = resolveFont(font)
    local m = FontWidths[font] or 0.48
    local maxChars = floor(maxW / ((size or 13) * m))
    if #value <= maxChars then return value end
    if maxChars <= 2 then return "" end
    return string.sub(value, 1, maxChars - 2) .. ".."
end
local function wrapLines(value, maxW, size, font)
    value = tostring(value or "")
    local m = FontWidths[font] or 0.48
    local maxChars = max(1, floor(maxW / ((size or 13) * m)))
    local lines, cur = {}, ""
    for word in string.gmatch(value, "%S+") do
        local cand = (cur == "") and word or (cur .. " " .. word)
        if #cand <= maxChars then
            cur = cand
        else
            if cur ~= "" then lines[#lines + 1] = cur end
            if #word > maxChars then
                while #word > maxChars do lines[#lines + 1] = string.sub(word, 1, maxChars); word = string.sub(word, maxChars + 1) end
                cur = word
            else
                cur = word
            end
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if #lines == 0 then lines[1] = "" end
    return lines
end
local function textTop(y, h, size) return floor(y + (h - (size or 13)) / 2 + 0.5) end
-- slots for "tx": 1/2 Pos, 3/4/5 RGB, 6 Size, 7 ZIndex, 8 Transp, 9 Text, 10 Font, 11 Center, 12 Outline
local function txt(value, x, y, color, size, font, z, centered, outline, maxW, alpha)
    value = tostring(value or "")
    if value == "" then return end
    if maxW then value = trimText(value, maxW, size, font); if value == "" then return end end
    local d, c = getDrawing("tx"); if not d then return end
    local rf = resolveFont(font or FontSystem)
    local sz = size or 13
    local xPos = (centered == true) and (x - textWidth(value, sz, rf) / 2) or x
    local eff = (color == WHITE) and Theme.text or color
    if c[9] ~= value then c[9] = value; d.Text = value end
    local r, g, b = eff.R, eff.G, eff.B
    if c[3] ~= r or c[4] ~= g or c[5] ~= b then c[3], c[4], c[5] = r, g, b; d.Color = eff end
    if c[10] ~= rf then c[10] = rf; d.Font = rf end
    if c[6] ~= sz then c[6] = sz; d.Size = sz end
    if HAS_OUTLINE then local ol = outline == true; if c[12] ~= ol then c[12] = ol; d.Outline = ol end end
    if c[11] ~= false then c[11] = false; d.Center = false end
    if c[1] ~= xPos or c[2] ~= y then c[1], c[2] = xPos, y; d.Position = v2(xPos, y) end
    local zi = zord((z or 1) + 10); if c[7] ~= zi then c[7] = zi; d.ZIndex = zi end
    local a = alpha or 1; if c[8] ~= a then c[8] = a; d.Transparency = a end
end

local function txtC(value, cx, y, color, size, font, z, alpha)
    value = tostring(value or "")
    if value == "" then return end
    local d, c = getDrawing("tx"); if not d then return end
    local rf = resolveFont(font or FontSystem)
    local sz = size or 13
    local eff = (color == WHITE) and Theme.text or color
    if c[9] ~= value then c[9] = value; d.Text = value end
    local r, g, b = eff.R, eff.G, eff.B
    if c[3] ~= r or c[4] ~= g or c[5] ~= b then c[3], c[4], c[5] = r, g, b; d.Color = eff end
    if c[10] ~= rf then c[10] = rf; d.Font = rf end
    if c[6] ~= sz then c[6] = sz; d.Size = sz end
    if HAS_OUTLINE then if c[12] ~= false then c[12] = false; d.Outline = false end end
    if c[11] ~= true then c[11] = true; d.Center = true end
    if c[1] ~= cx or c[2] ~= y then c[1], c[2] = cx, y; d.Position = v2(cx, y) end
    local zi = zord((z or 1) + 10); if c[7] ~= zi then c[7] = zi; d.ZIndex = zi end
    local a = alpha or 1; if c[8] ~= a then c[8] = a; d.Transparency = a end
end

local function approach(cur, tgt, speed)
    if ProjectState.noAnim or ProjectState.lite or not cur then return tgt end
    local dt = ProjectState.dt or 1/60
    if dt <= 0 then dt = 1/60 end
    return cur + (tgt - cur) * (1 - math.exp(-(speed or 15) * dt))
end

local _gradCache = { c1 = nil, c2 = nil, steps = nil, cols = nil }   -- cache the strip colours, else it's 24 Color3.new every frame per slider
local function gradRectH(x, y, w, h, c1, c2, z, alpha)
    if w <= 0 then return end
    local steps = ProjectState.lite and 6 or 24   -- CONSTANT count (don't tie to w or animated bars re-flicker)
    local C = _gradCache
    if C.steps ~= steps or C.c1 ~= c1 or C.c2 ~= c2 then   -- only rebuild when the colours or step count actually change
        local cols = {}
        for i = 1, steps do
            local t = (i - 0.5) / steps
            cols[i] = Color3.new(c1.R + (c2.R - c1.R) * t, c1.G + (c2.G - c1.G) * t, c1.B + (c2.B - c1.B) * t)
        end
        C.steps, C.c1, C.c2, C.cols = steps, c1, c2, cols
    end
    local cols = C.cols
    -- tile strips edge-to-edge on integer pixels: no 1px overlap (which doubled alpha -> bright seam lines)
    -- and no gaps. adjacent strips share the exact same rounded boundary.
    local prev = floor(x + 0.5)
    for i = 1, steps do
        local nx = floor(x + w * i / steps + 0.5)
        local sw = nx - prev; if sw < 1 then sw = 1 end   -- always draw all `steps` rects (constant count, no flicker)
        rect(prev, y, sw, h, cols[i], z, 0, alpha)
        prev = nx
    end
end
local function lerpColor(a, b, t)
    return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
local function shimmerColor(colA, colB, phase)
    return lerpColor(colA, colB, 0.5)
end
local function toHsv(color)
    local r, g, b = color.R, color.G, color.B
    local hi, lo = max(r, g, b), min(r, g, b)
    local d = hi - lo
    local h, s = 0, (hi > 0 and d / hi or 0)
    if d > 0 then
        if hi == r then h = ((g - b) / d) % 6
        elseif hi == g then h = ((b - r) / d) + 2
        else h = ((r - g) / d) + 4 end
        h = h / 6
    end
    return h, s, hi
end
local function toHex(color)
    local function b(v) local n = floor(clamp(v, 0, 1) * 255 + 0.5); return string.format("%02X", n) end
    return "#" .. b(color.R) .. b(color.G) .. b(color.B)
end
local function parseHex(str)
    str = string.gsub(tostring(str or ""), "[^0-9a-fA-F]", "")
    if #str == 3 then str = str:gsub("(.)", "%1%1") end
    if #str < 6 then return nil end
    local r = tonumber(string.sub(str, 1, 2), 16)
    local g = tonumber(string.sub(str, 3, 4), 16)
    local bl = tonumber(string.sub(str, 5, 6), 16)
    if not (r and g and bl) then return nil end
    return c3(r, g, bl)
end

local IT = 1.4
-- ===================== icons (vector set + base64 PNG data) =====================
local Icons = {}
Icons["target"] = function(ix, iy, s, c, z, a)
    local cx, cy = ix + s / 2, iy + s / 2
    circ(cx, cy, s * 0.44, c, z, false, IT, 26, a)
    circ(cx, cy, s * 0.24, c, z, false, IT, 22, a)
    circ(cx, cy, s * 0.06, c, z, true, 1, 12, a)
end
Icons["crosshair"] = function(ix, iy, s, c, z, a)
    local cx, cy = ix + s / 2, iy + s / 2
    circ(cx, cy, s * 0.4, c, z, false, IT, 26, a)
    lineD(cx, iy, cx, iy + s * 0.16, c, z, IT, a); lineD(cx, iy + s * 0.84, cx, iy + s, c, z, IT, a)
    lineD(ix, cy, ix + s * 0.16, cy, c, z, IT, a); lineD(ix + s * 0.84, cy, ix + s, cy, c, z, IT, a)
end
Icons["user"] = function(ix, iy, s, c, z, a)
    circ(ix + s / 2, iy + s * 0.33, s * 0.17, c, z, false, IT, 18, a)
    lineD(ix + s * 0.22, iy + s * 0.88, ix + s * 0.32, iy + s * 0.64, c, z, IT, a)
    lineD(ix + s * 0.78, iy + s * 0.88, ix + s * 0.68, iy + s * 0.64, c, z, IT, a)
    lineD(ix + s * 0.32, iy + s * 0.64, ix + s * 0.68, iy + s * 0.64, c, z, IT, a)
    lineD(ix + s * 0.22, iy + s * 0.88, ix + s * 0.78, iy + s * 0.88, c, z, IT, a)
end
Icons["eye"] = function(ix, iy, s, c, z, a)
    local cx, cy = ix + s / 2, iy + s / 2
    circ(cx, cy, s * 0.15, c, z, false, IT, 16, a)
    circ(cx, cy, s * 0.05, c, z, true, 1, 10, a)
    lineD(ix + s * 0.12, cy, ix + s * 0.32, iy + s * 0.3, c, z, IT, a)
    lineD(ix + s * 0.32, iy + s * 0.3, ix + s * 0.68, iy + s * 0.3, c, z, IT, a)
    lineD(ix + s * 0.68, iy + s * 0.3, ix + s * 0.88, cy, c, z, IT, a)
    lineD(ix + s * 0.12, cy, ix + s * 0.32, iy + s * 0.7, c, z, IT, a)
    lineD(ix + s * 0.32, iy + s * 0.7, ix + s * 0.68, iy + s * 0.7, c, z, IT, a)
    lineD(ix + s * 0.68, iy + s * 0.7, ix + s * 0.88, cy, c, z, IT, a)
end
Icons["settings"] = function(ix, iy, s, c, z, a)
    local cx, cy = ix + s / 2, iy + s / 2
    circ(cx, cy, s * 0.17, c, z, false, IT, 18, a)
    for i = 0, 5 do
        local ang = i * pi / 3
        lineD(cx + cos(ang) * s * 0.25, cy + sin(ang) * s * 0.25, cx + cos(ang) * s * 0.42, cy + sin(ang) * s * 0.42, c, z, IT, a)
    end
end
Icons["folder"] = function(ix, iy, s, c, z, a)
    strokeRect(ix + s * 0.1, iy + s * 0.34, s * 0.8, s * 0.46, c, z, 2, a)
    lineD(ix + s * 0.1, iy + s * 0.34, ix + s * 0.1, iy + s * 0.24, c, z, IT, a)
    lineD(ix + s * 0.1, iy + s * 0.24, ix + s * 0.42, iy + s * 0.24, c, z, IT, a)
    lineD(ix + s * 0.42, iy + s * 0.24, ix + s * 0.5, iy + s * 0.34, c, z, IT, a)
end
Icons["code"] = function(ix, iy, s, c, z, a)
    local cy = iy + s / 2
    lineD(ix + s * 0.38, iy + s * 0.26, ix + s * 0.18, cy, c, z, IT, a); lineD(ix + s * 0.18, cy, ix + s * 0.38, iy + s * 0.74, c, z, IT, a)
    lineD(ix + s * 0.62, iy + s * 0.26, ix + s * 0.82, cy, c, z, IT, a); lineD(ix + s * 0.82, cy, ix + s * 0.62, iy + s * 0.74, c, z, IT, a)
end
Icons["sliders"] = function(ix, iy, s, c, z, a)
    lineD(ix + s * 0.14, iy + s * 0.33, ix + s * 0.86, iy + s * 0.33, c, z, IT, a)
    lineD(ix + s * 0.14, iy + s * 0.67, ix + s * 0.86, iy + s * 0.67, c, z, IT, a)
    circ(ix + s * 0.66, iy + s * 0.33, s * 0.1, c, z, true, 1, 12, a)
    circ(ix + s * 0.34, iy + s * 0.67, s * 0.1, c, z, true, 1, 12, a)
end
Icons["shield"] = function(ix, iy, s, c, z, a)
    local pts = { {0.5,0.12},{0.83,0.27},{0.71,0.78},{0.5,0.9},{0.29,0.78},{0.17,0.27},{0.5,0.12} }
    for i = 1, #pts - 1 do lineD(ix + pts[i][1]*s, iy + pts[i][2]*s, ix + pts[i+1][1]*s, iy + pts[i+1][2]*s, c, z, IT, a) end
end
Icons["zap"] = function(ix, iy, s, c, z, a)
    local pts = { {0.55,0.1},{0.3,0.55},{0.5,0.55},{0.45,0.9},{0.7,0.45},{0.5,0.45},{0.55,0.1} }
    for i = 1, #pts - 1 do lineD(ix + pts[i][1]*s, iy + pts[i][2]*s, ix + pts[i+1][1]*s, iy + pts[i+1][2]*s, c, z, IT, a) end
end
Icons["box"] = function(ix, iy, s, c, z, a)
    strokeRect(ix + s * 0.18, iy + s * 0.18, s * 0.64, s * 0.64, c, z, 2, a)
    lineD(ix + s * 0.18, iy + s * 0.4, ix + s * 0.82, iy + s * 0.4, c, z, IT, a)
end
Icons["home"] = function(ix, iy, s, c, z, a)
    lineD(ix + s * 0.5, iy + s * 0.14, ix + s * 0.15, iy + s * 0.46, c, z, IT, a)
    lineD(ix + s * 0.5, iy + s * 0.14, ix + s * 0.85, iy + s * 0.46, c, z, IT, a)
    strokeRect(ix + s * 0.27, iy + s * 0.46, s * 0.46, s * 0.4, c, z, 1, a)
end
Icons["star"] = function(ix, iy, s, c, z, a)
    local cx, cy = ix + s / 2, iy + s / 2
    local pts = {}
    for i = 0, 10 do local r = (i % 2 == 0) and s * 0.44 or s * 0.18; local ang = -pi/2 + i * pi / 5; pts[#pts+1] = { cx + cos(ang)*r, cy + sin(ang)*r } end
    for i = 1, #pts - 1 do lineD(pts[i][1], pts[i][2], pts[i+1][1], pts[i+1][2], c, z, IT, a) end
end
local function drawIcon(name, ix, iy, sz, color, z, a)
    local f = Icons[name]
    if f then f(ix, iy, sz, color, z, a) end
end

local IconData = { ["target"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAB0klEQVR4nO2Y8VHCUAzGv3r8ryPgBLIBZQPdACZQJ8ANdANlAtmAMgF0A0bQCWoezWGtpMlL4ax3/d29612bl/eRvqR5DNBxBug4vcC2dF7ghfSgKIopjU0hM4UR9iWxafKVSA7p8gqFhICBoMJgdkfulvWbUgTvobOGHYvt/NhNKYLVX/xJ44nG9sfEJMkQAblMa7dG7Pey4jPxCHykeS84A7TMA12eD2KOCLRk8RbnQ/Xd18G2nEQg7aWw4ccoN34gvLo1banW20MSOENZB9dN2UrCrlBu8qnw/A1lkn0cex58k00oQWNe87cNnLC4Fb6jJhGiOJFEalzATyg9mjiwjbtMuSLIe26DOK4pijtE4o1ginhu4cCbxZZXW2cIB/+3H1Tw1LcdHHgjmCGeJRy4IshfiEXElIUng/drwQkX6ozGjWKa00hPWqgrZ4iVNJEXTNEcyYUmLqzRdMaxNKwTrXsm8yHKOldtFpbaa+Uu+xAEb8OqwkLO0nX3DWtbLGXG81mzkmoGlgjOOWnqx86Yc3FIiHHtVgrD+VvK4iBGq28ZiZzAJm4FPVo5+RtZBYaS8Q6FP/vrgw3DGSGHzAx2mmxzSdxeCzpOXwfb0gtsyxfbX+Kilrt4bgAAAABJRU5ErkJggg==", ["crosshair"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAADMklEQVR4nM1Y/3XaMBA+8vi/bBB3gqQT1J0AMkHoBJAJSicITFAzAXSCOBM0TFBnA5iA3odPRIiTLBvxXr/39Kwn63Sfdbofcp/+c/QpIfb7/T2evV7vjRLhhhKByY358QdN+kmQjCBjbPVHlAhJTWxhQInQowvAphzyA+cul6chtuWGc1jiyWfyN3VEa4JMCiQmVJs0ixSruBXcFkx2Sy3QiiCTw9l6pnhiLipuT0xyHSsQTZDJgdhUebXjthbllYxl0vBBnxSZOZN8olQEmdwvOvVS4JXbjBWVDbI55nH76rwqWPY7XUqQFcypPnMG2LFxGzPJOtjNgk53FGdySl0JyqIrOiWXd80UkmlKh+RD6GN7gcXgrcgMWQpyAZIVty8+7w5lkimdeuvYRw5KuU1wVqVNTF52IWuMraGMdOer5/tesIK/9EHwlRfOlTnY5Wc6dyCDguqwslVkS/pwnIrnfNYWuPGQG9Hp7s1IJ/cSIEfy7kXmuphb/Ux0xhGkOm0Z7DyhZO7Mo8Bac3dQHGPnzIsmmFv9Mw+T8/VI8XhkmUwZX3t0HnFjKcUiMAfMdmfNqRS5nNpDM2Fl9e+MfnAxg30hhx0pSEeljMWY1kWmjNnOg3OaSz9nTht4/LXqwWQ4mFhiE/Ii6jbkWPvwZopcl2BdKWO2d+9ENzg8mJh73EEeKEjM7MSoTFm4pPbQ0llm9d+0WOvz4tLqD92X8nVLiseSZSplfOjReYSPoG3CgZRMLpCeNtSMDSmpTNYceHSGCUoQfbeGfihz4IE5hXcS73JPIWCv+e6raEK5eOYs4i2LJAgjzpnwg91Ye8yqlXE/ee6MWhIciKJbGcIufEtUbiEZGPPCUvetyy0RsM/OoTjwlVEdyQHT0E0v+GdBTLqgc5Ijak9upJBbNF0dGn99yJ1h6ZBcSc7Mm+QxR/L7ik7JLZvuIwf9FAnl8mQA84SunQNFZhFDrhVBIQmFIHpL3QCHmF7l4m4g3o2vH1M8URArqL6wb6kFLv15ZGJfLk9zU0PiRzgqqc6x0TuWlKANp8BQL1ldcK16sJUZQ0j5h7Xw9C9CMhMD1/iJnpTgNfAPyQ1XINTuz3oAAAAASUVORK5CYII=", ["swords"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAADGUlEQVR4nM1YsW4TQRAdO1FEFQIlTSwRatJScWlRivwBxx84X5D4C7C/ALuFJgWijVMhKpI+COcHgNAQIUXOG9/a3tubm9293EV+0mh1d7Mzb3d2ZndvnVYc67TiKBCcTqdbaF4KuletVmtCNQA+Omi2hU8X8PHHftFyOh6jOaJy9GHgkO5H7j2arqLSg49jcgmamftNfgxh4B1VAHx8QJMGqD6Zz2TberlLYUiNoyhEkMtxaVM1RJGMJJeDjyCvtz3ISPgWRFIhNzK21TXtKzPnWAtjtGM44ue3VCRJZWtSI4c+qdEhDb4ZXBAyBoNn0lSElBRyrg8JdhZ30PwUdHJZC71hiVFXjyvClkZOmeFiFpsiPBCUczMUMZPXVI3cwC7WuRDjQzfEeSDJA8iVIdoLJDcyHJacBKWYMAbpOba9iWNDTJLQMDaYOEsupKDumQxJHBdqmWlgJtXEiSbYAMnSxCn1T4FoMnE0BB8W6g43bwyQI0hCml+KRB0zSdmGcErLhDlE3z7FEDQHWD79diAnMDCokeR/yIb1fIZ+iaCnnmb6lvEEznbnzjmMIacbRW/DeZ5QCbQ12BGcR681RW+OC1LuKBrBE6ru3K1/HyG3gt4lJHFvcjYa30kgnyCfBV//IM80cl6CNZHkmVtz3v2FbPvIMUJ3kkvhU2i414R3m5RVCC+8BA2JnZLPTHJRvwISwu3rvXS5fxa49s3DxI54lCn5sTiiczlC842KpYTDuin0HVJ2s1v4tUPvEuTqnpjHX5CngkEO945E0NxrvlPxSDVLCMrXVhu2rzFs7c0/tC1yHYsckUyOR/eC8neXnjXiVCDHA5plq7IEbF+JieQM7gyyo8ckw730zIzY4TAb/6nVh4twoc4pGc+4hn4pQV4/XyGPnE4cguchZQE2eFfgc98E0pX6mMH9oGKUbiCv0OdcJGg6vyG5sJaeOGJhBuGWGd609+Hji/2yUGaMwj5lo7Hhnb174EYiN+NT1sOEe0zZmjyDHISEOAQmxLzXv6bs+J/YYQ0iaBuri1gV29En6ofGyv/lvwPj/9coBGLaTwAAAABJRU5ErkJggg==", ["user"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABjUlEQVR4nO2W7U3DQAyG36AOUCYgTABskA2ACegIYZNugJgA2KAbQCboMQHpBMFuXLWq2vuw0yg/7pGstLmL7tF92TNMnBkmTha0kgWtDCbYdV1Jjxv5+1sUhcMAXMEIiT1RrOknx0pize+4DUYKGCCBN3osAt2WNJuvUKKeQZKrEZZjaumrQjWDNOAc/ZLOIz9pKW5pJlskop1B3luxcpC+qv2oPcUl0imhQCt4j3Q036iX+AfpaL5Rz+Bogup7kE6ywz5zhGjoBI+6xAyfyk1EP+6zgBK1IM0IL1kFvyS3VdJXhSkXy8AlBaey5qCpkXelRW47BiZOLlitmASlSL3DPkvsnrt9t4KxeE3egyT1iP6KqRCfXx162U+S/UICUYJSXr1Q1FAm/QMcxZLiPab8CgqSHC/bxwBixziK59A15BUUuW9clgefZEjwD2mFqYaWBK/PNZ7NJDJ7l5Zj5jLWSXzXzBhywbEmf1H7igWHuHLKykbGOknokJQY/no5xvkyTa5mrGRBK1nQyj9JfnKIuCLRswAAAABJRU5ErkJggg==", ["eye"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACl0lEQVR4nO1Y4XXaQAyW8/K/bFB3gpIJYiYoTFAyQdMJ4k7QMEHMBIEJ4k6QMAF0A5iA6sOye3F8J9nOy+OHv/cUBSzpPutsScclnTku6cwxEOyLgWBfvAvB4/E4ZvWp9vUhiqIX6omIOkAIfWNJRELIRdZdCLciyMS+s7plGVM3gOA9E11aHUwEmVjC6jd1J1YHiP5korlmqBJkcg+s5mTDX9GfjfYZk7wJGVz4LjCxEcsz6eSwXZOoQCyCG5/ItRDmWANr+QwiHzlWTxTeUmRrqj348kKtKJxVxMBN7kkjaCS3YUmaAnpIImbO8pVakmwi+MhqSmFcuZljn5jVHUvsLLZgm51jgxt+VuKu2GfmJchBQOxRCfKLg6SOz5zVg8f2hm0zxxZ+dxTGjH1WbwjKNmxZRkqAL2VmpPw8KfaTspxIpreK/V7WOG21+xbfGsht3G0THw2VjfhuFPvRKx/8aZG9P7xIUn5gvyMZIGWn9MlZXSsuVRYvHNYauY9ExedEUFK/pvbQtstqU8eyfJTcZ/De4Hhdq/oWn8pGfLXtBbLyn4qgvGkLg/PU8cko3M6Wbpkhvb4CC3eIqNdB3CGKbKgt7ago1HvHL6WiZ5d+aINZrV4iNgp1HIgNv7Ebu6mToOLn9HZCdtE4hUido1opKq9pU9GBivb5qrf7hgVLW1JHpRbkgKumwaNx3BJD9MQD+YFRaSvdxEcsgQ3pmZv5pqLgwCqZzCg8hQB4ZnIqnl8AfgkZOhPLPDSyWSZqLJKy/KD3BSpGqo1s5kOTZDOl4jTXB2sh9mIxbn3slDcVzRw1zXr2OJUdKl6sHbVAp3NxCdn+hP5P37HonWhkKbdO3k3oRfAjMPx41BcDwb4YCPbF2RP8B6CM/vT50VvlAAAAAElFTkSuQmCC", ["monitor"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABL0lEQVR4nO2YgQ2CMBBFr8YBdANGcAN1Ah3BDcQJ1AnUDVzBCcQN3EDZgA3wH7aJIhDhYsHkXnIpVggv9Lhw7VPH6VPH+S/BNE0nGGaIEbXDFXEyxkRuwrgDyIUYdtQNVpDc80EmCLkAw426xRCSiVvioOCEC/llnPvNaRaVvSTT1zzwgc3/c36+V3Syb7mqe2odlKKCUlRQigpKUUEpKihFBaWooJTCD1Z83Q7IM7Yv+qDsCZ5xAXdVd/JDgAiL/nCCSW6eG5YjtUvmlC0x+gFumH13cVWcrNNbDs4RB0RM7RFbh4WbMCSkrF20iNtXrYNSGi2xrZNrer7tAyrfDeNET+y45b0W8iTINXJJ9ThAMKx5jdclrv30mKaCGzt+u9EZIfbUAHGZ+TVaZqQ8AFdjQ0+y/ANkAAAAAElFTkSuQmCC", ["palette"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACqUlEQVR4nO2Y/3XaMBDHv/D4v2UC3AmSDeJOEDoBZoKECUInCJkgsAGZIGaCwgRVJyhMQO/C+SGrkixLcZrXl89794z1i69POunsAd45A7xz/n+Bx+Pxii653GZyVXLdkm16vd4ekfQQAYmaiKgx2eeALiXZmmzVVmwrgSQsp8sdzh5rC4tbkD2ECg0SSMLYS/dkBV4HRfaNRG6bGjYKFHHPZJd4feYk8ruvgVegiPuJsHUWy4xELlyVfVeF5rkuxTH39F+Fq7Lv6wj/tM7IhmRfyJ4s9U9SN5S2Ph5JZGarsE6xROsz3PB2UWjt2cu84EdS9IvsUo9UarOky8QzZkntv5qFLg/ewU+p34gQpRUpyzZSwk9ODzFGk0BZDzkaBjP6sAdHWtFIypx9HBRoEhg40IQE3LAIWTuPOB9zkN8v60ra3MA/vRXX5oP9tQapwW90H7k+eANfVzc1D0pw2MQdyDZkO6Szk7EOjvrazmFOcW7pwANxROZk3HmKeKY8Bo8lQg5NHfpoZkEDquqGfi8R58md9K3GUTglDiY1D5r5YGbpoCxlMfndPrCslkCEeLAWfRK1F2jPheW0uLa0U/rNwFcp8AbKpwpHFgfQLeKinPv8oLF4WtlzvCnnlnYlPAJd5IhPUnVY5NxTv9HXO2NOcYl/y61ZUBNI6ksEhH5HzGwZti1I1nh7Vq6k1SawxNvBszXVUzcTVz5Y0uUK3cH54hKnQ8C7p8YmrKHwsaiMsn3I21yF86UpIAMOYZjyVYHxnSQc8qnZyxyJhLx2KrJPiP0DAgn0Gwbn6cmQ4EnX21oojcmCiMzJVojAPLraEpLNvIiUvYpfCzcI5wGJxH5+K3D+/OZan/wg49QoTlrAjOyZnAVzQGU4pVJbPXtOIVlg13x8RE/lD10o3SFAI/ONAAAAAElFTkSuQmCC", ["settings"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACVElEQVR4nO2Y7VHDMAyG33D8ByYg3aBMQJgANiBMQJmAMAF0gnYD2gloJ2g7QdMNYIIiEfWucWXHTvp1PZ47Xe4ix1ZkW5J9jiPnHEfOaRu4XC4v6fFK0rY0mZK8RVH0jZpEaAAZOKDHfUWzIRn4gJo0neLrLbWx0tSDS5925MHa45yhJrL+tt7W5Kyi45Tki6RHYm6EkHX1YPTblj6579T1YeQwjg2aGK9HJH0ZMHThD0RSksTQ3dAqmCLQwC+lo10xIgPvNIU6xWQceyfB/khkzA02PCgLmqc2xn7JyYst86XmwQ72bxwTk3My82XJg+K9OUloWBij2Dz5ajAUm+EWYXBKbK2nRtNAbedW8UQd9jWFrCvWXcCf0o4uTbEouvDnxWac9LcKK750zXCjhhnPP19QZzE88CgqfkhS+aESapiRhjzdM9j5gD99h47HaGvGMdZURx/kKCK/jSn8yR26gYylcvQVtdWDtG5iuNdNG/7EDt29jKXiSnWTCiOe4c+jQ/cX2mypbsNAavhOj09UB2uO/J2KNqufrap8eKxPGbvENgJ1hxZ512FcD2GZqbW+abRUx8qQyM+MoKe6BGFwPIytqQ6FkRmKo+Qh4CNqtv7CVm5xjGt0GquBmpk2Nom4t3Lx7wB1TFfJP0J4uVSXMTkm0RSuU532R1z3PZEMEc5Qvh0rutT2kfNALUdClpzkY70UEl0PfpRqRglnq8q97yzZUBNJT3PP5ld1L5BO9+pDWHi0maEBTQ2cbqmNlaZTzEE9g/sCMzvYBeY++L9Eb8ov04vnmGZXJSUAAAAASUVORK5CYII=", ["sliders"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABa0lEQVR4nO2YgU3DMBBFf1AG6AhhgnYDnA0YgU5AR4ENGIENaDdIN/AGwAThrBgpRL7Qsy8mVH6S5TiJ7eudfT9ujZVTY+UUA1NZvYE3yEDf9w/9wBuEVMiAs2zUbKuqOl7Ydf0hDnqQfvCOqkcqDeI4k5cOo/HGHuyofEzet1SeqU83HYjzoFsrG8Qzt3R2zH1D5XZ6s46YYCmCc3IGGiouRA3i6GaenREO8VPo5bKLU8mSqIm9r08S7znEIfZqYNykNNkLFkZkIBlnMKSgoTOBhfmfXzMzSsImb+rj0sQWcVgwSsJJ3TsuUJJxiKnPkao7xGNpuOtXEudVLoxz6vEbFhpKUnZxAJGSeBU4+eYeGVALkU9N3+FvQykjBk0tdptq48sBSmiuwYa5TkKqJD+gMLbMo63wiGlRlCSdrGeST8iUxWLpM8kkxO7L2UABzTRjmesktBP1q2/eayXqv9gMIsofmKkUA1P5Am/6eNUAfuXtAAAAAElFTkSuQmCC", ["shield"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABkUlEQVR4nO2Y7VHDMAyG3/T6n45gJqAjtBPABrgTMAKwQdggbEA3CBvABJQJIBME6aL8AeIvJbnc1c+dLpdasd9KbiN5jYWzxsI5H4Ft2xq6XMvtsSiKE0aggAIStUEnypLtfg2/sJHQZyhIEkjCdnS5Jbsh23jcv9GJfSKxb4gkWKCkkEVZMoM0TmQlIraAV6BE6x5/U6ilj2rtcnIKJHH8be8wLY8k8mFocFCgpPQD83A5lPKV4yGD+TBDA/lNoiUL1JIFaskCtWSBWlzvYq7zvjCHCGJobOV4iAvNT0yPcw1XscDUmJ7aNbh4gSEVNaf6AtPQ0FZy9jS+CDIVpqPyOYRE0NCFu7Gxo9iQbX3NkzeCMkGJ8SlDOruYtpOjeIVxeCdx2xDHkD3YY9GlRUsjcwURLFBOBSz02JgThpgIskhutg9I5yBzhK+JBGg/8v6pEf7L5rTuUs5moiLYIwsZsmOAO/uYFHFMkkCGiwkyPt3ak73+48Kf7dlHCo+0dTAS8odu5bZaxAHmHOSSX8sPoqdhh7W2pFsAAAAASUVORK5CYII=", ["folder"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAA5UlEQVR4nO3Y0Q2CMBSF4VPDAG6gIzCCIziCbgAbuIFxAt1AN8ARcBM3wNuEGNqQiD2Q3of7JaSh4eEnTYBSQLkCylkgywJZo4Fd121l2GCal3PujYW4eELiKhnOmM7HnSTyggUEgRK3k6FBmptEHjGzVXS+R7qD3OAVM4sDS3B8ZKq7HOWvwJz86jUSuR5Oagr0fFw1nND4HAyWWWNgsMT2qmNZIMsCWRbIskCWBbIskKU+MP6ibpFf0BAHPpBf0BAEyr72KUONfOq+4cuNXdXvrNgt6L/asV8oDsrZY4ZlgSz1gR+92GNIRtdWlgAAAABJRU5ErkJggg==", ["code"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABW0lEQVR4nO2X0XHCMAyGZR/vpRukG3QD0g06QtigI3QTugnpBG0nKCOQCVyJ6sGAQyQL5/Lg787nxOff+jBHHFawcFawcKqglSpopQpaqYJWPCgJITTYNqCEMpQFJSpBLPCM3Re2Hq/3ihzN7SnLa4hx0om8MBVa89DgnFsLsyG6PWJ7wey3JCvawYQc8QZyttE1rbGX7uSk4IjcFnfgA4Tw3CxJX1rOKunnkLNI+rnkciX9nHI5ki4h+ItdA4XkLmp12O2ioQPWeornpL7iS2n1qaFgM1E7KfiKbYjuO/ykO7gzvGYXDQ1c+4wrQX7Ct1BQckSuTZ0uyV9xSUmN3KhgKUmt3E3Be0vmyE0KTki+gxCe24FS7lQfhPBDtMf2wENHLPAozIYcOUL8wprYyR+Q8wkZcqe6oIRf2xss0itilGvh/6Q4KGJ6wbmpfzutVEErVdBKFbSyeME/RofOMy1Qvr4AAAAASUVORK5CYII=", ["zap"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABnUlEQVR4nO2Y4U3DMBSEL6j/YQQzAdmAsAEjsAHdgG7QjACTECaATgCdAJggPLcOMiZW+/yuUn7kkyyndpOcznkXKwtMnAUmzizQyuQFnuEE9H3fSvuUdgEjFciIqFq61/DzsqqqDxg4hcBn6ZrdxQUYoT6DIu4WQZywAQF2kayj4y8QoAkU91bSuWioAwGKwFCt98nwpBxspaWR8gYC5ipLYiXGHDEehsDfWPlzYULEeExLnMRKDCViPNZncJ0ZF+39dWZuI+YeXUDFyxBi5QF6bkRgd+yfiwSGWHnH/8o9xIuIazQnlC7xCnpxw3kq1A6Kew5797Q8iXt3UFIicDRWDvAtrS7JRdUSh1BuoKctDW2Vg6E46sy0f91djYxvsXev6N2scjDcpBub88GXOW1ZKm53T5DICFTHSgpru+UyU0sYYW233MiYjxXzloslMC0cHytm9zwsgelbpbUURgylSOQZ7KQbdi9bEedAguXgeXRMWdoBloNDxJhjJcXsYBIxVPc8jCX2xeCr9pERKyn0bzNs5g+YVmaBVn4A2WB+p41hgdoAAAAASUVORK5CYII=", ["box"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABOElEQVR4nO2X7Q2CMBRFb43/cQMZgQ3sCDqBjuBIOoGO0BEcQTfQCfA2oNZa1ORhK0lP0vRTe/KARxnjzxnjzxmmYF3XS1aapUQcjixGKbX1J5Q/QLkdqznSsKfkwh0YuR3KrZFOzjJvHe74l7hy2heWA+Jg9y2c9h1fsHTaB4ZbIwKMmmE1CzjkNCNm0IIF740Z4lB0TfiCBo+btWr7sTFu5ylRM2IlmtRSIA02tVXMHsfbwFOibic00qFdOYsKrWIkaySAci8+Oc1IyYJSRpCxVR+wayBA9BSHnrq+/08UQe6r+1jzjj7yoPkwr/EloQjmRC0lC0rJglKyoJTBHhYuiE9wzy5Bg/iY0GDXq65sfzBFHE4IfDBZOo9LlJywWqF52U/wG85oArGh3Dm04KvzXEpympFyBbWzVjAPa8AQAAAAAElFTkSuQmCC", ["home"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABV0lEQVR4nO2XjW3CMBCFnysGYIRuUEagE1TdIN2go3QD2KDtBAkb0E2yQfosXVRo/s65AyLhTzoZcTb5dHEOZ4WFs8LCyYJW7kuwaZqXOIYQvuHEA5yg3I7DVwz57EKAEcqsOXwytv9SFeOV1axhwCQociVjMzDlyHi2SM6+xZSLUmNykFwpc2cxq4IncmvlkljBWMkjEkmuIOW2SJODzC1lbRJJgrxAgXS5llaySFmkFpQf9mgfuxRJ1R6UvlbAlz335NvUpMkKXkguUmga+mAFRxqwNxVGGnqvoKIBezPY0Du3+AZywF9D73SHvj34iOvKtWzk2md0BGO3DyfwqwMuxyGc0/mnySdqKx6CP4z3gdwH4wkGPARr7p2qL8Gn0nRYjeQ9aCULWsmCVlzaDOYzuVZz5N8b8mM5TV595I8njb4XpXrqVdKyVi14S/JTbCULWlm84C907Xp979DbtQAAAABJRU5ErkJggg==", ["star"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAB2UlEQVR4nO2Y0XHCMAyGlR7vpRMQJmg6Qc0E7QiMACMwQVeADcoE0AlaJiCdoHQC+usqrhRsx7INl4d8dz4H25F/ZEV20qOW06OW0wlMpROYyg1lYr/fVyhbKRVloqBMQNQKlZGf66IoRpSBLALFY+8nzQ8Q+UGJ5FriSWCbmmQPwnt9VF+Wrh3KEF7cUQI5PDh2tPc9fcHk8OAWVenoruHBISWQ5EGIeya3OKaUMdEEeRCTlKgGh0npTxRP3pTz+El+Pbo+xOQmJD4Lj6gXyvQkNsAi5xA7tXVaBUKcQbWi62LNm64Y5IHfdD14rtrWYRUosWHoOiJ5DuOKR+dTLO4uUTZ0Odh25dsSvWnmyJNvlB+2yZ6rfYMa8yCLRDG4XFA+FmwzJM0EJ2oYG6OaUjozsRU2LylBCuKk+0RxLCFOtbPEHPnvKZ6BcrzOg56jlYY7zRFMe1gwlI7RDG69QG0MNp1cDjvPbYKNf2g9+OjpW8rklVzH2DgjWKCccGx8oow4ffCuIIVTyUj6NLbiBdJ57PByctItUdang6WNvTkLsOUkOM3IqZo3dY4vXsJJ0z56cu+cfpeX/1gVem/MTlLFvpDLC36tyYPZPn1ciu7zWyqdwFRaL/AH0duIDzY4li8AAAAASUVORK5CYII=", ["skull"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAADMElEQVR4nM1Y63HbMAyGe/kfdYIyE8SeoMoEcSaoO0HdCeoNKk9geYI6E0SeoPYEVSeoM4EL2NAdDYIvWZfLd4ejCILgxzeoG3jnuIF3jkEJHo/HgtLRaHSAgTCCnmAyX1BKlIJTGw3KgdN1X9LZBJGYweQHypSJpYDI1ShLJNpCBrIIIrmfmMzhOlRI8nuqcRJBns4XlDEMgwblKWXaowQTyK1RWpQdnKeSULC9gfM61UD2DzGSo57kXlEqOE/XIcHHnOUWMknGCNbgjsBflCk63UEG0Bd1slFI0g6fQS5BdvhbqPcoZd8jg0ezQbkXRRNfh0MEaWpLob7LPSYUvwaTP0LdoN8Hzf6Dx8kMXHLLa8kR2MdSqEtu04FKEFxytCkWMBwW7DPU5gk+gp9Fvh70fj37qiNtnuAQ5DVihLqB4dGIvOmCDRvaCJZSgT3edN/UAZQVbSKWFXfqAordtwhBtW0t3DIiv7UbBXcHEqZYNuk2kcfutBHQZkIZmmbMk297aulo29iVtBEMHcALj74QZT67MZIKBRtO2xrB0GYw1vcWrNEVZdJub+Wn4IfTdkpE/cmjv4U0kN3RU3YPEaSMoOFrj9Ba+jFcBhGt51u1Y59FpG39qsPKtBbs3p0udF78VCZHjw7dsdgkQTslENmj3gnpfAd1LfKPdEYxAXJCMWC3Btc2OULMjs+7x0ibZ1+akh38E2rvhW7V6UYk+EjyBCIftTrqCLLhs1DTOVaBH9RoxfICfnKVQu7Z16FQuGVAX0dP9s3CtjNMVsLuK9rVwo6OmF/C7mL9JhMMONx1t4FlR4GtXOAt2t0l2DkdtuHbJCdwRTn0r4rpWNEZRSfrHkLkCEGC2OMS3LNKW4fLRF0t8gW34UWffzNOSISjMOez07CqleuvL1LexTTF2nORgtglJIBDrRkoz1f0UYTqBqeYUSs6aqiKTQ+TI5sK9HVaxeqnEFzAZTRio4Q4fDbkM0ow598M7Tb5bmgg/hwowSVJV990kH8zNpBoA57HTQa2SKxMNU6ZYhstXI9NjnHuCBrQr79UqCFVCH3/sC5AvylC2CC56KaQ6P2P+q3wH/rMb9XrhmAmAAAAAElFTkSuQmCC", ["gauge"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACWElEQVR4nO2Y7VECMRCG9xj/qx1cB9KBZwVgBaYDsQK1AulArECsQKxAqYCjA6gA3+VyM3u5JCQXYPjBO7OTIyG5J7ubD7igE9cFnbjOgKk6A6ZqL4CbzeYKxY1RvcyyrKREZdRBGmgAG8IK2JXjqyvYDDaFfQF4RYcE1GCPsJEHyiWGuwPkX0yn4BADjr31Bsupm3hCPMb+AQH3jkJZmpawsX7pqvaO9nSfqvAzVJ2fU4rUzhA74L5gL6Hhwhj59mXGouGJ7MrLHsXBrWH3GHQYk0sMJuEYDBaULj0P3MiA43DmeFF0mIxxCxS/sHXIJDPHIDmKhahizxWxK9AYk/PymaodYI6x+iH9XIvkzficCleg4HTJdZUK7duzDMYzG4qq165wIte+BVxjPLSrTaVFvZi8gFSFoBaHdkzd4Aqqck2Ox6F9Mb6qdJkb33UCDsTzJPZ4cnjNhJEqxfMt+QD1rOURNqE4uILaXqvlShW5K/TNMJselI3riI3Y5zWWLbRbWbatggIBYxYGr9CRp12RXz9kZ0i/D1pWvanXlC3KBCwoXr5rlzO0oTJDXFK8Sk+bong1JpwMqC8BT5amp4jQXpKDwQyxHLC1J7kEkDFykfvWuThF3Sykr7g72hialwXLJeE+9fayS/qm/imqruXh0AixDtdcVCk6vJR4npsnl+2om4jngT4dDiK9RcmjtXXuZ5ZOnBMlNRP3GOKTq7VltTyoXdzpBpMo6zudP5rgyQmKBzqOPuAYZWvw/qrTqzqnw2rl2y87/fVxTJ3/fkvVGTBVJw/4D7296lpNRhmNAAAAAElFTkSuQmCC", ["wrench"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACDklEQVR4nM2Yj3WCMBCHD58DdIPGCaoT1BF0guIG7QS1G9QJpBvYDewGdgJwg3YC+zsJNCAlCVyw33t5eUIgH5c/HozpnzN2bXg6nW5Q3RmHjlEUZRSYqO2klnpAeURRDU0ylARlA9kvCsCo7aTudEbNcqSPr1FSPMwzBSByaYTOE8ojaYPbPUlG00mQ8ZDcQXBJQoxcG6LTGNWbQ9MFHmZNQjhHsMAxkue5K7HKR0bHryix7QLHSPLqj0mAMoKQSylflStIJLYL0f5A1X2xTob7TKgnI92Zot+tZOsSSb7Mcl7p+/aiGGJVO94qiXNbVFOyo6gnbau4UVLLxTQQtm2mIjm0HBPpjhWqtKXdQdcuw2oy6bvVmKs4Q3VLcnC2o6gn5hDvSJaUBDAjqKRuapAgiivqQRlBPVdeSJZYL6zOXPwX44Z7VPckS+dINm0zC5R3kqVzJC8EOdlEYUke7m+So5OkyzvJmvKoNm1BR137bE9ew+2TUSuq/rdytpLph9hTe2ZTx1nSO2FtIqSkc8rfhn5JmqN8elzmNCdFBJlQkmKCTAhJUUFGWlJckJGUFFnFf9FxdS/xgGVmFVSQ6SB5gOCs+BFckPGVhGDpFWQONnTYZU6eGUSQ8ZCsZFKDDLGJZbg5e5qaL1qDRbDAiOSmduqDj9ffAgePYB1EdE75ym386Hl1QRvOX/mvxQ+3BNohn7iytgAAAABJRU5ErkJggg==", ["bell"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABY0lEQVR4nO2YgY3CMAxFf08McGzQm+B6G+Q2uNugK3QCYAIYgQ1ggzICG9ANYINiwEgIUWrXrlRQnmRVtCE8OQl1MsLAGWHgREErH3CirutAUXIEOJHAARJK6bK7u/2VJEkFI14ZzIX31HjNwU/hPTWmIaahneCSqbShSUWxpKGeoSOdBEkso8sKzWL3VBT/JLqFErUgy5XQD+GB4lcrqRIkuZPUabV2nV8VxQ9JHqRf0K7iKWyTP+U+xIgzyNnbw4exNIuaDObwI5c21AgG+BGkDTV/1N/wQ9yXZg7WcITmoOi3Yz1oJQpaiYJWoqAV0auOCwVXpH22CnJHJfwpJZJPBW/kMvhzrszbJNsymKMfuSsZWkqvl1/FS1xK/IB+2FBRs3jWwOXoo0/MQ8zb0HnD46LLXvgWcwYbDo6ujDVbzEeYD4/4BKt48Kiwyp37hxN8JvjHH9ckt4ED779I+mbwgkd0cGLR5PM1UwAAAABJRU5ErkJggg==", ["lock"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABq0lEQVR4nO2Y0VHDMAyGFa7vlA3SDWCChAnoCkwA2YANChuwQckEaSYAJmg2ACYIEiiHG+IktpRcHvzd6eyodu8/WZYTr2DhrECJuq4vsTnnx68oit5AgQgEoKg1Nndo92jr1s8V2jPaE4r9BE+8BXLEig5hbUjctW9EvQSyuFdw48pH5Bk4wstatNw5/EbpB+qzz6TgudMKhP/5douatmiHxkF98mE3M8atea4TzkuMUfiAP4E5C+kbf8Am4ccKx2/AAacIcu6Z0XscMe3B6Mf8H6NxXeKTHDKX1UbHGKc8VCvUUxEEShkUiEmdYnOD1t4g9FsB7uxwHp0uVLTzoTyOBsRR3drBtGQo0loNrAJRXIzNEebhwvZC0VdmYpgPa20Mu1hKEChFW2DJbQJK+LwPdvGOtsFSkZJRn31itATSC2vVPHB/CwpoCCxNcQ3sK0HI4jeJRgQTPhZPYJ94s2jl4N4Uyf09KKC1xHSWHvkDiUhBCe0cTEGZcNRJCQKl9AmsYD6st17WOshHVQbTk/VdcA5eHvFnJx38TncqI6CovYg+O5dA2MVSvgHw8nfpPNSjVwAAAABJRU5ErkJggg==", ["search"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACM0lEQVR4nO2Y7VHCQBCGN47/pQOvA+nAUIF0YKwArEA6ECogVKBUYKxArIDYAVYQd8lmWDK55G5DMD94Z3Zycx+5h9u9uw3X0HNdQ891AWyr3gNe+XTOssygTdDe0LbZQVReoj3CiRW4dMKJB/iYoM0cuu/QpkEQrOAEagREuCE+lmhD8FOM9oygO2ihWkCG+0AblJrWaBu0lNsM2hjtttQvQcARdAHIbiW4YQmM3JdaxhBkjHYjqhfYfwodAM4hj7tCK5woggbxD0vQ7kT1CMcmoFBQM8kWDq5d4wRjcBTtdshDoFhJtattx0wEx3Hn5SIOgbmoChnaWzbAUJTXtphr0Lzmnc6yAcr42YBCfLx8iyoDCtmuOiPKKkCWPAMHoJDLXWzgNFIB2lz8I8oG9JIHdwoK2QClWx9AIb6FjKhKQCEb4LsoG74hfCWPpl/tQV0JiC+L6aWiasmHt5Owb4QPmXrFoFRdPihXYH8vuxy2DPcqquiHzkApKyCvoszpKKa+EOClajUp5ihphTw1k+1Rm5SrKd2iiSge7yuaaSMVExuw7/YiLXvSgLpm1OXMpknk1ghy1xa3EoGOfCGdvkk4n6Ns5BOawRZoBsfQyqeibZ/8+my2/dzgKd4oIU9IVrh6w1Cyb1Vu6LWS3oC+agvp9dmpEUOEcJzZOLu7c0BSG8izAJK0kGcDJNVAhrYxZwUkWSCtSXHnu9gmdusY8i++1Nbv3wBddfl/sK0ugG3Ve8A/XTrc2FB3eyMAAAAASUVORK5CYII=", ["flame"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACOklEQVR4nO1Y7XHCMAxVewxAN8gGZYOGCWCDhgkoE8AIMEFhgtIJgA1ggsIEhQnSZ6pwic8fcuLc8YN3pwuxZPkhWY6SDt05OnTneBBsimeKgDzPE8gA0qXIaEwQpKa4/EDWkC+KjCeqCY7WJ2RYcQhQRNTagyql9B+tHrWMYIIgp0htINH3mwlBe5Aj5yTHNtEgJsh7TqXVF7nMMn8MeadAhKRYFYRkz01B5Be1smBilWLCfYrLBPqzwJesiuE040VCcYQkhvElCI5IAC9BjoA652IXxQIkP3xGkj2onLRRsWNOtxPOCLYYvQJbRLHvMvBFUG3sNs+71BdFCcEQrFhCkLmUvhTnJMcI6VryvIzkVX/GvBeb0hrBwCfCjZwC/xYdI0DXtZYrxQnJUCFXIJBkYlM07Qcr5FQjwc3EFYEkjWjS8vdBYFvclLoc9Vvp9sQkeSvXeRLVjuDIQq7LsjFEcuLwZ30u16niHRZMLeT0RW+RZNstLm+a3QU21rPWF8GDYWxWWrDoVEwLXHXai9TMYLclB3wE59r9pZxaXtDVgvWoRIrnXjSbNTUguNYc7jX9gPzQbco+TtSEIDeVM4dJQn64bGa+xtVbxXCg0ryzqE/kx8Ey/m064HVIj5khk3nVxpeCuXoKlQ9FOiMBRAQ5DSnkhKosdzhzskeIWHcrNJ6r/mgqfScRH9RweGSSPQNxU4u1MhDp4r4nJXddgyKBz7uC/D6EhAtRv6O0gccHzKZ4EGyKuyf4B8e71RBt5IsJAAAAAElFTkSuQmCC", ["snowflake"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACRElEQVR4nO2Y7XHCMAyGlRz/YQQ2gA0aRugETScoG+BOUDpBwwTtBoQNGIERYAIqFftwjL/kuG1+8N754jS29FROZJkRDFwjGLgGD1hCJp3P5wm2N9kmkEk5Iyiwvch+gW0JGcSOIEbnCVtleTR39NW8iuYCUyxAdCDw0mDbYv+DMY/GbmmutBEtbgT1yNQxkHJM7bARFBdQYDtp915IC9xJ2ogW6yMpimIv378W2xiukBAJV5EN4PiEBKHzuQEZUhIcqfRArLB9SpiOpKMKusvNhiPb0sfKNblwwNV4Ue/WEdvC5QD8kfTCweXLVkn9Ecd9meNcETxofTKwTYgkB450tNiwA6LRFi+bHpBcuI30GQcoHddMSB1mz4SrwSFvHuRAhpQCFwTMBZkK9+PfMEQG6JO3Oa+Me3qp9WWcawC+Z0ot3IrmvCL40QW4hmvJ9F96R8CluhliRd1JNyagkFfbEj8Y95RKzGUcRzxT2sGtWmxr/Q9Re3HMxo9jWrj+Ezt8VmnPbDtOg2OeIaDgV5yjKnEk86h6svxtuL6QZQ44uYQz7U8zxrbohXRVMxVcEmssnJmESdwqaGHbj10RnPaEA+AXGDYb7q9Ynr7IuEiA0xWKpIBLcSGAA+gTAy4IGVLKwd268UM38e4gUxXEPbhHVyW5SrWUc3EQTskBKYAhLqD+DsXVc7eQrPeQe3AXuEQH7B5cZwjHPErGDXan2G+AIXa55XFAkVHFQmuZ10KCcv8+SKKUsoZMSsqDf6n7j+h99Q0A3W3gZBxT3QAAAABJRU5ErkJggg==", ["bot"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAB3UlEQVR4nO2Yj1HCMBTGv3oOABt0A+sEhgkYAUbQCcQJxA1wBCYoTiBMIEwAG+B7NZUUSJrk0cqd/d29Sy/Nn++SvLzX3uLKucWV8z8E7vf7HhUjskxXLcnekyTZQUgCISSOReVkvaNXLG5AIpcQIBJI4lIqPnEqroRF3pPINSK5gYwJ7OKg300gQLqCW7gFMjtawT4iqXUSEqGoGOLgACZ14oo2NEZ+pp7P5pzEL1ydkxpxj1S8olmeSOTU9tIqUDvAF9qhb7uSXE6Soj0y24su1Em5eoGVM8gxleyZjJ0jR3vkPKeeu3J1JaY4LSrzHPRDlw8XalfC9+Og9GpzBacB4ngAxcbPF2hnkmktBcUKBt55nEaNzQrqP8NPuhXTzkZxN5YrmMKf3YXrbBS7GZPNDM2DrJ+HgnZOEqPzNqDfGodzwvE6FbY7R7HFphfP4H8+mub3/B5fMwuyO/wtKzJ1cs3oCkX2QrZB+2z03MrMbFzploI9mqyOB3LhsTsDW+Ia+00yDfmk1G1niCBWoEI4vqGuQmw2M6Jt4+3yXUXeYt8wWkGSbkVNGEqXsEpxCQwJ7FKsc1m9WP/0maN55q4fTHXXzJjsDc1Elo0ee+xqJP791jSdF0vpBEr5BitApEHVmA2+AAAAAElFTkSuQmCC", ["ghost"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACkElEQVR4nO2Y0XHbMAyGoV7eqw2iTlB3gjITxBtEmaDqBKknqDdwNEHSCeJuIE9QZ4NqAheowDsaBiWQ8uXy4P8ORwsEyU80RYG6gneuK5ihw+FQYXGLRuVCVHdoe7RfRVHsIVMFZAjB7rD4AQOYRQS7RtAWEpUEiGBLLH6CHUxqj/YdQZ+tDT5YAxHuAYsnyIcDbvvEfZlkmkHscINFPRKyg2F2ugCE1uTnkTaPOJP3MBdwBK6HYR3SQH8jbUtuS3EfIQOymIBrYFhzUrTYmxgY6KBrtDulmtbkGlIBeQv5o1TdY4ePkKGRG/4U24rGHpKN4lvlwpF4plbGsYY2mhPv1GHxIty04S7hDML+aZu5Fe4b7H8rY2MzWCu+Bs6nxjhmFPCruG7nvK6kuK92Ysz/OgHE6af9qxJu886fINlnxWMfSUsWSumQrybeNvyW0U7sg7G4rWVsDXAB06JXnuPfNdqX1DiCxRvQxt6GDm0NyrvYhRe8P7qwU/ZBRtxuYmxTsnD09/EC7wNXrz1AxrjJN5E5mxFyaL/Z3BniosrKqHEmOsuA1rgxzUr530IXwLm6AM7VBXCuLoBzlXJwp3ztgY8DWn2J9o2tjMQ47qMCo0wzyIkknVFKvj46zzIQ1ftUrUbfTZj/ifN1Q/VgkGUGr0O4AGATgQP+/eJnUjn8+zbXMCHLDFYRf80J5wL0JNdDdqAfiEpQ8r8cwDHVE/UxeLNS88HeUG+JMSsFkNLzCk6Pi+HAji0G0XIfOzDKCkgdOnoq0Wo4hey5vguSVAlJp7qan2wHRkgNcBuD8w6GXDHEq4cL6j3kK8esuI2vj0F24jr6babBYgnDR0nzZ7ZUBZ/lKrRn7TNc1kf0t9Q/g8sRu4EGCmsAAAAASUVORK5CYII=", ["gamepad"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAB9ElEQVR4nO2Y0U3DMBCGL1XfKRtkg4YJCBPACGEC6ATtBnQD2glaJiBs0E4AnYAyQfhPMVJwzva1idI85JcsV/b5/OXqs52MqecaU881ADbVANhUA2BTqQCLopigukeJUVJqphzlC+UtiqJjyDgKGQDuAdUryoTaFcM9AnLrMxr5OgGXodpQ+3BkfG7MHE45I4iBKap36kY3iORO6vBFcE7daeHq8EWwILdmKPzEoQj/VCbn+spliAiKLGMHXEp+7eAv9z9DCQW7pfHJ1YvLkOdkn6QBpHI7aVuTc/pPAfyo/D4KbQnV/8K5WSo8+RP5xeO3WsDEbkD4U18bOHJUt5YJgy1Jp1hqdAHWwg2AakLMeFuw2qYU1prKk+RZsI+lAWLmFOHVf2eSJJglFe0xJjH+Y1SfVv8R/df2oC4vC6GH0SWJYothTU+MHivBED7Tef/MJANpq5EiqDl3tQvfVhbor80tHXUJXU61uaUIxnQ5xXZD7wFr2wwW6jfp1iFfBHakk3TKSKptNRKgJjsZLnXd4QSfDJiTAtK+1UhJsqcW4cykbJuasT4d7AYJcNkm3J+UkAu7YSQ4WlF5Zto6nAtX8e2DXJu5/48hh8yJwiWmMhlWmtdEjcxrbGb8s+9cuqx6Afui4dNHUw2ATTUANlXvAX8Bo1qeTaQi0oIAAAAASUVORK5CYII=", ["brain"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACNUlEQVR4nO2Y7XWCMBSGLz0dwE5Q3IANxAlqJyhOYDcoG2gn0E6gTlDdQDegE1QnoO+tUXNiQhJCrT94zrkHIZfwcj8CeE83zj3dOK3AUG5e4B01QFmWCWwM+4R9l2d4fwp7oppEFAAunGLzBksd3AtYHkXRB3lQWyDEsbCc/FnAhhC6c3GuJZDThk1G9dnA+i4ivWsQ4nIKE8cksLmLo5dAbgY61JyRSAK7VfWWipttTiAYW8a3yn5h8R9BZKfKwVmgiF6qGRrC+rB32EAZm4jj7NOF7ZVxFvdKFTg3CQTyxUbK4TUymZIjIqVqiRSYo2s6xyfFiebYhC5FDGBzXobU9EFIrpkjrkqzj8BHzbGxSP1JHB26k7c5bCqNdVi4Ye6EQgSKC8eaIT4mRzFTxuWaTOmyRq1YBUJcTFIkNMyk3xtl7EsZ25MnLhHktJhqhB9ZM2mfo7mks7hTxOBX0CHiuqfHrpZA0blJhUsq7/CjCzYQ63QMUyPKc6k3u9f42QWK4h9RNS/HJsG2Z5pH6lJdqSyoAuM6KCad0fmOewbXQmxj2JIjKM2RSaI4Srps8EvDinwFqvDbp4Mbp/hBOke3uMtYF/qmBTIr6beu5o5wRyeieYz8hUBXniFuYXNq5JvEE46ckzjm2l91a1hmS6uMTwS3FMZvQ/iIY3wETugfcBYoHmn84hkaSS9Cv4t9Otvr5fZI+99MKNcUWFANQhfqoaMfvxvWWgWCmuQatDUYSiswlB+dk9tKqmoWqQAAAABJRU5ErkJggg==", ["map"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABdElEQVR4nO2YgW2DMBBFz1UGyAZlg3aDuhOUDcoI3aTtBnQDmKB0g3SCphuQCci3OBTLCdjhsIQiP+kLCV2OFycSPm9o5Wxo5SRBKbcn2HVdhssLkvOtCqmVUnuKgAopsqQK5HGkbIeUyBdkW08/jcsrkiGm9hOfaegaQTTZcpNiQmqMik4r23K/jPov+cZiLs+XJNWInBH6RrY0Tc0P9cmaPtpT9wNBHSpYBTyY0FDxSpv/Y4E8kQDT7+zepUI8tKMZDflnHGQf6EqiCzo9MupFTe5pZr9ogkv1S28SKUlQShKUkgSlJEEpSVBKEpSyesE7EoBt3h/yzpvTKIg2rA7D2Hk2I0s2rEsK2jR0km0D+5na3L05JmhWwzf01HwNGTtzT80B0RDcUaCgpn4udvlHPpDSGsiHsTMPkHX5pX6ly7HTiKmpTFN/CmAE9tykoQlYtqDpsXOQqkLOc4KmsjlYM7J9yBQkZRNNcCnSm0RKEpRyBNDskPpwhwuvAAAAAElFTkSuQmCC", ["cog"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACVElEQVR4nO2Y7VHDMAyG33D8ByYg3aBMQJgANiBMQJmAMAF0gnYD2gloJ2g7QdMNYIIiEfWucWXHTvp1PZ47Xe4ix1ZkW5J9jiPnHEfOaRu4XC4v6fFK0rY0mZK8RVH0jZpEaAAZOKDHfUWzIRn4gJo0neLrLbWx0tSDS5925MHa45yhJrL+tt7W5Kyi45Tki6RHYm6EkHX1YPTblj6579T1YeQwjg2aGK9HJH0ZMHThD0RSksTQ3dAqmCLQwC+lo10xIgPvNIU6xWQceyfB/khkzA02PCgLmqc2xn7JyYst86XmwQ72bxwTk3My82XJg+K9OUloWBij2Dz5ajAUm+EWYXBKbK2nRtNAbedW8UQd9jWFrCvWXcCf0o4uTbEouvDnxWac9LcKK750zXCjhhnPP19QZzE88CgqfkhS+aESapiRhjzdM9j5gD99h47HaGvGMdZURx/kKCK/jSn8yR26gYylcvQVtdWDtG5iuNdNG/7EDt29jKXiSnWTCiOe4c+jQ/cX2mypbsNAavhOj09UB2uO/J2KNqufrap8eKxPGbvENgJ1hxZ512FcD2GZqbW+abRUx8qQyM+MoKe6BGFwPIytqQ6FkRmKo+Qh4CNqtv7CVm5xjGt0GquBmpk2Nom4t3Lx7wB1TFfJP0J4uVSXMTkm0RSuU532R1z3PZEMEc5Qvh0rutT2kfNALUdClpzkY70UEl0PfpRqRglnq8q97yzZUBNJT3PP5ld1L5BO9+pDWHi0maEBTQ2cbqmNlaZTzEE9g/sCMzvYBeY++L9Eb8ov04vnmGZXJSUAAAAASUVORK5CYII=", ["rocket"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAC00lEQVR4nO2Y0XHbMAyGoZzfmw2qTlBngrATVN1AnqDdoMoEcSeoO4GcCSxP0GSCKhMkmcDFb4EuS5MURcm+POS/wykmIfIzSIJwZvTKNaNXrjfAsTo74G63u+aHEjP1zLbIsuzZbDwLIEPl/PjKVrJdBlxfxOegkwIyGGBu7UkDyu2GkwEyXMGPnxSOWK8uaGIhamwAq2kkHDRpBGVJN2xzmkjREeTJFduG7UmetwKk+wH1ZyRcYzdERZAnL6nbT1qK7UGnBIFD5FxLupXnNSUAZn1vOOBI4ObSD6jfdHwCH9gK9mvFD/1rto+eqR7Z1x4jvMQeOOSqwoDbOODIhIPk74L8WrkaLwbCQZUxcUXuPbc14SzIrcP/xQc4GwiHpV2Kj6LudphCS9cXgjIHXE7daXTpEw/UiB98cvLrgz2pZ2xEL7fvYC3XEufk1taAKykMB9UCZMLVDr/CBwe5IoiNv2L7bHXtoyf9iELsLdHIUzn6fvCY3yggb5qRb1xRd/LueSAl7Wj7TuN1SFVJgFoSsUsjn/XtvSg4NhVaWooFtMWALT/eU7qCh8JWSjVTyCQpio6c1uAIQnL3NmzvBrw2GA5Kqgd5knvqTmVsJG9wIIziIrpO7LuLdYmlVUulHAuJqF2xb2WMiRuqorGAkk429H/+AlwtfSHIR+p+oc3FZ5+22FD1lDSgZsw8cErgQvrCk6/FX+9JLCGKiZU1HvImEvJhadknav/7CtZgdheV1NV3OpJH+0q+KJY0t7ruKFK+q+6JIuSLgoAhasrz6qHo6JMrggUlSpYav4NVwG0RCwe5ABXFybVMLdtV4J2FvT/75DrFMT9uoKXdIHlu7fEfDLcf0/wwYP/dmLnNGiOn46I0CQ6yI9iXn36RlXhtSdVzNwXcfjzzg0SwpX93LBJuI7aOvUdlHEVdHdnSCPnSzFwGH3Sxn0JJ1cw59fYv4LH6C0Y4RyJu4KXxAAAAAElFTkSuQmCC", ["swirl"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAADKElEQVR4nO1Y63EaMRDe8/h/7AoiKjCpwOrA1wGkgpAO0gF2B1ABuAKOCsJVwFFBcAVkN1o5e4sex2MIk/E3s3PiJO190j604hauHLdw5bh6gjddBu12u28oY5Q7uDCyO4ikhvh45p89lBIuiC4mloSubwcRD6K9Cg1g0z8kdNRFUWzhCCQJ4ocNPox4Vam+Abgd7kMGOJ4ejZIKZYPkm9i8AtJKLT4W4tU9P8coQzgfGnBkKyQ7lR05E1vRfgO3m0T43L5owC14iJtyjyR9UGbTjBFtstFP2CdHK/6K8qVgUJvfvUb0vrHkvpk1cYWPx0g3fXyU8h/WYcClqSfVRYtowFmJhPx4q3XmCK5BrYjxXZqhC1DXCJzvehCZXi66cwR30IEcDqPV0077aKZ0tMRxqwzJFxwzgmMIcm77pV6/osJSjUlF9ATcgrZizhza5u6l3CQVJKHcNlLkFpBON9S3UGf4KDAGjiGoMVUrJTPrRSxZJPrw9ywH1iGjWwfP0QQr32CfG4i+GpypLAm4oqIW/QOOZo+5aPfPRVA6vFV9ZSs1uLauesqILn9iwUkEVUTKVS9DTs7vpLlNRFcS/0dFTWC/85A78Kj8y4+nd/IUaiK6jiaozSCVVqpvJklye6bGdA4MiShBTq4yEkvRR+Sn6oNrJEY5j3LjGtokdIoq4VSCDLnqJ2VKSri1Gm9hP8JraCd4A5ncdwjBifr9fo7yDlto76QG9VlVEIz1IOyvYgqSxQIBVzyBdlIOFQsG2qU/ucBcp59AseAJFqcQpHO0QfkkXlPN9gIHgO7WII48gQ3qMrF5N0qJQZmxs9NFnXyFCFo175nHGcgT+6MzQo7QpOYXStkE2ub08D50F+ibs9T+hOA8R9fQEsIRS+W+twhF+BAi0CfJKkIwRMzjnUS4vt0jZqF9U2xSE1omZuenyw5F3wbOC/JZA84acsFValKu5Des1PLTy2foBsqBZP6Jj2jUSbstT5lkRZ0sFngiSRXqT5VJidxmRXuTuxWeVM2kEmwCqTN9D/+i3JKnSpUbnE3U5wYn/h8oTZe79cUJHoqPP9FPxW+r/Eb9R3QXOAAAAABJRU5ErkJggg==", ["globe"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAC1ElEQVR4nO1Y0XHbMAx99uU/3qDqBPEGoSdoOoHlCepOUHeCeoM4EzidIMoEdieou4E9gQtE0BWiSYqk7Fyul3eHI0WBxBMFQISu8MZxhTeO/5/g8Xi8pcbIZSHtTtpqMBg8owcGyACRmlJzh5rYqEN9T1KRPBLZByQiiSARM9T8IBkjDxXJdyJaxU6IIkjEeJeYWInzYEXylYjuuxQ7CRK5gpo18neN8YfkgzW2JZl0kRwiTI53btOTHIhEQc2M5KCGec3fYiOdoEx8QncQdOEnapIr1FH+S917sREiGdrBPsHQgHds0Vzw6yThNXU0j8WWE04flGh9Qhp4Zxp/4pZ9bOnzMbLB92/U0MQV3T6COX43SUkf8lp3JNcyxEl9YusNHRNL9H+1nZCdXaghI7ZbcPngHV4JRHKJOgU1MLaOi+At8tCZdD1Yqf4n+2bLBxOCww6IFe3GIzJANtmdNmqo5cv2acaoPqeIOck9TjFPCYgQaJ0tkWRbTbAw4aq5H8qDW0muM1weW9VvJW2bYGFd4xVJOjkMY2Y4SPLnKRYl0rAPEdwhnmQs7hP1gwQ1buyBC75ubStIsFL9kaSAFs5NUmzowNh6CUrq0Gc2AwfOTFJ/uQ52+nK9Yq3wBR4IyXNgqvonyd5FUCsVGVF4Ai5NRcbWeIl2Wqnsub7jlj6rsdN+dJ3rHGe6GFQkn1H73Qb//O+ZbBhb2RfFc9XnBdYevSXSYWTeGu3gWLiUvVUd7c4Kbf/gA8HMoVeifqDUndR4oLVLJBLkp6ssw95SkfRZN+eoxicj4ysNvIlaJhi4S0VvdCfiECIXJMiQiQVOS8UlkWSi31zJPBK8ZtFVuKf8+mDHngbU2NAIceCycx7z6yP2NLMXJ+aqy/c7LYYcz2UfLmPIvdhGBiRyDerP1HWHOvsZJ/8q5+uTRVBD6pjmg1/I8A5SvPctDXoTvDTef6L3xV9GTCZ/TsXbRAAAAABJRU5ErkJggg==", ["leaf"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAB+ElEQVR4nO2Y7VHCQBCG3zj+xw6MHUgFxgrECgwVSAfSAVAB0gEdCBUYKiB2oBXgrrnMRGXva8OEH3lmdi6wB/Nkj/sglzhzLnHm9IJaekEtJxM8HA53ji4fSZKUjj5IoMSIZBS3FKlpfSko7kn0U+oQJUhSGTVPFCOKK+goSHAoJYMESYyrM0NVsTa5kYb7Ap6QHIu9o305JpUSXpOE5JbU5OgApyDJzdGRHGMVJLmcmmd0iChIcjw7Z+gYWwWn0C8hao7OYlM9zdB+oSWkZWaEeLYUe4Qh7iSSYIZwuGqPFAOEbXegRbqQcpJgijB25jMPCJRzIQm6TiJNVqgqPkHcermzJb23OoEVDU+OqmoviKOwJSVBn1n4I2dm/BLxlLakJGi9K1TDMjHX3KaIZ21LSoIlZLi6Iz5ktrFe2mYwIwna7mraOLtx9TS7zdrVQTywUnV48Rz8eXtLcpnJs9heKTiMrSAzP/Je3rjWHve3LjnGeuSnKpXUXJuX9ZJS596gO10PfQRd62DeuJ7WFySXQie38JFjrIL0JRtqxqiGo2ykNNsZj8TEt7NzJ6Eve8X/002s4K+fiQ9eW92RP9YZwuC1cxwqx8TuxWlA3wX3NyMRTPSjD5ooPOwcqYl6tvOBtaTYUKxtjzV8UD+bOTX980EtvaCWb5ZAfzhWHlKuAAAAAElFTkSuQmCC", ["sprout"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACU0lEQVR4nO1Y7VEjMQxVbvhPOrilg6MClgouHcRXwUEFhApIBwkdQAUsFYRUQKgAqCA8sQoojkxW68Dkx74Zjb9k7YtkyZ4c0J7jgPYcHcFcdARz0RHMxS9yYrlc9iF3kEA/ADdBQQmZgOQFfTPcBHu93guaaxmOvJ6UCAwhRRP9th4cqz57sty2QYhN0H2GTCGBGqBHLYGPLdD8liH3j8W7lm5AcwXpy9QcUqb0Ndp6kHGj+gUlPCJem7QhR5kEH6Lxf7LJBTX1yuOm5Bg5dXARje/1AOTOaNOrY5B7IAdan0EhsVTDI3x8IfMFmhl9hpXxhPWCnNjVTXK/IicY0To5xphaYFcEPxKGywmaYbR+S3VpcSMnSRinVGdlpeaC6j+xDrw78CSGhnkGxQuPVIepgrBx9tJt/CHW1XMYs95fqr0WLH2qPVxC/lBdoljnyPoRySSBoQrNibE0hVxGZ07v4+SYYz1E8wUavruDsY3PcGnZS4ZYNpxTXbs0AmT2xR38apDjGjmjTXJs+zxF7p0HbQGMcxgqyKGxPIXxf5F+HPK4WGty5ba62KgOeknuihyjURaLoUFiOVjhTtwkKwya3iium0RlaAwO6bFOHOjys6pv6HIlSP3YDXjrYEjMM5FRNDd32jDhIhi9pmMMpcatMDV0rr0Fu81NcvPFmg5d5dxrYu0MSrbekX12mmDtfMEee+vQsZ/1T3UCxR48yyBHxl7X20/2Bz0RE6woDyeUj0oPNsqMhLm1FxGeKsPWS1wfs17UP4Huz6NcdARzsfcE3wBmmutmpDlXvgAAAABJRU5ErkJggg==", ["layers"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACeElEQVR4nO1Y7VHjQAx9Yfh/dHDu4Hwd+DoIFeB0kKvgQgUHFcSpAKggoYJABYQOoIKghxXwbLzfDsOPvBmNnaxWel7tSrJP8c1xim+OI8FcnGAgbLfbC5GlygUGwgiZEDJncrkRqYyhlcj5aDR6QQayCAq5Ui5LkTOLygYtyQckIjnEQq6Wyxp2ckRBHdVNQjRBhlRkLrfziGlzztHtEIWoEIuDAu1+K5EGhpoh34ROCF5BITdGG9JUctC5a7UVhCCCYvAf2pWLDlEP3k+92vTCGWJHChkKK3hSkXUFNYUwpBUOhwptyK3bxrqCMukJbZr4CjzIKv7uG3DV4uwqEwGrL9ch4Ul7xuFBH7Vt0EpQyxP3xj0Ohzv6cJVCZ5rh6RKp5PYSw+NSbI99zUTwPtPk2oj8QB5eRUhsFaKcUupuRX4hDY9oyW1CJ5x4CJXdAq+GK5EF4rGQ+WWXnDYeZRJBmXiFNlE/yX3VIcl9WcvtBGFgSCc6p2ufW4a5dq2+euFK1Fvjr6k4uTZ0+PQM+U+LGaaQsXlKtQ7PunqiU/QZcIX42vh9JYZvjJC7UtFeCtGQLg1yRAMLfM1Cjf3GlA4nPatC3XrnUMYbY5wPwsaj6PzN8E9N3WCCHcNmGJm7/roMGzZq7D9ob/hNePtBSxgZZrbw/+EmZns98FaQD/+IgDibycVsNOnkj1kRHK8HrCAzBCK6Y7FUFJI731UH1eGqdTvwqAqSTFAJFOivKI1ea+P/6AqyQ3LPp+mGCdb3mWNhJukYDPHpo0b/O7I3hYRgkK5ZU1GDz5DzxE9zPnnsMGhbr3sTKXvNhq9870jC8QtrLo4Ec/EGlwgYKQZtG6AAAAAASUVORK5CYII=", ["grid"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABhUlEQVR4nO2Y4U3DMBCFX1D/0xHCBu0EdAPaDdIJYAQ2gE4AG9BOAEyQMEHaDdIJwhkuUhTunLMsVUHyJ1l27frdUxzbp8wwcWaYOMlgLJM3eKUNtG1bUClbPzWVJypzYf6cx+oRDRej0HxkmjmqXmBnn2XZZqDxTtUKdjaksYfRYEnVAmEsKUDF893cMmw6Kpq/HHZq72CoOcdcaVsRY6ZdHEsyGEsyGIt2k5xxeU5Sp2bwFYHidMh+dD+4fUIYe6lTM/hI5QAbzsha6F/DbvLAMf+Q+WbxleW9FfpPTtFYwU/TXZGiPibO/z5meImvff+h5fkc0biFn3PwEnMC+gZbPnfEby5XDTQWrJEbNNwO3pJGA6PBZ6ruYedI4jcDjdpormNHGg/DTu2YuUMYeX+3cjtHGGJM7R3McXlyqTMlC7Ekg7Ekg7Fo5+AXwmmUthUxpi8fDOHQv+q4bc0nvTFFg/yNZIvxJ+kS0h2VQhgreGwsaXUxxO8yP14wcdIujiUZjOUbzPq5rgR8AucAAAAASUVORK5CYII=", ["crown"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACnElEQVR4nO2Y7VHcMBCG1wz/CRVEVBBTAb4KoANIBeEq4FJBnAruOuCoIE4FuXRgKgAqcN6NFpB10kq2GeaGuXdmR9bX6rG+7UPacR3SjuvjA3ZdZxCcwz7BjCS3sEfYXVEULU1QQSMFsBsEVw5UTBvYGqDfaYQGAwLsAsEPSoP5amFzgK6HVBoECDgGu45k//biZ5FyNSDnlKlsQMAtyQ6pD1XDGjT66JXnOVmRfSEfdoXyX+mtANHYAsGNk/TEsLnDJdNiBTtyknm461TdJCCcVwh+UR+ugvMNDRD8lAga6kPO4KehiYAMV9EEOA/yj5PEU2Om1TlIOKwcOFY9Fo4ldd3tppI2aBQg9RfFPdkFERXPVZmvmmrxFWpjS0WiwQeyJwTrJ3rgWinL5R4keuyvaq8sQ36TaIuyJ7GyB4oT48CxUiv2IvIckuvLyMsFpQ2x8eKtX4B7ohMhunSylt2rQtPC91XSCMCeIod+o9f6v+qbTF9BZQOGJBv1qYD44oVQhTZzbUh9ZQPGtgPZOlaBrLWyJUWH1FcUMLDDa07PA2lnSvky0daLUj145zxfKuUM2WGeiT2R/kKXkTZoKKA7f0pl1+ebieGekN4wkrYl8VFG2thSzlncIvgsUX4+1TbhhC9eHHwWG0m6hy+j1clZJAvn2cBuabxuqb+/LlIVcu+DPAzuQuDVOcvtSek5vhW5Q8sfVKkTJxvQPWefxXB16mNIPq74DPf3vuOcFxxy5e+UbO5h7tVW4oZsb0V7CHBZbb8V4GDlAu5/fUzVHnCq9oBTtfOAk27Ujv7C+IfQidhc0iZryEbNx9KRB7Uie3NuI3UM2dPkCvbFyUreYsYA8tHFZ+pGg1LqG7KwFWyR+4di9B/W99LOL5J/34H4Fqzbn6kAAAAASUVORK5CYII=", ["users"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAAB+ElEQVR4nO2X8VHCMBTGXz3+FzeoE8gGlAnUCcQJhAmkEygb4AQeE1g2qBNYJ6BMgN9rE6/WtHltwOO8/O5yKU2+vI80SV8HdOIM6MTxBl3xBl3xBl3pZHC/31+jGqmSorwEQZBZNCGqu4omhWZNQgJJJwQZonpFiQzNCwSMG3SP3G5oSlBuocvpQAbfGsxp5gj2XNPMUD21aBJoJuRqEIFuqJy9NnIEu6jptqiGFt0EuqStwxnZiQR9hjD03U9d28yJxpZskpCOR2jrIJnBlGTkDddtZLYOkjUYovqwdNtgLUU1Hf+xK4vu0nZMWWdQDRC3dNmhzAz3p6qtidhmjpE8Yja5QDU3BHxHidCeGjR8L1J9qvAYczWmPTZ1pLJbc5OxBg2/RYpdbTtW6nQ2+Nf8u2RhXLu1kzxm9YjP9W9oNiRk0DIorxnOXiJVwoZ+XLHJhMr3a1OmstYmlSbTGm5rShwCQ8AQFWchU+oHB+LEYVkNqmYxocpM1liR4egJauYe1OCHIKMypUor4y+o/PNtzKBZUt2gUNwVnsGJNqmWzVagi/U5GXQU9uHHaxCxElRjge6Cl4h+k4zoeEjMmCg8+a86V7RBaf7Wh0/qR+GpMMi7DIv3Hpf8/SFJ1aVk9PvY4sAbi7GV3vk+WXDFG3TFG3TFG3TlCxeAq5+TynB6AAAAAElFTkSuQmCC", ["compass"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACwElEQVR4nO2Y7VHjMBCG33j4f5QgKiAdoFRwuQrwVXBcBWcqOHdwSQWBCmIquFABpgNSQdjFm8GWZWtlOzMMwzOz41jRx2t5tVr5DB+cM3xwPr/Aw+FwRRcrt0aupVyL2Wz2gBHMMAASdU2XJSph54HqL2QF2R2JXSOSKIEkzNLlL9kcwyjIbklooW2gEkjCeJZYWIppWJH9JqEvoYpBgSTO0GWD4bPWxY5sERLZK1Bm7glhPxsKi7voE5l0/SHitjidOEjfWxnLS9LTeMxi6OOe7LZ2P5exvHgFympNMS0cYvh1LtF+8FTGbOH1Qar8H9PM3h7Vis1JWCl9G1R+7cJBfeEWJh5x6QTiWBi/RkOD3hzFCVlHGytj9wtEtUMM5ZnspwjL3NUps3fd0966Bb69+ArxPKJ6jatAvZvA/9/dgoYPiqNuEccPEnYXqhQRUxf1rdB9xRZxPGrECTx7mpja8P8E48iPP2iG5mQbscYgMnu/oKPxEK4PGuh5dnwuw7sPsevUF9sS+h3J1G/GJKxZRN0/EXUbK98VWELH3rNiM99viW0GenoFasndAhLM6ZMvhsbMHtMQ6C6SAmF4l8gV9Xj2WLBBHLv6TUOgxJ99f3usQkkmn1nIOOZtEMfePQ74wkyBfvIOUec1YSvEzxzTiqmJplKNtbPxH4Wxn40RdqRwC7rSLfaDS89fF07axME3xTRZ9wP1bd3Crp3Et6nfszgWRvYP1Yxpty8Nma/QK1Ac1T1k73gbE2EppmXddVbuPNXJ/smNLnFaOFWzXZFBc+wsyb7hNHBIM4OOnYw0NKiecmq4TxOKqcF0SzqwaPvkGLgvq/n0ocoHuSOylH7yqWvM5zRuyxlzqhH3NjYGIBmKRZUchPyT/YyDf6E4s7QYJLCOnGM4g+YFZaS4RJWV7GI+tfkYLfDUfH1EH8sr/Sj18Q217OUAAAAASUVORK5CYII=", ["magnet"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAADMUlEQVR4nM2YTbLSQBDH/6HYS3kBcwPBvRoPoOLWjXgC8Aa8Ezw9gXmLV2+LegDAAyjvAJbhAoonwO6kg5PJfGWCpf+qLmA+f/R0TweG+M81xBl1PB7H9PKcLBVTtSHbkW2TJDkgUAl6iqBG9DInmxmgbFqRXRDozjewFyDBMdiSbIQ45WRvXB6NAhSvXaLyWl8VZC9s3uwMKHBrsrFj2BZVvNWeyVAd/z3L+INAbtAH0AO3J1vSJrljPs9bkL2CGfKJ7slgQA8cx9FbBIrWylAlyh2tqyCbqDE5QIAccL9QHU0wHEuOMiW71bq4rbGW14MeuCzkqvCsXaDtyUm97uBfwbHkKKeGruVpDOxwnHFfyO6iA5xSTTJpqqvHCva9cmiJQ+MTK6B47lsEnOvi5ti6MF3K8qW+as0c26uBBW5tgGNtHXDvBcJWVRZQjk6VrLnXmsuwGljgbJfwMwExwc3g15zGTi19BVyAgRWCNVMhHXAfyN4Z2jOYtdE+lyehPm7ZsvUz2VO0IU/v0dYVHVvZLuPmSp/PAQ0NZZEFHFeJKctgP9ITnMhWf3Wlpsb6iKc2OP4gG17BrwacHL++9gZhgIUKqOs7tKANgDTBzbQx/MVzfaLE/2M4APWrg497LRMba8GsmwA4Fj/tFIZ2U2aXF3siC9pqIoPzI9DBsemO+icBcHpsQpnDJ5YqTXsaW34uPSi3e4bqCFTVnrRteqPBXUfALdGOv7x+k2iDGWiDtifh25Tmcqka+8Zp+3G7fvGzk9K6JDaSRLI2Q9uTPrjrCDgef2noWjgfWAMgTdn60jL26IDjwjAyrJ03eGBbuVqEi3+d/gw8Ux+bAmtwTnNeB8Dd0rjWKQT9JqFFU/166PCAcIJ0waEqDIcoQF2W4GbVF7npV9tHskdd4PoA/oQ5fmbSn1sg0QWOFfSrToNLXXCswNrthYsCtJSq+3pZFMhP6AGHGEBlA1Wt2i0J8dAw90coHCs2Bm0Vp6zdqEqXKVsZ7gHB7RGo6L/fPJApOmYrzg3I6lC7o+BYsTFYKrB2R8OxegGyPJC94Mr1cSZJBi/x56lm1fVfL5POBvi39Bveg5lLAuPIgwAAAABJRU5ErkJggg==", ["footprints"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAADOklEQVR4nM1YwW4TMRB9qXqslHDjgNTtEQmJ/AHLFzR/0PAFpF/QzRfQfgHpFyQfgMT2yAE1EYgrmwM3pCYSBziFGTKLNuOx10m6VZ802p2x134ee8ZeH+KR4zCm0mq1SulxStIV04JkSnLdarUKNIgWwsSY0JgkCVR7QyRHaAgHvgIi16fHR4TJMd5L3UZgelA8d4t4FOTFEzQAnwfHHvsNyZBkruxJU150gkQ6SpR5RpKSlxZS55IeBUm7UidBA7A8eKH0JSrkGPI+UfW6qIEsnd0JUgM9uJ4YVMlVUCi9A5vUGcl3khWpt6s17kg4uBJsQ5DQV/pynxTCJOgxgjvojvTFxC+wBUHthRH8SJW+UOQGcAdsIZOBmNAEXyq9gB9tpU+V/hbx6MuAHNR5cGp9RI1xPb3gF5Vyay1fk7wmOcc6XWm8s9bkQaXRbSKsZ9iqUZ2qsjmt5T5JTnJJkgphjYGXIH1keiuS4EwdGvRgdUri/vpwPXkms+MS9CDx2F8pPUcYC489U3oZ3f+hCc6Uniq9XF/bRDvgyZE85UafvRDBXOnaU4xU6UtjeRRKD63vSaCslmBiRNZpRAeF0o/hh6674RR9WLAChcO/tD+Fuy4tgrqdfwP1nL4dGwdKub22jMJv9HiOeDzRe7VE4p2qd84pBm5/KdYH4ypOysFYUfwH8Sisg4TYnBSCSFQ9bRGcIR4/AmXOcUznuNKOACyChdJLb9zAzWcfgGiCDGsHSpW+4fm6RM3gXSKV7SnauzJN8wiCwaQfQ3AfaC9ukJH9X097XlViftzbnvcYjLB57OoQqS/0/Cn6M/2B7C4IEdQ5jBd3GYHdmrq6syl9+4tejyrmF4FPnPYsgoVhGyGyQQPsrSPE4bc2OGtQ9tUr1OMq8l7mM+LxSRt8QZIhHLEzuEclH74qvcD6538IO6VtwCTIOwFJF+4tAr8PuczzKxoDPl1nLHDTkINgFEsjWbkD7EFqZ0TdD94zsWPPu4mmEzUjVzofvcYscI9uum74AvM+IMujQH2S5zugRM9W4x6UDrOIquYd0ENMMeSgOgxUGfrugBqf4irkcMAnmlRMOckk9E/+oAR3wV9uaCeGF/zxowAAAABJRU5ErkJggg==", ["sword"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACD0lEQVR4nM2YvU4CQRSF76Ix2hC1tJHEB1ALY6zE1thayxsoT6A+AfgExtaKwtiKla30FthYGrQyJgbPkVlchmF2F2YGTnIy7M4d+LjztzvzMuOalxnXVAC73W4JxbqhqhVFUSd5I5LAAlwNxZkl5BKQF/FFUEDAXaOoZAhdiTNZkEDKAUdtxR+CjMGccAPynkEL3A18AFdt7b1m0AaHMVZRMdbv8AaYBU7pRCzyMouzwlni+rPYeQYdwF0lF2unGXQAp3e/uwz6gKOcAPqCoyYG9AlHTQToG44aGzAEHDUWYCg4qpACUobP1QNmcDgqssDxobKmLrlwcmM/DQmXBthEsZ+49Q0vSEA4ytbFbe06OBxly+Ayiia8OSLEOxw1MoNqwy7DL4bqH/hWPMP9caQFqEy+wUt6FXwEH/uCE8n4NKMgX+GiVsVMzhmaOIGjsi7UXG6Khvte4ahUwJxvZE7hqEiDYVfG7wh862LmKoZ2nzKcUa6TuwB8Fo+AD9KbudQ7vGpoQ3DuMqaJw5m/Dci2OFIhAVdKwMkoOHahWoLWZHgJYg9UxKH6gOpff1hiB8aXgtyBW1pcUxxK72KeiTzBi1ocu3sj0o7GVBtmrQ6X4AZi6uILUP3gIYo7Q13V9Y9n0dBWB4h76e0QX1pVR6Yg416sIPfkf0w+wg2ZgjLtxaaxF0rBj4DzauZP+X8B4icUfKgAlRsAAAAASUVORK5CYII=", ["sparkles"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACRUlEQVR4nN1Y0XHCMAxVev0vTFDYACYoTFA2IJ2gdAJgAugGZgLYoDABdALoBMAE9AmUKwTbiY2P5PrudDrbwnnIlmT7kUqORyo5HqhAHA6HSpZNYQRBrga1hR7Y7CIqCCCmoLqQXRRFVZNdIR6Upe1Ks4J2bLK9O0GQaUFNU90j9Hd19ndbYhDoQPUhDYvZDjLGkg+TjnsSnEG95jSvgiST9VtifKwBWYo0cv4shrBnfiw2E0g9Icfw8iBIfUG1pDnHhG1ygKSW/lnXAhJjnk3a1pmgeGyZ6m5i8hU5APNsoJ6l2cbv5zo7nyXu5ezLghL9bSLHcPKgZP+1YbiuWyLLXJwLFQt+NzPZuXqw5zl2BQ4ESMdG7mhHOSH/mL1nKvAceRcRGAKZHuRlhYzITo5kbM22shWCILIQ42h9p1P+8oGCfLpGdxpXBIUYe6xFYTCHfPgS1RHkHJe3OuTFCgSb5AHdkb9K4eFd83VBwqeOBYXDsYyRJ7KChHNbl/zAhX8cPEjSkJTBRGPIU4b5nk7RO3apKja4JuoNmUkyudrdE3UC+bCymKjQ5BiutXjsOXYFXhHIVK4CRjgRlH010QxNPPYc7+vknmL+Jjki4IF1S3+1PdyBVYic58mFB7k+XR48+qZnEN87CXtRSTPOQ1AIJIePmsFMQYbn2+V/Xjs9oSi7hHIuHd587bwF8vQxgLycdTOxHoiptH0hr1uay9ebjhyjDM9ve5AzXiWKfGEdiLZWoMI8yODUk1W/CyWYB6V/5f8F0Ifq/euDgPsAAAAASUVORK5CYII=", ["waypoints"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABm0lEQVR4nO2Xj02DQBTGPwwD1AnEDdhAuoEj4ASmE+gIOkHpBnWC4gStE5RuYCfA76U0UXIHx/0hJPJLXmjgAb/ewXtHjIkTY+L8D8G6rhfcPDMyxeGKsYmiqIQFERxp5PaMpCd1aSN5A3dS9MsJj7BgzGcwhQXzW+zKLOiKD0HTh7+EBU51kDVQ5PYGqSdGyjr4jYFYj2Ajt2vtXjEOivSDjZxgNYKa7rGixBs8M3gEGzkZueTX7k0IOSHuEEm4uVMcyvH3xfigXI5AKKeYctI314xF9+n4YmS2z5cJOsEjzBYAtyHlBJ1gDZOTCQIztzpXJi/otKJuamJQdIJnmHGk5EtIUZ1gATNE7BUBRbVlgjfLcfnQ0d30QbFPaqK0vPd2fezoTMKJ+RWGCPbBG2a4jF6vaPNn1x2Xk/wn5m7hS3CgaI7+zlRR8L6901sn6BE1QtWZfHy4Xy9eMjL+XDI+4Qlvgld8iwZv9s3U70xyVVMcXFBwWR15n2INZ9ucsQQL25xRpljo6ExSK7ec3UJ13miCtswLVld+AHRchUekLW3kAAAAAElFTkSuQmCC", ["bug"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAACCklEQVR4nO2Y7W3CMBCG31T8Lxs0GzRMQNiADcgIHaFMUDYo3YANAhPQbhA2gAnSO3EWSRQ7/ogrVPFIVlL7XL/4fOeDCe6cCe6ch8BQ/qfAuq4zfiZJ8h3DvskTHKHFlvQ4cqP3Dwv7z4b9Eo44CyTyxvubCOhFxgrNXCsSOCLu2lN7bnTvqLH7MvlbvTd37MICXd3sLNAg0oSXOCYkiutIti18g6SkNnWYxralT5A4uZgWSHGNSBdxTc7UZuTqynZCMiBohXYUptJCqKQptiT4S2esFSiBcMTfMNMF0N1fdUMuLnDNZXzm5gbTE9puY1JqLxp7Tju8Y3wm2cU7+AhsQmJrg7iMFjl37Kciolck2Vut7XPVdam64kQA91UIZAyBc9qtvNspfXMEMnQGOSHniMuednuhG9TuoOxAjvjkfR5QmFxc4RptsbnAcFaHXJzidnOUBlO+CbadvoLayjBHubUyXX1jpJkfWiDTzOE089o3ZptmxrhJas8xK4wCxcUq0XJe66tiMintd2IDsStwq7C7nGmOSkEnLxePUFrZYizBTFGcIr44yBqpblArkD7Rnh4HxOcga/XrgAOSUEuEsTAJ6uJ0F8s/XsOftYs4xrlYoAXe4SdyLXPd1oMn8g1tA31RquB6sXDdOYW3QIUILdCuujm4OH1sfIUpggXG5vEDZigPgaH8Av23voLBXVgfAAAAAElFTkSuQmCC", ["activity"]="iVBORw0KGgoAAAANSUhEUgAAACgAAAAoCAYAAACM/rhtAAABc0lEQVR4nO2X7U3DMBCGL1EH6AgdoSOEDboBzgawASN0g5YN2KAwQWECwgZ0gvCecKWrib8jnB9+pFNk5y59ZDvXdkULZ0ULpwrmUgVzqYK5VMFcWirMOI5rxHn85cm831BhWA6X7XXcAHm/6BZD7kBCDryZOcUEtZwSUx+InZlXZIshp3A5iKkLYoPd/TZz/30FLXLdlByTvIL89uFyj/jCw18Ca/i8nY3pO9S/2mqSVlDLnUgfcIyP+JCe/HInY7p3yTHRK2jKCaySuuYTsRbTj8jfk4eoRu2QY5R+M201Uu45RC5K0CJ3Ib+kWcNyigIJEnTIdYjeJjnRiLnXPVAE3jPoksNKvOscRbetgxkQG7qVs7aTJMEQOZGrJiRlzRY1A0XSziHHYO5If7db1gyUQDuHnEdy56rx0cwlZzyDv/QVYu9rxCmCLNdRotzcTAmOYlhUjpk6g9czVFyOKf6T30f925lLFcylCuZSBXNZvOAPi9mzvQ09WC4AAAAASUVORK5CYII=" } --@@ICONDATA@@
local IconBytes = {}
if base64decode then
    for k, v in pairs(IconData) do
        local ok, b = pcall(base64decode, v)
        if ok and b and b ~= "" then IconBytes[k] = b end
    end
end

local Mouse, LocalPlayer, Players
pcall(function() Players = game:GetService("Players") end)
-- ===================== mouse, viewport & window-state helpers =====================
local function viewportSize()
    if ProjectState._vpW then return ProjectState._vpW, ProjectState._vpH end
    local x, y = 1920, 1080
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then x = cam.ViewportSize.X; y = cam.ViewportSize.Y end
    end)
    ProjectState._vpW, ProjectState._vpH = x, y
    return x, y
end
local function getMouse()
    if not Mouse then
        pcall(function() LocalPlayer = Players and Players.LocalPlayer end)
        pcall(function() Mouse = LocalPlayer and LocalPlayer:GetMouse() end)
    end
    if Mouse then
        ProjectState.mouseX = Mouse.X; ProjectState.mouseY = Mouse.Y; ProjectState.hasMouse = true
        return Mouse.X, Mouse.Y
    end
    ProjectState.hasMouse = false
    return nil, nil
end
local function over(x, y, w, h)
    local mx, my = ProjectState.mouseX, ProjectState.mouseY
    return ProjectState.hasMouse and mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function applyInputState(force)
    local capture = ProjectState.open and (ProjectState.minimized ~= true)
    if capture and ProjectState.gameInput == "always" then
        capture = false
    elseif capture and ProjectState.gameInput ~= false then
        local popup = ProjectState.dropdown or ProjectState.colorpicker or ProjectState.keyMenu or ProjectState.spotlightOpen
        if not popup and not over(ProjectState.x, ProjectState.y, ProjectState.w, ProjectState.h) then
            capture = false
        end
    end
    local desired = not capture
    if force or ProjectState.inputState ~= desired then
        ProjectState.inputState = desired
        pcall(setrobloxinput, desired)
    end
end
local function clampWindow()
    local vw, vh = viewportSize()
    ProjectState.x = clamp(ProjectState.x, 0, max(0, vw - min(80, ProjectState.w)))
    ProjectState.y = clamp(ProjectState.y, 0, max(0, vh - min(40, ProjectState.h)))
end
local function setOpen(open)
    open = boolv(open)
    if ProjectState.open == open then return end
    ProjectState.open = open
    ProjectState.drag = nil; ProjectState.resizeEdge = nil; ProjectState.sliderDrag = nil
    ProjectState.scrollDrag = nil; ProjectState.dropdown = nil; ProjectState.colorpicker = nil
    ProjectState.cpDrag = nil; ProjectState.focus = nil; ProjectState.keyMenu = nil
    applyInputState(false)
end

local function invoke(cb, ...)
    if type(cb) ~= "function" then return end
    local ok, r = pcall(cb, ...)
    if not ok then
        ProjectState.notifications[#ProjectState.notifications + 1] =
            { title = "error", description = string.lower(tostring(r)), duration = 5, elapsed = 0 }
        return
    end
    return r
end

local function snapValue(raw, item)
    local lo, hi, step = item.min or 0, item.max or 100, item.step or 1
    if step <= 0 then step = 1 end
    local steps = floor(((raw - lo) / step) + 0.5)
    local val = clamp(lo + steps * step, lo, hi)
    if item.float == true then return val end
    -- round to the step's own precision so a fractional step survives: an integer step
    -- gives an integer, a 0.001 step keeps three decimals. (The old code floored to an
    -- int, so a typed 0.1 became 0 and the min-clamp then showed it as 0.001.)
    local p, s = 1, step
    while s < 1 do s = s * 10; p = p * 10 end
    return floor(val * p + 0.5) / p
end
local function setDropdownValue(item, value, fire)
    local nv = copyArray(value)
    local changed = #nv ~= #item.value
    for i = 1, max(#item.value, #nv) do if item.value[i] ~= nv[i] then changed = true break end end
    for i = #item.value, 1, -1 do item.value[i] = nil end
    for i = 1, #nv do item.value[i] = nv[i] end
    if changed and fire ~= false then invoke(item.callback, item.value) end
end
local function setItemValue(item, value, fire)
    if item.type == "dropdown" then setDropdownValue(item, value, fire); return end
    if item.type == "slider" then
        value = tonumber(value) or item.value or item.min or 0
        value = snapValue(value, item)
    elseif item.type == "textbox" then value = tostring(value or "")
    elseif item.type == "checkbox" then value = value == true end
    local changed = item.value ~= value
    item.value = value
    if changed and fire ~= false then invoke(item.callback, value) end
end
local function isItemDisabled(item)
    local dep = item.dependsOn
    if dep and dep.item then
        if not dep.item.value or isItemDisabled(dep.item) then return true end
    end
    return false
end

local doColorPicker, dDropdown

-- ===================== widget model: sections & widget builders =====================
local function makeItem(section, item)
    section.items[#section.items + 1] = item
    item._secName = section.name
    if item.default == nil then
        if item.type == "slider" or item.type == "checkbox" then item.default = item.value
        elseif item.type == "dropdown" then item.default = copyArray(item.value) end
    end
    local handle = { item = item }
    function handle:Set(v) setItemValue(item, v, true); return self end
    function handle:Get() return item.value end
    function handle:IsActivated()
        if item.type == "keybind" then
            local v = item.value
            if not v or v == "" or item.listening then return false end
            local mod, k = parseCombo(v)
            local kIn = Input[k]
            if not kIn then return false end
            if mod then local mIn = Input[mod]; return (mIn ~= nil and mIn.held and kIn.held) == true end
            return kIn.held == true
        end
        local kb = item.keybind
        if kb and kb.callback then return kb.active == true end   -- attached callback-keybind is separate: report ITS held/toggle state, not the widget value
        return item.value == true
    end
    function handle:DependsOn(parent) item.dependsOn = parent; return self end
    function handle:Tooltip(text) item.tooltip = tostring(text or ""); return self end
    function handle:SetText(t) item.label = tostring(t); if item.buttons and item.buttons[1] then item.buttons[1].label = item.label end; return self end
    function handle:SetColor(c) item.color = c; return self end
    function handle:SetRisk(b) item.risk = b ~= false; return self end
    function handle:Reset() if item.default ~= nil then setItemValue(item, item.default, true) end; return self end

    if item.type == "checkbox" then
        function handle:AddKeybind(defaultKey, mode, callback)
            local kb = { value = normalizeKey(defaultKey), mode = normalizeMode(mode),
                         callback = callback, listening = false, active = false }
            item.keybind = kb
            keybindItems[#keybindItems + 1] = item
            local kh = { item = item, keybind = kb }
            function kh:Set(k, m) kb.value = normalizeKey(k); if m then kb.mode = normalizeMode(m) end; return self end
            function kh:IsActivated() if kb.callback then return kb.active == true end; return item.value == true end
            function kh:Parent() return handle end
            handle.keyHandle = kh
            return handle
        end
        function handle:AddColorpicker(label, defaultColor, callback, defaultAlpha)
            item.colorpicker = { label = label or "color", value = defaultColor or Theme.accent,
                                 alpha = defaultAlpha or 1, callback = callback }
            return handle
        end
    end

    if item.type == "dropdown" then
        function handle:UpdateChoices(newChoices)
            item.choices = copyArray(newChoices)
            if ProjectState.dropdown and ProjectState.dropdown.item == item then
                ProjectState.dropdown.choices = copyArray(newChoices)
                ProjectState.dropdown._filterQ = nil; ProjectState.dropdown.scrollOffset = 0
            end
            return self
        end
        function handle:AddChoice(c)
            for i = 1, #item.choices do if item.choices[i] == c then return self end end
            item.choices[#item.choices + 1] = c; return self:UpdateChoices(item.choices)
        end
        function handle:RemoveChoice(c)
            for i = #item.choices, 1, -1 do if item.choices[i] == c then remove(item.choices, i) end end
            for i = #item.value, 1, -1 do if item.value[i] == c then remove(item.value, i) end end
            return self:UpdateChoices(item.choices)
        end
        function handle:SetSearchable(b) item.searchable = b == true; return self end
        function handle:SetMaxSelections(n) item.maxSelections = tonumber(n); return self end
        function handle:ClearChoices() item.choices = {}; if not item.multi then item.value = {} end; return self:UpdateChoices(item.choices) end
    end

    if item.type == "button" then
        function handle:AddButton(label, callback)
            item.buttons[#item.buttons + 1] = { label = tostring(label or "Button"), callback = callback }
            return self
        end
    end
    if item.type == "keybind" then keybindItems[#keybindItems + 1] = item end
    return handle
end

local function createSection(tab, name, side, desc)
    local section = { name = tostring(name or "Section"), side = tostring(side or "Left"), items = {},
        desc = (desc ~= nil and desc ~= "") and tostring(desc) or nil }
    tab.sections[#tab.sections + 1] = section
    local api = { _section = section }
    function api:SetName(t) section.name = tostring(t); return self end
    function api:Label(label, color, tooltip)
        if type(color) == "string" and tooltip == nil then tooltip = color; color = nil end
        local fn = type(label) == "function" and label or nil
        return makeItem(section, { type = "label", labelFn = fn, label = fn and "" or tostring(label or ""), color = color or Theme.sub, tooltip = tooltip })
    end
    function api:Info(text, color)
        return makeItem(section, { type = "info", label = tostring(text or ""), color = color or Theme.sub })
    end
    function api:Divider(label)
        return makeItem(section, { type = "divider", label = label and tostring(label) or nil })
    end
    function api:Button(label, callback, tooltip)
        return makeItem(section, { type = "button", label = tostring(label or "Button"), callback = callback, tooltip = tooltip,
            buttons = { { label = tostring(label or "Button"), callback = callback } } })
    end
    function api:Toggle(label, default, callback, tooltip)
        return makeItem(section, { type = "checkbox", label = tostring(label or "Toggle"), value = default == true, callback = callback, tooltip = tooltip })
    end
    api.Checkbox = api.Toggle
    function api:Slider(label, default, step, minV, maxV, suffix, callback, tooltip)
        local item = { type = "slider", label = tostring(label or "Slider"),
            min = tonumber(minV) or 0, max = tonumber(maxV) or 100, step = tonumber(step) or 1,
            value = tonumber(default) or tonumber(minV) or 0, suffix = suffix or "", callback = callback, tooltip = tooltip }
        item.value = snapValue(item.value, item)
        return makeItem(section, item)
    end
    function api:RangeSlider(label, defLo, defHi, step, minV, maxV, suffix, callback, tooltip)
        local item = { type = "rangeslider", label = tostring(label or "Range"),
            min = tonumber(minV) or 0, max = tonumber(maxV) or 100, step = tonumber(step) or 1,
            valueLo = tonumber(defLo) or tonumber(minV) or 0,
            valueHi = tonumber(defHi) or tonumber(maxV) or 100,
            suffix = suffix or "", callback = callback, tooltip = tooltip }
        item.valueLo = snapValue(item.valueLo, item)
        item.valueHi = snapValue(item.valueHi, item)
        if item.valueLo > item.valueHi then item.valueLo, item.valueHi = item.valueHi, item.valueLo end
        item.defLo, item.defHi = item.valueLo, item.valueHi
        return makeItem(section, item)
    end
    function api:Dropdown(label, default, choices, multi, callback, tooltip, searchable, maxSelections)
        return makeItem(section, { type = "dropdown", label = tostring(label or "Dropdown"),
            value = copyArray(default), choices = copyArray(choices), multi = multi == true,
            searchable = searchable == true, maxSelections = tonumber(maxSelections),
            callback = callback, tooltip = tooltip })
    end
    function api:Colorpicker(label, default, callback, defaultAlpha)
        return makeItem(section, { type = "colorpicker", label = tostring(label or "Color"),
            value = default or Theme.accent, alpha = defaultAlpha or 1, callback = callback })
    end
    function api:Textbox(label, default, callback, tooltip)
        return makeItem(section, { type = "textbox", label = tostring(label or "Textbox"),
            value = tostring(default or ""), callback = callback, tooltip = tooltip })
    end
    function api:Keybind(label, default, callback, tooltip)
        return makeItem(section, { type = "keybind", label = tostring(label or "Keybind"),
            value = normalizeKey(default), listening = false,
            callback = callback, tooltip = tooltip })
    end
    function api:Image(data, height, width)
        return makeItem(section, { type = "image", imageData = data,
            imgHeight = tonumber(height) or 80, imgWidth = tonumber(width) })
    end
    return api
end

-- ===================== public API (Lib:* methods) =====================
local ui = {}
ui.__index = ui

function ui.Notify(a, b, c, d, e)

    local title, desc, dur, typ
    if type(a) == "table" then title, desc, dur, typ = b, c, d, e
    else title, desc, dur, typ = a, b, c, d end
    ProjectState.notifications[#ProjectState.notifications + 1] = {
        title = string.lower(tostring(title or "notification")),
        description = string.lower(tostring(desc or "")),
        duration = tonumber(dur) or ProjectState.notifyDur or 5, elapsed = 0,
        ntype = typ and string.lower(tostring(typ)) or nil }
end
function ui:Dialog(opts)
    opts = opts or {}
    ProjectState.dialog = {
        title = tostring(opts.title or "Confirm"),
        text = tostring(opts.text or ""),
        confirm = tostring(opts.confirm or "Confirm"),
        cancel = tostring(opts.cancel or "Cancel"),
        onConfirm = opts.onConfirm, onCancel = opts.onCancel,
    }
    return self
end
function ui:SetTheme(overrides)
    if type(overrides) == "table" then for k, v in pairs(overrides) do if Theme[k] ~= nil then Theme[k] = v end end end
    return self
end
function ui:SetOpacity(v)
    v = tonumber(v)
    if v then if v > 1 then v = v / 100 end; ProjectState.menuOpacity = clamp(v, 0.4, 1) end
    return self
end
function ui:SetPerformance(on)
    ProjectState.lite = on == true
    return self
end
function ui:IsPerformance() return ProjectState.lite == true end
function ui:SetRounding(v)
    v = tonumber(v)
    if v then if v > 2.5 then v = v / 100 end; ProjectState.roundScale = clamp(v, 0, 2.5) end
    return self
end
function ui:GetRounding() return ProjectState.roundScale or 1 end
function ui:SetRowLines(on) ProjectState.rowLines = on == true; return self end
function ui:SetAutoSave(on) ProjectState.autoSave = on == true; return self end
function ui:SetMenuKey(key)
    if type(key) == "number" or (type(key) == "string" and tonumber(key)) then
        local vk = tonumber(key)
        for name, inp in pairs(Input) do if inp.id == vk then key = name break end end
    end
    menuKey = normalizeKey(key) or "p"
    return self
end
function ui:IsOpen() return ProjectState.open == true end
function ui:SetOpen(b) setOpen(b == true); return self end
function ui:_dbgFocus(h) local it = (type(h) == "table" and h.item) or h; if it then ProjectState.focus = it; it.caret = 0; it.selA = nil end return self end
function ui:_dbgOpenDropdown(h) local it = (type(h) == "table" and h.item) or h; if it then dDropdown(120, 120, 180, it) end return self end
function ui:OpenColorpicker(h)
    local item = (type(h) == "table" and h.item) or h
    if item and item.type == "colorpicker" then doColorPicker(ProjectState.x + 80, ProjectState.y + 80, item) end
    return self
end
function ui:OpenSpotlight(open)
    ProjectState.spotlightOpen = open ~= false
    if ProjectState.spotlightOpen then ProjectState.spotlight = { query = "", sel = 1 } end
    return self
end
function ui:AvatarLog() return table.concat(ProjectState._avLog or { "avatar task has not run yet" }, "\n") end
function ui:SetGameInput(on) ProjectState.gameInput = (on == "always") and "always" or (on ~= false); return self end
function ui:OpenSettings()
    if ProjectState.settingsTab and ProjectState.activeTab ~= ProjectState.settingsTab then
        ProjectState._prevTab = ProjectState.activeTab; ProjectState._prevIndex = ProjectState.activeIndex
        ProjectState.activeTab = ProjectState.settingsTab; ProjectState.activeIndex = ProjectState.settingsIndex or #ProjectState.tabs
        ProjectState.contentFade = 0
    end
    return self
end
function ui:SetTitle(t) ProjectState.title = tostring(t or "uilib"); return self end
function ui:SetSize(w, h)
    if tonumber(w) then ProjectState.w = max(80, tonumber(w)); ProjectState.wTarget = ProjectState.w end
    if tonumber(h) then ProjectState.h = max(80, tonumber(h)); ProjectState.hTarget = ProjectState.h end
    return self
end
function ui:SetPos(x, y)
    if tonumber(x) then ProjectState.x = tonumber(x) end
    if tonumber(y) then ProjectState.y = tonumber(y) end
    return self
end
ui.SetPosition = ui.SetPos
function ui:Center()
    local vw, vh = viewportSize()
    ProjectState.x = floor(vw / 2 - ProjectState.w / 2)
    ProjectState.y = floor(vh / 2 - ProjectState.h / 2)
    return self
end
function ui:Tab(name, icon)
    local tab = { name = tostring(name or ("Tab " .. (#ProjectState.tabs + 1))), icon = icon, sections = {}, scrollY = 0, targetScrollY = 0, maxScroll = 0 }
    ProjectState.tabs[#ProjectState.tabs + 1] = tab
    if not ProjectState.activeTab then ProjectState.activeTab = tab; ProjectState.activeIndex = #ProjectState.tabs end
    local tabApi = { _tab = tab }
    function tabApi:Section(secName, side, desc) return createSection(tab, secName, side, desc) end
    return tabApi
end

function ui:CreateBox(opts)
    opts = type(opts) == "table" and opts or {}
    ProjectState.boxes = ProjectState.boxes or {}
    local box = { title = tostring(opts.title or "Box"), lines = {}, visible = opts.visible ~= false, alive = true,
        x = (opts.position and opts.position.X) or opts.x or 20,
        y = (opts.position and opts.position.Y) or opts.y or 140, width = opts.width or opts.w }
    ProjectState.boxes[#ProjectState.boxes + 1] = box
    local api = { _box = box }
    function api:Text(value, color)
        local ln = { value = value, color = color }; box.lines[#box.lines + 1] = ln
        return { Set = function(_, t) ln.value = t end, SetColor = function(_, c) ln.color = c end }
    end
    api.Label = api.Text
    function api:Stat(value, color)
        local ln = { kind = "stat", value = value, color = color }
        box.lines[#box.lines + 1] = ln
        return { Set = function(_, t) ln.value = t end, SetColor = function(_, c) ln.color = c end }
    end
    function api:Bar(value, color)
        local ln = { kind = "bar", value = value, color = color }
        box.lines[#box.lines + 1] = ln
        return { Set = function(_, v) ln.value = v end, SetColor = function(_, c) ln.color = c end }
    end
    function api:SetVisible(b) box.visible = b ~= false; return self end
    function api:Toggle() box.visible = not box.visible; return self end
    function api:SetTitle(t) box.title = tostring(t); return self end
    function api:Clear() box.lines = {}; return self end
    function api:Remove()
        box.alive = false
        for i, b in ipairs(ProjectState.boxes) do if b == box then remove(ProjectState.boxes, i) break end end
    end
    return api
end
local function splitPath(s) local p = {}; for part in string.gmatch(s, "[^%.]+") do p[#p + 1] = part end return p end
function ui:GetValue(path)
    local p = splitPath(tostring(path)); if #p < 3 then return nil end
    for _, t in ipairs(ProjectState.tabs) do if t.name == p[1] then
        for _, s in ipairs(t.sections) do if s.name == p[2] then
            for _, it in ipairs(s.items) do if it.label == p[3] then return it.value end end
        end end
    end end
    return nil
end
function ui:SetValue(path, value)
    local p = splitPath(tostring(path)); if #p < 3 then return self end
    for _, t in ipairs(ProjectState.tabs) do if t.name == p[1] then
        for _, s in ipairs(t.sections) do if s.name == p[2] then
            for _, it in ipairs(s.items) do if it.label == p[3] then setItemValue(it, value, true); return self end end
        end end
    end end
    return self
end

local function updateInput()
    ProjectState.mouseScroll = 0
    local active = true
    pcall(function() active = isrbxactive() end)

    for _, name in ipairs(InputOrder) do local inp = Input[name]; inp.click = false; inp.released = false end

    local m1 = active and ismouse1() or false
    local m2 = active and ismouse2() or false
    Input.m1.click = m1 and not Input.m1.held; Input.m1.released = (not m1) and Input.m1.held; Input.m1.held = m1
    Input.m2.click = m2 and not Input.m2.held; Input.m2.released = (not m2) and Input.m2.held; Input.m2.held = m2

    local pollAll = ProjectState.open or ProjectState.focus ~= nil
    if not pollAll then
        for _, item in ipairs(keybindItems) do if item.keybind and item.keybind.listening then pollAll = true break end end
    end
    if pollAll then
        for _, name in ipairs(InputOrder) do
            if name ~= "m1" and name ~= "m2" then
                local inp = Input[name]
                local down = active and iskeypressed(inp.id) or false
                inp.click = down and not inp.held; inp.released = (not down) and inp.held; inp.held = down
            end
        end
    else
        local keys = {}
        keys[menuKey] = true
        for _, item in ipairs(keybindItems) do
            local kb = item.keybind
            if kb and kb.value then
                if kb._pcSrc ~= kb.value then kb._pcSrc = kb.value; kb._pcMod, kb._pcKey = parseCombo(kb.value) end
                if kb._pcMod then keys[kb._pcMod] = true end
                if kb._pcKey then keys[kb._pcKey] = true end
            elseif item.type == "keybind" and item.value and item.value ~= "" then
                if item._pcSrc ~= item.value then item._pcSrc = item.value; item._pcMod, item._pcKey = parseCombo(item.value) end
                if item._pcMod then keys[item._pcMod] = true end
                if item._pcKey then keys[item._pcKey] = true end
            end
        end
        for name in pairs(keys) do
            local inp = Input[name]
            if inp and name ~= "m1" and name ~= "m2" then
                local down = active and iskeypressed(inp.id) or false
                inp.click = down and not inp.held; inp.released = (not down) and inp.held; inp.held = down
            end
        end
    end
end

local function shiftHeld() return Input.shift.held or Input.lshift.held or Input.rshift.held end
local function ctrlHeld() return Input.ctrl.held or Input.lctrl.held or Input.rctrl.held end
local function keyRepeats(name)
    local inp = Input[name]
    if not inp then return false end
    if inp.click then ProjectState.repeatKey = name; ProjectState.repeatAt = (clock() or 0) + 0.4; return true end
    if inp.held and ProjectState.repeatKey == name and (clock() or 0) >= ProjectState.repeatAt then
        ProjectState.repeatAt = (clock() or 0) + 0.035; return true
    end
    return false
end

local function editText(obj, field, numeric, hexOnly)
    local value = obj[field] or ""
    obj.caret = clamp(obj.caret or #value, 0, #value)
    local caret = obj.caret
    local selA = obj.selA
    local hasSel = selA ~= nil and selA ~= caret
    local selLo = hasSel and min(selA, caret) or caret
    local selHi = hasSel and max(selA, caret) or caret
    local changed = false
    local sh = shiftHeld()
    local function deleteSel()
        value = string.sub(value, 1, selLo) .. string.sub(value, selHi + 1)
        caret = selLo; selA = nil; hasSel = false; changed = true
    end
    local function done() obj.caret = clamp(caret, 0, #value); obj.selA = selA; obj[field] = value; return changed end

    if ctrlHeld() then
        if Input.a.click then selA = 0; caret = #value; Input.a.click = false
        elseif Input.c.click then if hasSel then pcall(setclipboard, string.sub(value, selLo + 1, selHi)) end; Input.c.click = false
        elseif Input.x.click then if hasSel then pcall(setclipboard, string.sub(value, selLo + 1, selHi)); deleteSel() end; Input.x.click = false
        elseif Input.v.click then
            Input.v.click = false
            local clip; if getclipboard then local ok, c = pcall(getclipboard); if ok then clip = c end end
            if type(clip) == "string" and clip ~= "" then
                if numeric then clip = clip:gsub("[^0-9%.%-]", "") elseif hexOnly then clip = clip:gsub("[^0-9a-fA-F]", "") end
                if hasSel then deleteSel() end
                value = string.sub(value, 1, caret) .. clip .. string.sub(value, caret + 1); caret = caret + #clip; changed = true
            end
        end
        return done()
    end
    if Input.left.click or Input.right.click or Input.home.click or Input["end"].click then
        local nc = caret
        if Input.left.click then nc = (hasSel and not sh) and selLo or max(0, caret - 1) end
        if Input.right.click then nc = (hasSel and not sh) and selHi or min(#value, caret + 1) end
        if Input.home.click then nc = 0 end
        if Input["end"].click then nc = #value end
        if sh then selA = selA or caret else selA = nil end
        caret = nc
        Input.left.click = false; Input.right.click = false; Input.home.click = false; Input["end"].click = false
        return done()
    end
    if Input.delete.click then
        if hasSel then deleteSel() elseif caret < #value then value = string.sub(value, 1, caret) .. string.sub(value, caret + 2); selA = nil; changed = true end
        Input.delete.click = false
    end
    if keyRepeats("backspace") then
        if hasSel then deleteSel() elseif caret > 0 then value = string.sub(value, 1, caret - 1) .. string.sub(value, caret + 1); caret = caret - 1; selA = nil; changed = true end
    end
    if not changed then
        for _, name in ipairs(InputOrder) do
            local inp = Input[name]
            if inp.char then
                local doIt = inp.click or (inp.held and ProjectState.repeatKey == name and (clock() or 0) >= ProjectState.repeatAt)
                if doIt then
                    local ch = (sh and inp.shifted) or inp.char
                    if numeric and not ch:match("[0-9%.%-]") then ch = "" elseif hexOnly and not ch:match("[0-9a-fA-F]") then ch = "" end
                    if ch ~= "" then if hasSel then deleteSel() end; value = string.sub(value, 1, caret) .. ch .. string.sub(value, caret + 1); caret = caret + 1; selA = nil; changed = true end
                    if inp.click then ProjectState.repeatKey = name; ProjectState.repeatAt = (clock() or 0) + 0.4; inp.click = false
                    else ProjectState.repeatAt = (clock() or 0) + 0.035 end
                    break
                end
            end
        end
    end
    return done()
end

local EDIT_FONT = FontUI
local EDIT_MULT = FontWidths[FontUI] or 0.50
local function editCharW(size) return (size or 13) * EDIT_MULT end
local function editCaretAtX(obj, value, mouseX)
    local cw = obj._ecw or editCharW(13)
    return clamp((obj._es or 0) + floor((mouseX - (obj._ex or 0)) / cw + 0.5), 0, #tostring(value or ""))
end
local function drawEditable(obj, value, fx, yText, size, color, alpha, z, fieldW, focused, caretIdx, selA)
    value = tostring(value or "")
    local cw = editCharW(size)
    local n = #value
    caretIdx = clamp(caretIdx or n, 0, n)
    local cap = max(1, floor(fieldW / cw))
    local scroll = 0
    if focused and caretIdx > cap then scroll = caretIdx - cap end
    obj._ecw = cw; obj._ex = fx; obj._es = scroll
    local last = min(n, scroll + cap)
    local hasSel = focused and selA and selA ~= caretIdx
    local vis = string.sub(value, scroll + 1, last)

    for i = 1, #vis do
        txt(string.sub(vis, i, i), fx + (i - 1) * cw, yText, color, size, EDIT_FONT, z, false, false, nil, alpha)
    end
    if focused and not hasSel and (((clock() or 0) % 1) < 0.55) then
        rect(fx + clamp(caretIdx - scroll, 0, #vis) * cw, yText, 1, size, color, z, 0, alpha)
    end

    if hasSel then
        local lo, hi = min(selA, caretIdx), max(selA, caretIdx)
        local vlo = clamp(lo - scroll, 0, #vis)
        local vhi = clamp(hi - scroll, 0, #vis)
        rect(fx + vlo * cw, yText - 1, max(1, (vhi - vlo) * cw), size + 4, ProjectState._accentMid, z, 3, (vhi > vlo) and (0.45 * alpha) or 0)
    end
end

local function processTextInput()
    local item = ProjectState.focus
    if not item then return end
    if item == ProjectState.dropdown and item.searchable then
        if Input.enter.click or Input.esc.click then ProjectState.focus = nil; Input.enter.click = false; Input.esc.click = false; return end
        if editText(item, "searchQuery", false) then item.scrollOffset = 0 end
        return
    end
    if type(item) ~= "table" or (item.type ~= "textbox" and item.type ~= "slider") then return end
    if Input.enter.click or Input.esc.click then
        if item.type == "slider" and item.directValue then
            if Input.enter.click then setItemValue(item, tonumber(item.directValue) or item.value, true) end
            item.directValue = nil
        end
        ProjectState.focus = nil; item.selA = nil
        Input.enter.click = false; Input.esc.click = false
        return
    end
    if item.type == "textbox" then
        if editText(item, "value", false) then invoke(item.callback, item.value) end
    else
        editText(item, "directValue", true)
    end
end

local function processKeybinds()
    if ProjectState.focus then return end
    for _, item in ipairs(keybindItems) do
        local kb = item.keybind
        if kb and kb.value and not kb.listening and not isItemDisabled(item) then
            if kb._pcSrc ~= kb.value then kb._pcSrc = kb.value; kb._pcMod, kb._pcKey = parseCombo(kb.value) end
            local mod, k = kb._pcMod, kb._pcKey
            local kIn = Input[k]
            local mIn = mod and Input[mod] or nil
            if kIn then
                if kb.callback then
                    -- got a callback -> it's a standalone bind, run its own state and leave the toggle alone
                    local act = kb.active or false
                    if mod and not mIn then
                        -- modifier's not down, ignore
                    elseif kb.mode == "Always" then
                        act = true
                    elseif kb.mode == "Toggle" then
                        local fire = mod and (mIn.held and kIn.click) or (not mod and kIn.click)
                        if fire then act = not kb.active end
                    else
                        act = (mod and (mIn.held and kIn.held)) or (not mod and kIn.held) or false
                    end
                    if act ~= kb.active then kb.active = act; invoke(kb.callback, act) end
                else
                    -- no callback, so it just drives the toggle like before
                    if mod and not mIn then

                    elseif kb.mode == "Always" then
                        setItemValue(item, true, true)
                    elseif kb.mode == "Toggle" then
                        local fire = mod and (mIn.held and kIn.click) or (not mod and kIn.click)
                        if fire then setItemValue(item, not item.value, true) end
                    else
                        setItemValue(item, (mod and (mIn.held and kIn.held)) or (not mod and kIn.held) or false, true)
                    end
                end
            end
        end
    end
end


-- ===================== popups: dropdown / colour picker / keybind menu =====================
function dDropdown(x, y, w, item)
    local rowH = 26
    local searchable = item.searchable == true
    local headerH = searchable and 30 or 0
    local visible = min(#item.choices, 8)
    local h = max(rowH, visible * rowH) + 8 + headerH
    local vw, vh = viewportSize()
    x = clamp(x, 8, max(8, vw - w - 8)); y = clamp(y, 8, max(8, vh - h - 8))
    ProjectState.dropdown = { item = item, choices = copyArray(item.choices), value = item.value,
        x = x, y = y, w = w, h = h, rowH = rowH, multi = item.multi, scrollOffset = 0, anim = 0,
        searchable = searchable, headerH = headerH, searchQuery = "" }
    ProjectState.colorpicker = nil
    if searchable then ProjectState.focus = ProjectState.dropdown end
end
function doColorPicker(x, y, picker)
    local w, h = 212, 230
    local vw, vh = viewportSize()
    x = clamp(x, 8, max(8, vw - w - 8)); y = clamp(y, 8, max(8, vh - h - 8))
    local hh, ss, vv = toHsv(picker.value)
    ProjectState.colorpicker = { picker = picker, x = x, y = y, w = w, h = h, hue = hh, sat = ss, val = vv, alpha = picker.alpha or 1, anim = 0 }
    ProjectState.dropdown = nil
end

local function drawDropdown(click, rightClick)
    local dd = ProjectState.dropdown
    if not dd then return click, rightClick end
    dd.anim = approach(dd.anim or 0, dd.closing and 0 or 1, 9)
    if dd.closing and dd.anim < 0.02 then
        if ProjectState.focus == dd then ProjectState.focus = nil end
        ProjectState.dropdown = nil; return click, rightClick
    end
    local a = dd.anim
    local x, y, w, h = dd.x, dd.y + (1 - a) * -6, dd.w, dd.h
    local rowH, headerH = dd.rowH, dd.headerH or 0

    local list = dd.choices
    if dd.searchable and dd.searchQuery ~= "" then
        if dd.searchQuery ~= dd._filterQ then
            dd._filterQ = dd.searchQuery
            local q = string.lower(dd.searchQuery); local f = {}
            for _, c in ipairs(dd.choices) do if string.find(string.lower(tostring(c)), q, 1, true) then f[#f + 1] = c end end
            dd._filtered = f
        end
        list = dd._filtered
    end
    local maxRows = max(1, floor((h - 8 - headerH) / rowH))
    local hovered = over(x - 4, y - 4, w + 8, h + 8)
    if hovered and ProjectState.mouseScroll ~= 0 then
        dd.scrollOffset = dd.scrollOffset - (ProjectState.mouseScroll > 0 and 1 or -1)
    end
    dd.scrollOffset = clamp(dd.scrollOffset, 0, max(0, #list - maxRows))
    rect(x, y, w, h, Theme.bg, 200, 8, 0.97 * a)
    strokeRect(x, y, w, h, WHITE, 201, 8, AL.cardStrk * a)

    if dd.searchable then
        local focused = ProjectState.focus == dd
        rect(x + 6, y + 5, w - 12, 22, WHITE, 202, 6, AL.field * a)
        strokeRect(x + 6, y + 5, w - 12, 22, WHITE, 203, 6, (focused and 0.4 or AL.hairline) * a)
        local q = dd.searchQuery
        if q == "" and not focused then
            txt("search...", x + 14, textTop(y + 5, 22, 13), WHITE, 13, FontSystem, 204, false, false, w - 28, 0.3 * a)
        else
            drawEditable(dd, q, x + 14, textTop(y + 5, 22, 13), 13, WHITE, AL.dim * a, 204, w - 30, focused, dd.caret, dd.selA)
        end
        if click and over(x + 6, y + 5, w - 12, 22) then ProjectState.focus = dd; dd.caret = editCaretAtX(dd, q, ProjectState.mouseX); dd.selA = dd.caret; ProjectState.textDrag = dd; click = false end
        if Input.m1.held and ProjectState.textDrag == dd then dd.caret = editCaretAtX(dd, q, ProjectState.mouseX) end
    end
    local rowsTop = y + 4 + headerH
    local now = clock() or 0
    local accentMid = ProjectState._accentMid
    local rowW2 = (#list > maxRows) and (w - 18) or (w - 8)
    dd._sy = approach(dd._sy or dd.scrollOffset, dd.scrollOffset, 16)
    local sy = dd._sy
    local areaH = maxRows * rowH
    for off = 0, maxRows do
        local ai = floor(sy) + off
        local choice = (ai >= 0) and list[ai + 1] or nil
        if choice then
            local ryRaw = rowsTop + (ai - sy) * rowH
            if ryRaw + rowH > rowsTop and ryRaw < rowsTop + areaH then
                local edgeA = clamp((ryRaw + rowH - rowsTop) / rowH, 0, 1) * clamp((rowsTop + areaH - ryRaw) / rowH, 0, 1)
                local casc = clamp((a - off * 0.07) / 0.4, 0, 1)
                local ra = casc * edgeA
                local ry = ryRaw + (1 - casc) * 12
                local sel = false
                for _, vv in ipairs(dd.value) do if vv == choice then sel = true break end end
                local rowHover = ryRaw >= rowsTop - 2 and ryRaw + rowH <= rowsTop + areaH + 2 and over(x + 4, ry, rowW2, rowH - 2)
                rect(x + 4, ry, rowW2, rowH - 2, accentMid, 202, 6, ((dd._pressRow == ai and dd._pressT and dd._pressT > now) and (0.45 * ((dd._pressT - now) / 0.3)) or 0) * ra)
                rect(x + 4, ry, rowW2, rowH - 2, WHITE, 202, 6, (sel and 0.05 or 0) * ra)
                rect(x + 4, ry, rowW2, rowH - 2, accentMid, 202, 6, (rowHover and 0.16 or 0) * ra)
                txt(choice, x + 12, textTop(ry, rowH - 2, 13), WHITE, 13, FontSystem, 203, false, false, w - 42, ((rowHover or sel) and AL.text or AL.label) * ra)
                if sel then
                    local ckx, cky = x + 4 + rowW2 - 14, ry + (rowH - 2) / 2 + 1
                    lineD(ckx, cky, ckx + 3, cky + 3, WHITE, 204, 1.5, AL.text * ra)
                    lineD(ckx + 3, cky + 3, ckx + 8, cky - 4, WHITE, 204, 1.5, AL.text * ra)
                end
                if click and rowHover and not dd.closing then
                    dd._pressRow = ai; dd._pressT = now + 0.3
                    if dd.multi then
                        local nv = copyArray(dd.value)
                        local found
                        for i = #nv, 1, -1 do if nv[i] == choice then found = i end end
                        if found then remove(nv, found)
                        elseif not dd.item.maxSelections or #nv < dd.item.maxSelections then nv[#nv + 1] = choice end
                        setDropdownValue(dd.item, nv, true); dd.value = dd.item.value
                    else
                        setDropdownValue(dd.item, { choice }, true); dd.closing = true; ProjectState.focus = nil
                    end
                    click = false
                end
            end
        end
    end

    local maxOff = max(0, #list - maxRows)
    if dd._sbDrag and not Input.m1.held then dd._sbDrag = nil end
    if maxOff > 0 then
        local trackY, trackH, sbX = rowsTop + 1, maxRows * rowH - 4, x + w - 6
        rect(sbX, trackY, 3, trackH, WHITE, 204, 2, 0.05 * a)
        local thumbH = max(22, trackH * maxRows / #list)
        local targetY = trackY + (trackH - thumbH) * (dd.scrollOffset / maxOff)
        dd._sbY = approach(dd._sbY or targetY, targetY, 18)
        local sbHot = over(sbX - 6, trackY, 12, trackH) or dd._sbDrag
        rect(sbX, dd._sbY, 3, thumbH, WHITE, 205, 2, (sbHot and 0.5 or 0.22) * a)
        if click and over(sbX - 6, trackY, 12, trackH) then dd._sbDrag = true; click = false end
        if dd._sbDrag and Input.m1.held then
            local frac = clamp((ProjectState.mouseY - trackY - thumbH / 2) / max(1, trackH - thumbH), 0, 1)
            dd.scrollOffset = floor(frac * maxOff + 0.5)
        end
    end

    if dd.multi and rightClick and hovered then dd.ctx = { x = ProjectState.mouseX, y = ProjectState.mouseY }; rightClick = false end
    if dd.ctx then
        local cx, cy, cw = dd.ctx.x, dd.ctx.y, 110
        rect(cx, cy, cw, 52, Theme.bg, 206, 6, 0.98 * a)
        strokeRect(cx, cy, cw, 52, WHITE, 207, 6, AL.cardStrk * a)
        for i, o in ipairs({ "Select All", "Clear All" }) do
            local oy = cy + 4 + (i - 1) * 24
            local oh = over(cx + 3, oy, cw - 6, 22)
            rect(cx + 3, oy, cw - 6, 22, WHITE, 207, 5, (oh and 0.05 or 0) * a)
            txt(o, cx + 10, textTop(oy, 22, 12), WHITE, 12, FontSystem, 208, false, false, cw - 16, AL.label * a)
            if click and oh then
                if i == 1 then
                    local nv = {}
                    for _, c in ipairs(dd.choices) do if not dd.item.maxSelections or #nv < dd.item.maxSelections then nv[#nv + 1] = c end end
                    setDropdownValue(dd.item, nv, true)
                else setDropdownValue(dd.item, {}, true) end
                dd.value = dd.item.value; dd.ctx = nil; click = false
            end
        end
        if click and not over(cx - 4, cy - 4, cw + 8, 60) then dd.ctx = nil; click = false end
    end
    if click and not hovered and not dd.ctx and not dd.closing then dd.closing = true; ProjectState.focus = nil; click = false end
    return click, rightClick
end

local function drawColorpicker(click, held)
    local cp = ProjectState.colorpicker
    if not cp then return click end
    cp.anim = approach(cp.anim or 0, 1, 22)
    local a = cp.anim
    local x, y, w, h = cp.x, cp.y + (1 - a) * -6, cp.w, cp.h
    rect(x, y, w, h, Theme.bg, 210, 8, 0.97 * a)
    strokeRect(x, y, w, h, WHITE, 211, 8, AL.cardStrk * a)
    local pad = 12
    local boxX, boxY = x + pad, y + pad
    local boxW, boxH = w - pad * 2, h - 90
    local pure = hsv(cp.hue, 1, 1)

    local strips = clamp(floor(boxW), 40, 160)
    for i = 0, strips - 1 do
        local x0 = floor(boxX + boxW * i / strips + 0.5); local x1 = floor(boxX + boxW * (i + 1) / strips + 0.5)
        if x1 > x0 then rect(x0, boxY, x1 - x0, boxH, lerpColor(WHITE, pure, i / (strips - 1)), 212, 0, a) end
    end
    local vS = clamp(floor(boxH), 40, 140)
    for j = 1, vS - 1 do
        local y0 = floor(boxY + boxH * j / vS + 0.5); local y1 = floor(boxY + boxH * (j + 1) / vS + 0.5)
        if y1 > y0 then rect(boxX, y0, boxW, y1 - y0, c3(0, 0, 0), 213, 0, (j / (vS - 1)) * 0.92 * a) end
    end
    circ(boxX + cp.sat * boxW, boxY + (1 - cp.val) * boxH, 4, WHITE, 214, false, 1.5, 20, a)
    local hueY = boxY + boxH + 12
    local segs = clamp(floor(boxW), 40, 160)
    for i = 0, segs - 1 do
        local x0 = floor(boxX + boxW * i / segs + 0.5); local x1 = floor(boxX + boxW * (i + 1) / segs + 0.5)
        if x1 > x0 then rect(x0, hueY, x1 - x0, 12, hsv(i / (segs - 1), 1, 1), 213, 0, a) end
    end
    rect(boxX + cp.hue * boxW - 1, hueY - 2, 3, 16, WHITE, 214, 1, a)
    local alphaY = hueY + 20
    local cur = hsv(cp.hue, cp.sat, cp.val)
    for i = 0, segs - 1 do
        local x0 = floor(boxX + boxW * i / segs + 0.5); local x1 = floor(boxX + boxW * (i + 1) / segs + 0.5)
        if x1 > x0 then rect(x0, alphaY, x1 - x0, 12, cur, 213, 0, (i / (segs - 1)) * a) end
    end
    rect(boxX + cp.alpha * boxW - 1, alphaY - 2, 3, 16, WHITE, 214, 1, a)

    local pvY = alphaY + 18
    rect(boxX, pvY, 34, 16, c3(40, 40, 40), 213, 3, a)
    rect(boxX, pvY, 34, 16, cur, 214, 3, a * cp.alpha)
    strokeRect(boxX, pvY, 34, 16, WHITE, 214, 3, AL.hairline * a)
    local hxX, hxW = boxX + 42, boxW - 42
    local editing = cp.hexInput ~= nil
    local hexStr = editing and ("#" .. cp.hexInput)
        or (toHex(cur) .. ((cp.alpha or 1) < 0.999 and string.format("%02X", floor(clamp(cp.alpha, 0, 1) * 255 + 0.5)) or ""))
    local hxHov = over(hxX, pvY, hxW, 16)
    rect(hxX, pvY, hxW, 16, WHITE, 213, 4, (editing and 0.08 or AL.field) * a)
    strokeRect(hxX, pvY, hxW, 16, WHITE, 214, 4, (editing and 0.4 or (hxHov and 0.25 or AL.hairline)) * a)
    if editing then
        drawEditable(cp, cp.hexInput, hxX + 8, textTop(pvY, 16, 12), 12, WHITE, AL.text * a, 214, hxW - 16, true, cp.caret, cp.selA)
    else
        txt(hexStr, hxX + 8, textTop(pvY, 16, 12), WHITE, 12, FontMono, 214, false, false, hxW - 14, AL.text * a)
    end
    if held and not editing then
        if ProjectState.cpDrag == "sv" or over(boxX, boxY, boxW, boxH) then
            ProjectState.cpDrag = "sv"
            cp.sat = clamp((ProjectState.mouseX - boxX) / boxW, 0, 1)
            cp.val = clamp(1 - (ProjectState.mouseY - boxY) / boxH, 0, 1)
        elseif ProjectState.cpDrag == "hue" or over(boxX, hueY, boxW, 12) then
            ProjectState.cpDrag = "hue"; cp.hue = clamp((ProjectState.mouseX - boxX) / boxW, 0, 1)
        elseif ProjectState.cpDrag == "alpha" or over(boxX, alphaY, boxW, 12) then
            ProjectState.cpDrag = "alpha"; cp.alpha = clamp((ProjectState.mouseX - boxX) / boxW, 0, 1)
        end
        local nc = hsv(cp.hue, cp.sat, cp.val)
        if colorChanged(cp.picker.value, nc) or abs((cp.picker.alpha or 1) - cp.alpha) > 0.001 then
            cp.picker.value = nc; cp.picker.alpha = cp.alpha
            invoke(cp.picker.callback, nc, cp.alpha)
        end
    end
    if not held then ProjectState.cpDrag = nil end
    local function applyHex()
        local raw = string.gsub(tostring(cp.hexInput or ""), "[^0-9a-fA-F]", "")
        local c = parseHex(cp.hexInput)
        if c then local hh, ss, vv = toHsv(c); cp.hue = hh; cp.sat = ss; cp.val = vv
            if #raw >= 8 then local av = tonumber(string.sub(raw, 7, 8), 16); if av then cp.alpha = av / 255 end end
            cp.picker.value = c; invoke(cp.picker.callback, c, cp.alpha) end
        cp.hexInput = nil
    end
    if click and hxHov then
        cp.hexInput = string.sub(string.gsub(hexStr, "#", ""), 1, 8)
        cp.caret = #cp.hexInput; cp.selA = cp.caret; ProjectState.cpHexDrag = true; click = false
    elseif editing then
        if Input.enter.click then applyHex(); Input.enter.click = false
        elseif Input.esc.click then cp.hexInput = nil; Input.esc.click = false
        elseif click and not over(x - 4, y - 4, w + 8, h + 8) then applyHex()
        else editText(cp, "hexInput", false, true) end
    end
    if editing and Input.m1.held and ProjectState.cpHexDrag then cp.caret = editCaretAtX(cp, cp.hexInput, ProjectState.mouseX) end
    if not held then ProjectState.cpHexDrag = nil end
    if click and not over(x - 4, y - 4, w + 8, h + 8) then ProjectState.colorpicker = nil; click = false end
    return click
end

local KEY_MODES = { "Hold", "Toggle", "Always" }
local function drawKeyMenu(click)
    local km = ProjectState.keyMenu
    if not km then return click end
    km.anim = approach(km.anim or 0, 1, 22)
    local a = km.anim
    local w, rowH = 96, 24
    local h = #KEY_MODES * rowH + 8
    local vw, vh = viewportSize()
    local x = clamp(km.x, 8, max(8, vw - w - 8))
    local y = clamp(km.y, 8, max(8, vh - h - 8)) + (1 - a) * -6
    rect(x, y, w, h, Theme.bg, 250, 8, 0.97 * a)
    strokeRect(x, y, w, h, WHITE, 251, 8, AL.cardStrk * a)
    for i, mode in ipairs(KEY_MODES) do
        local ry = y + 4 + (i - 1) * rowH
        local sel = km.kb.mode == mode
        local hov = over(x + 4, ry, w - 8, rowH - 2)
        rect(x + 4, ry, w - 8, rowH - 2, WHITE, 252, 6, ((hov or sel) and (sel and 0.06 or 0.04) or 0) * a)
        txt(mode, x + 12, textTop(ry, rowH - 2, 13), WHITE, 13, FontSystem, 253, false, false, w - 20, (sel and AL.text or AL.label) * a)
        if click and hov then km.kb.mode = mode; ProjectState.keyMenu = nil; click = false end
    end
    if click and not over(x - 4, y - 4, w + 8, h + 8) then ProjectState.keyMenu = nil; click = false end
    return click
end

local function drawHotkeyOverlay(click, held)
    if ProjectState.hotkeyEnabled == false then return click end
    if not ProjectState._winReady then return click end
    local rows = {}
    for _, item in ipairs(keybindItems) do
        local kb = item.keybind
        local on = kb and kb.value and kb.value ~= "" and item.value == true   -- only currently-active binds
        item._hkA = approach(item._hkA or 0, on and 1 or 0, 16)
        if item._hkA > 0.02 then
            local lbl = item.label or ""
            local low = string.lower(lbl)
            if (low == "enabled" or low == "enable" or low == "active" or low == "on") and item._secName and item._secName ~= "" then lbl = item._secName end
            rows[#rows + 1] = { label = lbl, key = (kb and kb.value) and keyLabel(kb.value) or "", ra = item._hkA }
        end
    end
    local rowsH = 0
    for _, r in ipairs(rows) do rowsH = rowsH + r.ra end
    ProjectState.hkFade = approach(ProjectState.hkFade or 0, 1, 14)   -- overlay enabled => box stays visible even with no active binds
    local a = ProjectState.hkFade
    if a < 0.02 then return click end
    local w, rowH = 180, 20
    local h = 30 + (#rows == 0 and 0 or rowsH * rowH) + 6
    ProjectState.hkPos = ProjectState.hkPos or { x = 18, y = 90 }

    if held and ProjectState.hkDrag then
        ProjectState.hkDrag.tx = ProjectState.mouseX - ProjectState.hkDrag.ox
        ProjectState.hkDrag.ty = ProjectState.mouseY - ProjectState.hkDrag.oy
    end
    if ProjectState.hkDrag and ProjectState.hkDrag.tx then
        ProjectState.hkPos.x = approach(ProjectState.hkPos.x, ProjectState.hkDrag.tx, 28)
        ProjectState.hkPos.y = approach(ProjectState.hkPos.y, ProjectState.hkDrag.ty, 28)
    end
    local hvw, hvh = viewportSize()
    ProjectState.hkPos.x = clamp(ProjectState.hkPos.x, 0, max(0, hvw - w))
    ProjectState.hkPos.y = clamp(ProjectState.hkPos.y, 0, max(0, hvh - h))
    local x, y = ProjectState.hkPos.x, ProjectState.hkPos.y
    rect(x, y, w, h, Theme.bg, 150, 8, 0.92 * a)
    strokeRect(x, y, w, h, WHITE, 151, 8, AL.cardStrk * a)
    txt("keybinds", x + 12, y + 9, WHITE, 12, FontBold, 152, false, false, w - 24, AL.text * a)
    gradRectH(x + 10, y + 26, w - 20, 2, Theme.accentA, Theme.accentB, 152, 0.9 * a)
    local yc = y + 30
    for _, r in ipairs(rows) do
        local rA = r.ra * a
        local slide = (1 - r.ra) * 12
        local ry = yc
        circ(x + 14 + slide, ry + rowH / 2, 2.5, Theme.accentA, 152, true, 1, 10, rA)
        txt(r.label, x + 22 + slide, textTop(ry, rowH, 12), WHITE, 12, FontSystem, 152, false, false, w - 92, AL.text * rA)
        local kt = r.key
        local ktw = max(18, textWidth(kt, 11, FontMono) + 12)
        local kx = x + w - 10 - ktw + slide
        rect(kx, ry + 2, ktw, rowH - 4, WHITE, 152, 4, AL.field * rA)
        txtC(kt, kx + ktw / 2, ry + rowH / 2, WHITE, 11, FontMono, 153, AL.text * rA)
        yc = yc + rowH * r.ra
    end

    if click and not ProjectState.hkDrag and over(x, y, w, 28) then
        ProjectState.hkDrag = { ox = ProjectState.mouseX - x, oy = ProjectState.mouseY - y }; click = false
    end
    return click
end

local function fuzzyScore(q, lab)
    local ql, ll = #q, #lab
    if ql == 0 then return 0 end
    local qi, li, first, prev, gaps = 1, 1, nil, 0, 0
    while qi <= ql and li <= ll do
        if string.sub(q, qi, qi) == string.sub(lab, li, li) then
            if not first then first = li elseif li - prev > 1 then gaps = gaps + 1 end
            prev = li; qi = qi + 1
        end
        li = li + 1
    end
    if qi <= ql then return nil end
    local wordStart = (first == 1 or string.sub(lab, first - 1, first - 1) == " ") and -1 or 0
    return (first - 1) + gaps * 4 + wordStart
end
local function spotlightResults(q)
    q = string.lower(q or "")
    local out = {}
    for ti, tab in ipairs(ProjectState.tabs) do
        for _, sec in ipairs(tab.sections) do
            for _, item in ipairs(sec.items) do
                if item.label and item.type ~= "divider" and item.type ~= "label" then
                    local score = (q == "") and 0 or fuzzyScore(q, string.lower(item.label))
                    if score then
                        out[#out + 1] = { tab = tab, ti = ti, item = item, label = item.label,
                            sub = tab.name .. "  >  " .. sec.name, type = item.type, score = score }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.score ~= b.score then return a.score < b.score end return a.label < b.label end)
    return out
end
local function spotlightJump(r)
    if not r then return end
    if ProjectState.activeTab ~= r.tab then ProjectState.activeTab = r.tab; ProjectState.activeIndex = r.ti; ProjectState.contentFade = 0 end
    ProjectState.minimized = false
    setOpen(true)
    r.item._flash = (clock() or 0) + 1.3
    ProjectState._spotScrollTo = r.item
    ProjectState.spotlightOpen = false
end
local function drawSpotlight(click)
    local sp = ProjectState.spotlight
    if not sp then sp = { query = "", sel = 1 }; ProjectState.spotlight = sp end
    ProjectState.spotlightFade = approach(ProjectState.spotlightFade or 0, ProjectState.spotlightOpen and 1 or 0, 16)
    local a = ProjectState.spotlightFade
    if a < 0.02 then return click end
    if ProjectState.spotlightOpen then
        if Input.esc.click then ProjectState.spotlightOpen = false; Input.esc.click = false end
        if editText(sp, "query", false) then sp.sel = 1 end
    end
    if sp.query ~= sp._resQ then sp._resQ = sp.query; sp._results = spotlightResults(sp.query) end
    local results = sp._results
    sp.sel = clamp(sp.sel or 1, 1, max(1, #results))
    if ProjectState.spotlightOpen then
        if Input.down.click then sp.sel = min(#results, sp.sel + 1); Input.down.click = false end
        if Input.up.click then sp.sel = max(1, sp.sel - 1); Input.up.click = false end
        if Input.enter.click then spotlightJump(results[sp.sel]); Input.enter.click = false; return click end
    end
    local vw, vh = viewportSize()
    local W, rowH, maxRows = 470, 34, 7
    local shown = min(#results, maxRows)
    local H = 50 + (shown > 0 and (shown * rowH + 8) or 30)
    local X, Y = floor((vw - W) / 2), floor(vh * 0.16)
    rect(0, 0, vw, vh, c3(0, 0, 0), 398, 0, 0.4 * a)
    rect(X, Y, W, H, Theme.bg, 400, 12, 0.97 * a)
    strokeRect(X, Y, W, H, WHITE, 401, 12, AL.cardStrk * a)
    circ(X + 24, Y + 21, 6, WHITE, 402, false, 1.5, 16, AL.label * a)
    lineD(X + 28, Y + 25, X + 33, Y + 30, WHITE, 402, 1.5, AL.label * a)
    gradRectH(X + 14, Y + 46, W - 28, 2, Theme.accentA, Theme.accentB, 402, 0.7 * a)
    local qx = X + 44
    if sp.query == "" and not ProjectState.spotlightOpen then
        txt("Search widgets...", qx, textTop(Y, 46, 15), WHITE, 15, FontSystem, 402, false, false, W - 60, 0.3 * a)
    else
        drawEditable(sp, sp.query, qx, textTop(Y, 46, 15), 15, WHITE, AL.text * a, 402, W - 60, ProjectState.spotlightOpen, sp.caret, sp.selA)
    end
    if ProjectState.spotlightOpen then
        if click and over(X + 36, Y, W - 50, 46) then
            sp.caret = editCaretAtX(sp, sp.query, ProjectState.mouseX); sp.selA = sp.caret
            ProjectState.spTextDrag = true; click = false
        end
        if Input.m1.held and ProjectState.spTextDrag then sp.caret = editCaretAtX(sp, sp.query, ProjectState.mouseX) end
    end
    if #results == 0 then
        txt("no matches", X + 18, Y + 62, WHITE, 13, FontSystem, 402, false, false, W - 36, AL.dim * a)
    end
    local accentMid = ProjectState._accentMid
    local maxOff = max(0, #results - maxRows)
    sp._off = clamp(sp._off or 0, 0, maxOff)
    if sp.sel - 1 < sp._off then sp._off = sp.sel - 1 end
    if sp.sel - 1 > sp._off + maxRows - 1 then sp._off = sp.sel - maxRows end
    sp._off = clamp(sp._off, 0, maxOff)
    sp._sy = approach(sp._sy or sp._off, sp._off, 16)
    local sy = sp._sy
    local areaTop, areaH = Y + 50, maxRows * rowH
    local scrollable = #results > maxRows
    local rowW = scrollable and (W - 24) or (W - 16)
    local mouseMoved = ProjectState.mouseX ~= sp._mx or ProjectState.mouseY ~= sp._my
    sp._mx, sp._my = ProjectState.mouseX, ProjectState.mouseY
    for off = 0, maxRows do
        local ai = floor(sy) + off
        local r = (ai >= 0) and results[ai + 1] or nil
        if r then
            local ry = areaTop + (ai - sy) * rowH
            if ry + rowH > areaTop and ry < areaTop + areaH then
                local edgeA = clamp((ry + rowH - areaTop) / rowH, 0, 1) * clamp((areaTop + areaH - ry) / rowH, 0, 1)
                local ra = a * edgeA
                local inside = ry >= areaTop - 2 and ry + rowH <= areaTop + areaH + 2
                local hov = inside and over(X + 8, ry, rowW, rowH)
                if hov and mouseMoved and not sp._sbDrag then sp.sel = ai + 1 end
                local selOn = (ai + 1 == sp.sel)
                rect(X + 8, ry + 1, rowW, rowH - 2, accentMid, 401, 8, (selOn and 0.1 or 0) * ra)
                rect(X + 8, ry + 1, 3, rowH - 2, accentMid, 402, 1.5, (selOn and 0.9 or 0) * ra)
                txt(r.label, X + 18, ry + 6, WHITE, 14, FontBold, 402, false, false, W - 150, AL.text * ra)
                txt(r.sub, X + 18, ry + 19, WHITE, 11, FontSystem, 402, false, false, W - 150, AL.dim * ra)
                txt(r.type, X + rowW - 4 - textWidth(r.type, 11, FontSystem), textTop(ry, rowH, 11), WHITE, 11, FontSystem, 402, false, false, nil, AL.dim * ra)
                if inside and click and hov then spotlightJump(r); click = false end
            end
        end
    end
    if sp._sbDrag and not Input.m1.held then sp._sbDrag = nil end
    if maxOff > 0 then
        local sbX = X + W - 7
        local thumbH = max(22, areaH * maxRows / #results)
        local thumbY = areaTop + (areaH - thumbH) * (sp._off / maxOff)
        rect(sbX, areaTop, 3, areaH, WHITE, 403, 2, 0.05 * a)
        local sbHot = over(sbX - 6, areaTop, 12, areaH) or sp._sbDrag
        rect(sbX, thumbY, 3, thumbH, WHITE, 404, 2, (sbHot and 0.5 or 0.22) * a)
        if click and over(sbX - 6, areaTop, 12, areaH) then sp._sbDrag = true; click = false end
        if sp._sbDrag and Input.m1.held then
            local frac = clamp((ProjectState.mouseY - areaTop - thumbH / 2) / max(1, areaH - thumbH), 0, 1)
            sp._off = clamp(floor(frac * maxOff + 0.5), 0, maxOff)
            sp.sel = clamp(sp.sel, sp._off + 1, sp._off + maxRows)
        end
    end
    if click and not over(X, Y, W, H) then ProjectState.spotlightOpen = false; click = false end
    return click
end

local function drawBoxes(click, held)
    local boxes = ProjectState.boxes
    if not boxes or #boxes == 0 then return click end
    local interactive = ProjectState.open
    for _, box in ipairs(boxes) do
        if box.visible ~= false and box.alive ~= false then

            local accentMid = ProjectState._accentMid
            local lines = {}
            local maxW = textWidth(box.title or "Box", 12, FontBold) + 30
            for _, ln in ipairs(box.lines) do
                local kind = ln.kind or "text"
                if kind == "stat" then
                    local v = ln.value; if type(v) == "function" then local ok, r = pcall(v); v = ok and r or "" end
                    v = tostring(v == nil and "" or v)
                    if v ~= "" then
                        local lbl, val = v:match("^(.-)%s+|%s+(.+)$")
                        if not lbl then lbl, val = "", v end
                        lines[#lines + 1] = { kind = "stat", label = lbl, text = val, color = ln.color }
                        maxW = max(maxW, textWidth(lbl, 12, FontSystem) + textWidth(val, 12, FontMono) + 70)
                    end
                elseif kind == "bar" then
                    local v = ln.value; if type(v) == "function" then local ok, r = pcall(v); v = ok and r or nil end
                    if v ~= nil then
                        lines[#lines + 1] = { kind = "bar", pct = clamp(tonumber(v) or 0, 0, 100), color = ln.color }
                        maxW = max(maxW, 170)
                    end
                else
                    local t = ln.value; if type(t) == "function" then local ok, r = pcall(t); t = ok and r or "" end
                    t = tostring(t == nil and "" or t)
                    lines[#lines + 1] = { kind = "text", text = t, color = ln.color }
                    maxW = max(maxW, textWidth(t, 12, FontSystem) + 24)
                end
            end
            local titleH, lineH = 26, 18
            local w = box.width or max(140, maxW)
            local h = titleH + #lines * lineH + (#lines > 0 and 8 or 4)
            box.x = box.x or 20; box.y = box.y or 140
            if box._drag and not held then box._drag = nil end
            if interactive and held and box._drag then
                box._drag.tx = ProjectState.mouseX - box._drag.ox; box._drag.ty = ProjectState.mouseY - box._drag.oy
            end
            if box._drag and box._drag.tx then
                box.x = approach(box.x, box._drag.tx, 28); box.y = approach(box.y, box._drag.ty, 28)
            end
            local x, y = box.x, box.y
            rect(x, y, w, h, Theme.bg, 160, 8, 0.92)
            strokeRect(x, y, w, h, WHITE, 161, 8, AL.cardStrk)
            circ(x + 15, y + titleH / 2, 2.5, Theme.accentA, 162, true, 1, 10, 1)
            txt(box.title or "Box", x + 24, textTop(y, titleH, 12), WHITE, 12, FontBold, 162, false, false, w - 34, AL.text)
            gradRectH(x + 10, y + titleH - 1, w - 20, 1.5, Theme.accentA, Theme.accentB, 162, 0.7)
            for i, ln in ipairs(lines) do
                local ry = y + titleH + 5 + (i - 1) * lineH
                if ln.kind == "stat" then
                    local up = string.upper(ln.text)
                    local ready = up:find("READY") or up:find("FARMING") or up:find("GO", 1, true)
                    local idle = up:find("PAUSED") or up:find("WAIT") or up:find("IDLE") or up:find("OFF", 1, true) or up:find("SOON") or up == "--" or up:match("^%d+:%d")
                    local dotCol = ready and accentMid or (idle and c3(120, 122, 130) or c3(195, 197, 205))
                    local dotA = ready and (0.5 + 0.42 * sin((clock() or 0) * 5)) or (idle and 0.7 or 0.85)
                    circ(x + 16, ry + 7, 3, dotCol, 163, true, 1, 12, dotA)
                    txt(ln.label, x + 28, ry, WHITE, 12, FontSystem, 162, false, false, w - 110, AL.label)
                    txt(ln.text, x + w - 12 - textWidth(ln.text, 12, FontMono), ry, ln.color or WHITE, 12, FontMono, 162, false, false, nil, ready and AL.text or AL.label)
                elseif ln.kind == "bar" then
                    rect(x + 14, ry + 5, w - 28, 6, WHITE, 162, 3, AL.field)
                    if ln.pct > 0 then rect(x + 14, ry + 5, max(6, (w - 28) * ln.pct / 100), 6, Theme.accentA, 163, 3, 0.95) end
                else
                    txt(ln.text, x + 14, ry, ln.color or WHITE, 12, FontSystem, 162, false, false, w - 24, AL.label)
                end
            end
            if interactive and click and not box._drag and over(x, y, w, titleH) then
                box._drag = { ox = ProjectState.mouseX - x, oy = ProjectState.mouseY - y }; click = false
            end
        end
    end
    return click
end

local function drawMenuBars(cx, cy, sz, color, alpha, z)
    local lw, lh, sp = sz * 0.62, sz * 0.1375, sz * 0.275
    local lx = cx - lw / 2
    rect(lx, cy - sp - lh / 2, lw, lh, color, z, lh / 2, alpha)
    rect(lx, cy - lh / 2, lw, lh, color, z, lh / 2, alpha)
    rect(lx, cy + sp - lh / 2, lw, lh, color, z, lh / 2, alpha)
end

local function drawMinBubble(click, held)
    ProjectState.minA = approach(ProjectState.minA or 0, ProjectState.minimized and 1 or 0, 11)
    local a = ProjectState.minA * ProjectState.drawVisible
    if a < 0.02 then return click end
    ProjectState.minPos = ProjectState.minPos or { x = 24, y = 24 }
    local d = ProjectState.minBubbleDrag
    if d then
        if held then
            d.tx = ProjectState.mouseX - d.ox; d.ty = ProjectState.mouseY - d.oy
            if math.abs(ProjectState.mouseX - d.downX) + math.abs(ProjectState.mouseY - d.downY) > 4 then d.moved = true end
            ProjectState.minPos.x = approach(ProjectState.minPos.x, d.tx, 28)
            ProjectState.minPos.y = approach(ProjectState.minPos.y, d.ty, 28)
            local bvw, bvh = viewportSize()
            ProjectState.minPos.x = clamp(ProjectState.minPos.x, 0, max(0, bvw - 42))
            ProjectState.minPos.y = clamp(ProjectState.minPos.y, 0, max(0, bvh - 42))
        else
            if not d.moved then

                ProjectState.x = ProjectState.minPos.x
                ProjectState.y = ProjectState.minPos.y
                clampWindow()
                ProjectState.minimized = false
            end
            ProjectState.minBubbleDrag = nil
        end
    end

    local dv = ProjectState.drawVisible
    local t = ProjectState.minA
    local et = t * t * (3 - 2 * t)
    local bs = 42
    local wx, wy, ww, wh = ProjectState.x, ProjectState.y, ProjectState.w, ProjectState.h
    local bx, by = ProjectState.minPos.x, ProjectState.minPos.y
    local rx = wx + (bx - wx) * et
    local ry = wy + (by - wy) * et
    local rw = ww + (bs - ww) * et
    local rh = wh + (bs - wh) * et
    local rad = 10 + et
    local cx, cy = rx + rw / 2, ry + rh / 2
    local accentMid = ProjectState._accentMid
    local settled = ProjectState.minA > 0.9
    local hov = settled and over(rx, ry, rw, rh)
    ProjectState._minHov = approach(ProjectState._minHov or 0, hov and 1 or 0, 12)
    local hh = ProjectState._minHov
    for i = 1, 3 do local o = i * 3; rect(rx - o, ry - o + 2, rw + o * 2, rh + o * 2, c3(0, 0, 0), 199, rad + o, (0.10 - i * 0.025) * et * dv) end
    rect(rx - 3, ry - 3, rw + 6, rh + 6, accentMid, 200, rad + 2, 0.25 * hh * dv)
    rect(rx, ry, rw, rh, lerpColor(Theme.bg, accentMid, et), 201, rad, (0.96 - 0.04 * et) * dv)
    rect(rx, ry, rw, rh * 0.5, lerpColor(accentMid, WHITE, 0.14), 202, rad, 0.22 * et * dv)
    strokeRect(rx, ry, rw, rh, WHITE, 203, rad, (0.16 + 0.14 * et + 0.35 * hh) * dv)
    if et > 0.4 then
        local bubA = clamp((et - 0.4) / 0.6, 0, 1) * dv
        if ProjectState.iconImg then
            pcall(function()
                local ls = rw - 8
                ProjectState.iconImg.Position = v2(cx - ls / 2, cy - ls / 2); ProjectState.iconImg.Size = v2(ls, ls)
                pcall(function() ProjectState.iconImg.Rounding = rad end)
                ProjectState.iconImg.ZIndex = 2049999; ProjectState.iconImg.Transparency = bubA; ProjectState.iconImg.Visible = bubA > 0.01
            end)
        else
            drawMenuBars(cx, cy, rh, c3(36, 38, 50), bubA, 204)
        end
    end
    if settled and click and hov and not ProjectState.minBubbleDrag then
        ProjectState.minBubbleDrag = { ox = ProjectState.mouseX - rx, oy = ProjectState.mouseY - ry, downX = ProjectState.mouseX, downY = ProjectState.mouseY, moved = false }
        click = false
    end
    return click
end

local function thickBar(x1, y1, x2, y2, thick, color, z, alpha)
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.001 then return end
    local px, py = -dy / len * thick / 2, dx / len * thick / 2
    local p1, p2 = v2(x1 + px, y1 + py), v2(x1 - px, y1 - py)
    local p3, p4 = v2(x2 - px, y2 - py), v2(x2 + px, y2 + py)
    tri(p1, p2, p3, color, z, true, alpha)
    tri(p1, p3, p4, color, z, true, alpha)
end

local function getItemHeight(item)
    local t = item.type
    if t == "slider" or t == "rangeslider" then return 38
    elseif t == "dropdown" then return ProjectState.dropdownInline and 26 or 44
    elseif t == "textbox" then return 44
    elseif t == "checkbox" then return 30
    elseif t == "colorpicker" then return 26
    elseif t == "label" then return max(18, (item.cachedLineCount or 1) * 16 + 2)
    elseif t == "info" then return max(16, (item.cachedLineCount or 1) * 15 + 2)
    elseif t == "button" then return 26
    elseif t == "keybind" then return 30
    elseif t == "image" then return (item.imgHeight or 80) + 6
    elseif t == "divider" then return 18
    end
    return 28
end

local function tooltipReq(text, x, y)
    if not text or text == "" then return end
    ProjectState.tooltipText = text
    ProjectState.tooltipX = x; ProjectState.tooltipY = y
    if ProjectState.lastTooltipText ~= text then ProjectState.tooltipAt = clock() or 0 end
end

-- ===================== widget rendering =====================
local function drawWidget(item, rowX, rowY, rowW, trans, click, rightClick, popupBlocking)
    local t = item.type
    local interact = (trans > 0.5) and (not popupBlocking)

    if t == "label" then
        if item.labelFn then local ok, v = pcall(item.labelFn); if ok and v ~= nil then item.label = tostring(v) end end
        local lf = resolveFont(FontSystem)
        if item._wrapW ~= rowW or item._wrapTxt ~= item.label or item._wrapF ~= lf then
            item._wrapW = rowW; item._wrapTxt = item.label; item._wrapF = lf
            local all = {}
            for seg in (item.label .. "\n"):gmatch("(.-)\n") do
                if seg == "" then all[#all + 1] = "" else for _, ln in ipairs(wrapLines(seg, rowW, 13, lf)) do all[#all + 1] = ln end end
            end
            item._wrapLines = all
            item.cachedLineCount = max(1, #all)
        end
        local lines = item._wrapLines
        for i = 1, #lines do txt(lines[i], rowX, rowY + (i - 1) * 16, item.color or WHITE, 13, FontSystem, 31, false, false, nil, 0.7 * trans) end

    elseif t == "info" then
        local lf = resolveFont(FontSystem)
        if item._wrapW ~= rowW or item._wrapTxt ~= item.label or item._wrapF ~= lf then
            item._wrapW = rowW; item._wrapTxt = item.label; item._wrapF = lf
            local all = {}
            for seg in (item.label .. "\n"):gmatch("(.-)\n") do
                if seg == "" then all[#all + 1] = "" else for _, ln in ipairs(wrapLines(seg, rowW, 12, lf)) do all[#all + 1] = ln end end
            end
            item._wrapLines = all
            item.cachedLineCount = max(1, #all)
        end
        local lines = item._wrapLines
        for i = 1, #lines do txt(lines[i], rowX, rowY + (i - 1) * 15, item.color or WHITE, 12, FontSystem, 31, false, false, nil, AL.dim * trans) end

    elseif t == "divider" then
        local gc = shimmerColor(Theme.accentA, Theme.accentB, rowY * 0.004)
        local function gline(x1, x2)
            if x2 - x1 < 1 then return end
            lineD(x1, rowY + 8, x2, rowY + 8, gc, 29, 3, 0.14 * trans)
            lineD(x1, rowY + 8, x2, rowY + 8, gc, 30, 1, 0.55 * trans)
        end
        if item.label then
            local cx = rowX + rowW / 2
            local half = textWidth(item.label, 12, FontSystem) / 2 + 6
            gline(rowX, cx - half)
            txtC(item.label, cx, rowY + 8, WHITE, 12, FontSystem, 31, AL.dim * trans)
            gline(cx + half, rowX + rowW)
        else
            gline(rowX, rowX + rowW)
        end

    elseif t == "button" then
        local bh = 22
        local btns = item.buttons or { { label = item.label, callback = item.callback } }
        local nB = #btns
        local gap = 8
        local bw = (rowW - gap * (nB - 1)) / nB
        for bi, b in ipairs(btns) do
            local bx = rowX + (bi - 1) * (bw + gap)
            local hov = interact and over(bx, rowY, bw, bh)
            b._hf = approach(b._hf or 0, hov and 1 or 0, 16)
            local hf = b._hf
            rect(bx, rowY, bw, bh, WHITE, 30, 5, (AL.field + 0.06 * hf) * trans)
            strokeRect(bx, rowY, bw, bh, WHITE, 31, 5, (AL.hairline + 0.22 * hf) * trans)
            local la = (AL.label + (AL.hover - AL.label) * hf) * trans
            txtC(b.label, bx + bw / 2, rowY + bh / 2, item.color or WHITE, 13, FontSystem, 32, la)
            if item.tooltip and bi == 1 and hov then tooltipReq(item.tooltip, ProjectState.mouseX, ProjectState.mouseY) end
            if click and hov then invoke(b.callback); click = false end
        end

    elseif t == "checkbox" then

        local rightX = rowX + rowW
        local onColor, onKey = false, false

        local pw, ph = 38, 20
        local px = rowX + rowW - pw
        local py = rowY + 3
        local target = item.value and 1 or 0
        item.animState = approach(item.animState or target, target, 16)
        local onCol = item.risk and (Theme.unsafe or c3(255, 190, 70)) or ProjectState._accentMid
        local trackCol = lerpColor(Theme.trackOff, onCol, item.animState)
        rect(px, py, pw, ph, trackCol, 30, 6, trans)
        local knobX = px + 10 + (pw - 20) * item.animState
        rect(knobX - 7, py + 3, 14, 14, WHITE, 32, 4, trans)
        rightX = px - 8
        if item.colorpicker then
            rightX = rightX - 14
            local cpHov = interact and over(rightX, rowY + 6, 14, 14)
            rect(rightX, rowY + 6, 14, 14, c3(40, 40, 40), 30, 3, trans)
            rect(rightX, rowY + 6, 14, 14, item.colorpicker.value, 31, 3, trans * (item.colorpicker.alpha or 1))
            strokeRect(rightX, rowY + 6, 14, 14, WHITE, 32, 4, (cpHov and 0.4 or AL.hairline) * trans)
            onColor = cpHov; rightX = rightX - 8
            if click and cpHov then doColorPicker(ProjectState.mouseX + 12, ProjectState.mouseY - 80, item.colorpicker); click = false end
        end
        if item.keybind then
            local kb = item.keybind
            local lbl = kb.listening and "..." or keyLabel(kb.value)
            local kbW = max(28, textWidth(lbl, 13, FontMono) + 14)
            rightX = rightX - kbW
            local kbHov = interact and over(rightX, rowY + 3, kbW, 20)
            kb._hov = approach(kb._hov or 0, (kbHov or kb.listening) and 1 or 0, 14)
            if kb.listening then
                local accentMid = ProjectState._accentMid
                rect(rightX - 1, rowY + 2, kbW + 2, 22, Theme.accentB, 30, 6, 0.18 * trans)
                rect(rightX, rowY + 3, kbW, 20, accentMid, 31, 5, 0.6 * trans)
                strokeRect(rightX, rowY + 3, kbW, 20, Theme.accentB, 32, 5, 0.85 * trans)
            else
                rect(rightX, rowY + 3, kbW, 20, WHITE, 31, 5, (AL.field + 0.05 * kb._hov) * trans)
                strokeRect(rightX, rowY + 3, kbW, 20, Theme.accentA, 32, 5, 0.45 * kb._hov * trans)
                local nm = normalizeMode(kb.mode)
                local modeCol = (nm == "Always" and Theme.accentB) or (nm == "Toggle" and Theme.accentA) or WHITE
                strokeRect(rightX, rowY + 3, kbW, 20, modeCol, 32, 5, (nm == "Hold" and AL.hairline or 0.55) * trans)
            end
            txtC(lbl, rightX + kbW / 2 + 0.37, rowY + 13, WHITE, 13, FontMono, 33, (kb.listening and AL.text or (kbHov and AL.hover or AL.dim)) * trans)
            onKey = kbHov; rightX = rightX - 8
            if kbHov and not kb.listening then tooltipReq("click rebind (any key / mouse)  \194\183  right-click mode", ProjectState.mouseX, ProjectState.mouseY) end
            if click and kbHov then kb.listening = true; click = false; Input.m1.click = false end   -- swallow the chip click so it isn't captured as the MB1 bind
            if rightClick and kbHov and not kb.listening then
                ProjectState.keyMenu = { kb = kb, x = ProjectState.mouseX, y = ProjectState.mouseY, anim = 0 }
                ProjectState.dropdown = nil; ProjectState.colorpicker = nil
                rightClick = false
            end
            if item.keybind.listening then
                for _, name in ipairs(InputOrder) do
                    local inp = Input[name]
                    if inp.click then   -- any key OR mouse button (m1/m2/mb3-5) can be bound now
                        if name == "esc" then item.keybind.value = nil else item.keybind.value = name end
                        item.keybind.listening = false; inp.click = false
                        break
                    end
                end
            end
        end
        txt(item.label, rowX, textTop(rowY, 26, 13), WHITE, 13, FontSystem, 31, false, false, rightX - rowX - 4, AL.label * trans)
        if item.tooltip and interact and over(rowX, rowY, rowW, 26) then tooltipReq(item.tooltip, ProjectState.mouseX, ProjectState.mouseY) end
        if click and interact and over(rowX, rowY, rowW, 26) and not onColor and not onKey then
            setItemValue(item, not item.value, true); click = false
        end

    elseif t == "keybind" then
        local lbl = item.listening and "..." or keyLabel(item.value)
        local kbW = max(40, textWidth(lbl, 13, FontMono) + 16)
        local kx = rowX + rowW - kbW
        local kbHov = interact and over(kx, rowY + 3, kbW, 20)
        item._hov = approach(item._hov or 0, (kbHov or item.listening) and 1 or 0, 14)
        txt(item.label, rowX, textTop(rowY, 26, 13), WHITE, 13, FontSystem, 31, false, false, kx - rowX - 6, AL.label * trans)
        if item.listening then
            local accentMid = ProjectState._accentMid
            rect(kx - 1, rowY + 2, kbW + 2, 22, Theme.accentB, 30, 5, 0.18 * trans)
            rect(kx, rowY + 3, kbW, 20, accentMid, 31, 4, 0.6 * trans)
            strokeRect(kx, rowY + 3, kbW, 20, Theme.accentB, 32, 4, 0.85 * trans)
        else
            rect(kx, rowY + 3, kbW, 20, WHITE, 31, 4, (AL.field + 0.05 * item._hov) * trans)
            strokeRect(kx, rowY + 3, kbW, 20, Theme.accentA, 32, 4, 0.45 * item._hov * trans)
            strokeRect(kx, rowY + 3, kbW, 20, WHITE, 32, 4, AL.hairline * trans)
        end
        txtC(lbl, kx + kbW / 2 + 0.37, rowY + 13, WHITE, 13, FontMono, 33, (item.listening and AL.text or (kbHov and AL.hover or AL.dim)) * trans)
        if item.tooltip and interact and over(rowX, rowY, rowW, 26) then tooltipReq(item.tooltip, ProjectState.mouseX, ProjectState.mouseY) end
        if click and kbHov then item.listening = true; ProjectState.kbCapture = item; click = false; Input.m1.click = false end   -- swallow chip click
        if item.listening then
            for _, name in ipairs(InputOrder) do
                local inp = Input[name]
                if inp.click then   -- any key OR mouse button (m1/m2/mb3-5)
                    if name ~= "esc" then item.value = name; invoke(item.callback, item.value) end
                    item.listening = false; ProjectState.kbCapture = nil; inp.click = false
                    break
                end
            end
        end

    elseif t == "image" then
        local ih = item.imgHeight or 80
        local iw = item.imgWidth or rowW
        if iw > rowW then iw = rowW end
        local ix = rowX + (rowW - iw) / 2
        if item.imageData then
            if not item._img then pcall(function() item._img = Drawing.new("Image"); item._img.Data = item.imageData end) end
            if item._img then pcall(function()
                item._img.Position = v2(ix, rowY); item._img.Size = v2(iw, ih)
                item._img.ZIndex = 329999; item._img.Transparency = trans; item._img.Visible = trans > 0.01
                pcall(function() item._img.Rounding = item.rounding or 6 end)
            end) end
        else
            rect(ix, rowY, iw, ih, WHITE, 30, 6, AL.field * trans)
            strokeRect(ix, rowY, iw, ih, WHITE, 31, 6, AL.hairline * trans)
        end

    elseif t == "colorpicker" then
        txt(item.label, rowX, textTop(rowY, 24, 13), WHITE, 13, FontSystem, 31, false, false, rowW - 24, AL.label * trans)
        local swX, swY = rowX + rowW - 16, rowY + 5
        local hov = interact and over(swX, swY, 16, 16)
        rect(swX, swY, 16, 16, c3(40, 40, 40), 30, 3, trans)
        rect(swX, swY, 16, 16, item.value, 31, 3, trans * (item.alpha or 1))
        strokeRect(swX, swY, 16, 16, WHITE, 32, 3, (hov and 0.4 or AL.hairline) * trans)
        if click and hov then doColorPicker(ProjectState.mouseX + 12, ProjectState.mouseY - 80, item); click = false end

    elseif t == "slider" then
        txt(item.label, rowX, textTop(rowY, 16, 13), WHITE, 13, FontSystem, 31, false, false, rowW - 60, AL.label * trans)
        local focused = ProjectState.focus == item
        if item._dispVal ~= item.value then
            item._dispVal = item.value
            local _v = item.value   -- show small fractions as 0.00001, not 1e-05
            local _vs = (_v == floor(_v)) and tostring(floor(_v))
                or (string.format("%.8f", _v):gsub("0+$", ""):gsub("%.$", ""))
            item._dispStr = _vs .. (item.suffix ~= "" and (" " .. item.suffix) or "")
        end
        local disp = focused and (item.directValue or "") or item._dispStr
        local vbW = max(40, (focused and (#disp * editCharW(12)) or textWidth(disp, 12, FontSystem)) + 16)
        local vbX = rowX + rowW - vbW
        rect(vbX, rowY, vbW, 18, WHITE, 30, 3, AL.field * trans)
        strokeRect(vbX, rowY, vbW, 18, WHITE, 31, 3, (focused and 0.4 or AL.hairline) * trans)
        if focused then
            drawEditable(item, item.directValue or "", vbX + 7, textTop(rowY, 18, 12), 12, WHITE, AL.text * trans, 32, vbW - 12, true, item.caret, item.selA)
        else
            txt(disp, vbX + vbW / 2, textTop(rowY, 18, 12), WHITE, 12, FontSystem, 32, true, false, vbW - 8, AL.dim * trans)
        end
        if click and interact and over(vbX, rowY, vbW, 18) then
            ProjectState.focus = item; item.directValue = tostring(item.value)
            item._ex = vbX + 7; item._ecw = editCharW(12); item._es = 0          -- prime field metrics so the click maps to a caret now
            item.caret = editCaretAtX(item, item.directValue, ProjectState.mouseX); item.selA = item.caret   -- caret at click point, no selection
            ProjectState.textDrag = item; item._dragDownX = ProjectState.mouseX; click = false
        end
        if Input.m1.held and ProjectState.textDrag == item then
            if abs(ProjectState.mouseX - (item._dragDownX or ProjectState.mouseX)) > 3 then   -- only once the mouse actually moves = real drag-select; a still click leaves no selection
                item.caret = editCaretAtX(item, item.directValue or "", ProjectState.mouseX)
            end
        end
        local syBar = rowY + 26
        local sw = rowW
        local frac = (item.max ~= item.min) and clamp((item.value - item.min) / (item.max - item.min), 0, 1) or 0
        item._fillFrac = approach(item._fillFrac or frac, frac, 20)
        local f = item._fillFrac
        rect(rowX, syBar, sw, 3, Theme.sliderTrack, 30, 2, trans)

        if f > 0.001 then gradRectH(rowX, syBar, sw * f, 3, Theme.accentA, Theme.accentB, 31, trans) end
        local knobX = rowX + sw * f
        local hovKnob = interact and over(knobX - 9, syBar - 8, 18, 18)
        item.animatedRadius = approach(item.animatedRadius or 5, (hovKnob or ProjectState.sliderDrag == item) and 8 or 5, 16)
        circ(knobX, syBar + 1, item.animatedRadius, WHITE, 32, true, 1, 24, trans)
        if click and interact and over(rowX - 4, syBar - 8, sw + 8, 16) and not over(vbX, rowY, vbW, 18) then
            ProjectState.sliderDrag = item; click = false
        end
        if rightClick and interact and over(rowX - 4, syBar - 8, sw + 8, 16) and item.default ~= nil then
            setItemValue(item, item.default, true); rightClick = false
        end
        if Input.m1.held and ProjectState.sliderDrag == item then
            local sn = snapValue(item.min + (item.max - item.min) * clamp((ProjectState.mouseX - rowX) / sw, 0, 1), item)
            if sn ~= item.value then item.value = sn; invoke(item.callback, sn) end
        end

    elseif t == "rangeslider" then
        txt(item.label, rowX, textTop(rowY, 16, 13), WHITE, 13, FontSystem, 31, false, false, rowW - 90, AL.label * trans)
        if item._rsLo ~= item.valueLo or item._rsHi ~= item.valueHi or item._rsSuf ~= item.suffix then   -- only rebuild the text when the values change
            item._rsLo, item._rsHi, item._rsSuf = item.valueLo, item.valueHi, item.suffix
            item._rsDisp = tostring(item.valueLo) .. " - " .. tostring(item.valueHi) .. (item.suffix ~= "" and (" " .. item.suffix) or "")
        end
        local disp = item._rsDisp
        local vbW = max(54, textWidth(disp, 12, FontSystem) + 16)
        local vbX = rowX + rowW - vbW
        rect(vbX, rowY, vbW, 18, WHITE, 30, 3, AL.field * trans)
        strokeRect(vbX, rowY, vbW, 18, WHITE, 31, 3, AL.hairline * trans)
        txt(disp, vbX + vbW / 2, textTop(rowY, 18, 12), WHITE, 12, FontSystem, 32, true, false, vbW - 8, AL.dim * trans)
        local syBar = rowY + 26
        local sw = rowW
        local span = (item.max ~= item.min) and (item.max - item.min) or 1
        item._fLo = approach(item._fLo or 0, clamp((item.valueLo - item.min) / span, 0, 1), 20)
        item._fHi = approach(item._fHi or 1, clamp((item.valueHi - item.min) / span, 0, 1), 20)
        local xLo, xHi = rowX + sw * item._fLo, rowX + sw * item._fHi
        rect(rowX, syBar, sw, 3, Theme.sliderTrack, 30, 2, trans)
        gradRectH(xLo, syBar, max(0.5, xHi - xLo), 3, Theme.accentA, Theme.accentB, 31, trans)
        local dragging = ProjectState.sliderDrag == item
        local hovLo = interact and over(xLo - 9, syBar - 8, 18, 18)
        local hovHi = interact and over(xHi - 9, syBar - 8, 18, 18)
        item._rLo = approach(item._rLo or 5, (hovLo or (dragging and item._drag == "lo")) and 8 or 5, 16)
        item._rHi = approach(item._rHi or 5, (hovHi or (dragging and item._drag == "hi")) and 8 or 5, 16)
        circ(xLo, syBar + 1, item._rLo, WHITE, 32, true, 1, 24, trans)
        circ(xHi, syBar + 1, item._rHi, WHITE, 32, true, 1, 24, trans)
        if click and interact and over(rowX - 4, syBar - 8, sw + 8, 16) and not over(vbX, rowY, vbW, 18) then
            item._drag = (ProjectState.mouseX < (xLo + xHi) / 2) and "lo" or "hi"
            ProjectState.sliderDrag = item; click = false
        end
        if rightClick and interact and over(rowX - 4, syBar - 8, sw + 8, 16) then
            item.valueLo = item.defLo or item.min; item.valueHi = item.defHi or item.max
            invoke(item.callback, item.valueLo, item.valueHi); rightClick = false
        end
        if Input.m1.held and ProjectState.sliderDrag == item then
            local sn = snapValue(item.min + span * clamp((ProjectState.mouseX - rowX) / sw, 0, 1), item)
            if item._drag == "lo" then
                if sn > item.valueHi then sn = item.valueHi end
                if sn ~= item.valueLo then item.valueLo = sn; invoke(item.callback, item.valueLo, item.valueHi) end
            else
                if sn < item.valueLo then sn = item.valueLo end
                if sn ~= item.valueHi then item.valueHi = sn; invoke(item.callback, item.valueLo, item.valueHi) end
            end
        end

    elseif t == "dropdown" then
        local inline = ProjectState.dropdownInline == true
        local boxW = inline and max(110, floor(rowW * 0.5)) or rowW
        local boxX = inline and (rowX + rowW - boxW) or rowX
        local boxY = inline and rowY or (rowY + 20)
        if inline then
            txt(item.label, rowX, textTop(rowY, 24, 13), WHITE, 13, FontSystem, 31, false, false, boxX - rowX - 8, AL.label * trans)
        else
            txt(item.label, rowX, textTop(rowY, 16, 13), WHITE, 13, FontSystem, 31, false, false, rowW, AL.label * trans)
        end
        local disp = item.multi and (#item.value > 0 and concat(item.value, ", ") or "none") or (item.value[1] or "none")
        local hov = interact and over(boxX, boxY, boxW, 24)
        rect(boxX, boxY, boxW, 24, WHITE, 30, 4, AL.field * trans)
        strokeRect(boxX, boxY, boxW, 24, WHITE, 31, 4, (hov and 0.4 or AL.hairline) * trans)
        txt(disp, boxX + 10, textTop(boxY, 24, 13), WHITE, 13, FontSystem, 32, false, false, boxW - 30, AL.dim * trans)
        local open = ProjectState.dropdown and ProjectState.dropdown.item == item and not ProjectState.dropdown.closing

        local ccx, ccy = boxX + boxW - 13, boxY + 12
        local arm = open and (ccy + 1.9) or (ccy - 1.9)
        local tip = open and (ccy - 1.9) or (ccy + 1.9)
        thickBar(ccx - 4, arm, ccx, tip, 1.6, WHITE, 32, AL.dim * trans)
        thickBar(ccx + 4, arm, ccx, tip, 1.6, WHITE, 32, AL.dim * trans)
        if item.tooltip and hov then tooltipReq(item.tooltip, ProjectState.mouseX, ProjectState.mouseY) end
        if click and hov then
            if open then ProjectState.dropdown.closing = true else dDropdown(boxX, boxY + 26, boxW, item) end
            click = false
        end

    elseif t == "textbox" then
        txt(item.label, rowX, textTop(rowY, 16, 13), WHITE, 13, FontSystem, 31, false, false, rowW, AL.label * trans)
        local boxY = rowY + 20
        local focused = ProjectState.focus == item
        local hov = interact and over(rowX, boxY, rowW, 24)
        rect(rowX, boxY, rowW, 24, WHITE, 30, 4, AL.field * trans)
        strokeRect(rowX, boxY, rowW, 24, WHITE, 31, 4, (focused and 0.45 or (hov and 0.2 or AL.hairline)) * trans)
        local tx = rowX + 10
        local val = item.value or ""
        local empty = val == "" and not focused
        if empty then
            txt(item.label, tx, textTop(boxY, 24, 13), WHITE, 13, FontSystem, 32, false, false, rowW - 20, 0.3 * trans)
        else
            drawEditable(item, val, tx, textTop(boxY, 24, 13), 13, WHITE, AL.text * trans, 32, rowW - 18, focused, item.caret, item.selA)
        end
        if click and hov then
            ProjectState.focus = item
            item.caret = editCaretAtX(item, val, ProjectState.mouseX)
            item.selA = item.caret
            ProjectState.textDrag = item; item._dragDownX = ProjectState.mouseX
            click = false
        end
        if Input.m1.held and ProjectState.textDrag == item then
            if abs(ProjectState.mouseX - (item._dragDownX or ProjectState.mouseX)) > 3 then
                item.caret = editCaretAtX(item, val, ProjectState.mouseX)
            end
        end
    end
    return click, rightClick
end

local HEADER_H = 17
local function secHeaderH(s)
    if not (s.name and s.name ~= "") then return 0 end
    return HEADER_H + ((s.desc and s.desc ~= "") and 13 or 0)
end
local function drawSectionCard(section, colX, sy, colW, secH, clipTop, clipBottom, click, held, rightClick, popupBlocking)
    local cf = ProjectState.contentFade * ProjectState.drawVisible
    local fx = ProjectState.hoverEffects ~= false
    local headerH = secHeaderH(section)
    if headerH > 0 then
        local ha = cf * clamp((sy + headerH - clipTop) / headerH, 0, 1) * clamp((clipBottom - sy) / headerH, 0, 1)
        if ha > 0.01 then
            local cc = ProjectState._accentMid
            if section._nameU ~= section.name then section._nameU = section.name; section._nameUpper = string.upper(section.name) end   -- cache the upper'd name
            txt(section._nameUpper, colX + 4, sy + 2, cc, 11, FontBold, 31, false, false, colW - 22, 0.85 * ha)
            if section.desc then txt(section.desc, colX + 4, sy + 15, WHITE, 10, FontSystem, 31, false, false, colW - 22, AL.dim * 0.72 * ha) end
            local cvx, cvy = colX + colW - 12, sy + 7
            if section.collapsed then
                lineD(cvx - 2, cvy - 4, cvx + 2, cvy, cc, 31, 1.5, 0.8 * ha); lineD(cvx + 2, cvy, cvx - 2, cvy + 4, cc, 31, 1.5, 0.8 * ha)
            else
                lineD(cvx - 4, cvy - 1, cvx, cvy + 3, cc, 31, 1.5, 0.8 * ha); lineD(cvx, cvy + 3, cvx + 4, cvy - 1, cc, 31, 1.5, 0.8 * ha)
            end
            if click and not popupBlocking and over(colX, sy, colW, headerH) then section.collapsed = not section.collapsed; click = false end
        end
    end
    if (section._cA or 0) > 0.98 then return click, rightClick end   -- fully collapsed: skip body (still animate above)
    local cardTop = sy + headerH
    local drawY = max(cardTop, clipTop)
    local drawH = min(sy + secH, clipBottom) - drawY

    local cardHov = (not popupBlocking) and over(colX, drawY, colW, drawH)
    section._hovA = approach(section._hovA or 0, (cardHov and fx) and 1 or 0, 6)
    local cardAcc = ProjectState._accentMid
    rect(colX, drawY, colW, drawH, lerpColor(WHITE, cardAcc, 0.40), 28, 5, AL.card * 1.5 * cf)
    strokeRect(colX, drawY, colW, drawH, lerpColor(WHITE, cardAcc, 0.55), 29, 5, AL.cardStrk * cf)
    local hovA = section._hovA
    local accentMid = ProjectState._accentMid
    local ha = hovA * cf * (ProjectState.glowMul or 1)
    if not ProjectState.lite then
        strokeRect(colX - 2, drawY - 2, colW + 4, drawH + 4, accentMid, 32, 7, 0.05 * ha)
        strokeRect(colX - 1, drawY - 1, colW + 2, drawH + 2, accentMid, 32, 6, 0.11 * ha)
    end
    strokeRect(colX, drawY, colW, drawH, accentMid, 33, 8, 0.34 * ha)
    local rowW = colW - 38
    local rowX = colX + 20
    local rowY = cardTop + 14
    local n = #section.items
    local gap = ProjectState.rowLines and 5 or 8
    local cardBottom = min(clipBottom, sy + secH)   -- clip items to the (animating) card bottom so they wipe away smoothly
    for i, item in ipairs(section.items) do
        local ih = getItemHeight(item)
        local disabled = isItemDisabled(item)
        local clipF = 1
        if rowY < clipTop then clipF = clamp(1 - (clipTop - rowY) / (ih * 0.5), 0, 1) end
        if rowY + ih > cardBottom then clipF = min(clipF, clamp(1 - (rowY + ih - cardBottom) / (ih * 0.5), 0, 1)) end
        local trans = (disabled and 0.4 or 1) * cf * clipF
        click, rightClick = drawWidget(item, rowX, rowY, rowW, trans, click, rightClick, popupBlocking)
        local fa = (item._flash and item._flash > (clock() or 0)) and (0.35 + 0.5 * clamp(0.5 + 0.5 * sin((clock() or 0) * 9), 0, 1)) or 0
        strokeRect(rowX - 4, rowY - 4, rowW + 8, ih + 8, ProjectState._accentMid, 33, 7, fa * trans)
        if ProjectState.rowLines and i < n then
            local ly = rowY + ih + gap / 2
            if ly > clipTop and ly < cardBottom then lineD(colX + 14, ly, colX + colW - 14, ly, WHITE, 31, 1, 0.12 * cf * clipF) end
        end
        rowY = rowY + ih + (i < n and gap or 0)
    end
    return click, rightClick
end

local function sectionHeight(section)
    section._cA = approach(section._cA or (section.collapsed and 1 or 0), section.collapsed and 1 or 0, 10)
    local hdr = secHeaderH(section)
    local full = hdr + 14 + 10
    local n = #section.items
    for i, item in ipairs(section.items) do full = full + getItemHeight(item) + (i < n and (ProjectState.rowLines and 5 or 8) or 0) end
    return full + ((hdr + 6) - full) * section._cA   -- smoothly interpolate full <-> header-only
end

local function drawSections(tab, click, held, rightClick, px, contY, pw, contH)
    local popupBlocking = ProjectState.dropdown ~= nil or ProjectState.colorpicker ~= nil or ProjectState.keyMenu ~= nil or ProjectState.dialog ~= nil
    local colW = floor((pw - 10) / 2)
    local scrollTarget = ProjectState._spotScrollTo; ProjectState._spotScrollTo = nil

    local leftTotal, rightTotal = 0, 0
    for _, s in ipairs(tab.sections) do
        s._h = sectionHeight(s)
        if s.side == "Right" then rightTotal = rightTotal + s._h + 10 else leftTotal = leftTotal + s._h + 10 end
    end
    local contentH = max(leftTotal, rightTotal)
    tab.maxScroll = max(0, contentH - contH)

    if ProjectState.mouseScroll ~= 0 and not popupBlocking and over(ProjectState.x, ProjectState.y, ProjectState.w, ProjectState.h) then
        tab.targetScrollY = clamp(tab.targetScrollY - (ProjectState.mouseScroll > 0 and 1 or -1) * 42, 0, tab.maxScroll)
    end
    if tab.maxScroll > 0 and not popupBlocking and not ProjectState.focus and not ProjectState.spotlightOpen and over(px, contY, pw, contH) then
        if Input.up.click then tab.targetScrollY = max(0, tab.targetScrollY - 60) end
        if Input.down.click then tab.targetScrollY = min(tab.maxScroll, tab.targetScrollY + 60) end
        if Input.pageup.click then tab.targetScrollY = max(0, tab.targetScrollY - contH * 0.8) end
        if Input.pagedown.click then tab.targetScrollY = min(tab.maxScroll, tab.targetScrollY + contH * 0.8) end
    end
    tab.targetScrollY = clamp(tab.targetScrollY, 0, tab.maxScroll)
    tab.scrollY = approach(tab.scrollY, tab.targetScrollY, 15)

    local sy0 = contY - tab.scrollY
    local clipTop, clipBottom = contY, contY + contH
    local leftY, rightY = sy0, sy0
    for _, s in ipairs(tab.sections) do
        local tx, ty, tw
        if s.side == "Full" then
            ty = max(leftY, rightY); tx = px; tw = pw
            leftY = ty + s._h + 10; rightY = leftY
        elseif s.side == "Right" then
            tx = px + colW + 10; ty = rightY; tw = colW; rightY = rightY + s._h + 10
        else
            tx = px; ty = leftY; tw = colW; leftY = leftY + s._h + 10
        end

        if scrollTarget then
            local acc, nIt = secHeaderH(s) + 14, #s.items
            for ii, it in ipairs(s.items) do
                if it == scrollTarget then
                    tab.targetScrollY = clamp((ty - sy0) + acc - 40, 0, tab.maxScroll)
                    scrollTarget = nil; break
                end
                acc = acc + getItemHeight(it) + (ii < nIt and (ProjectState.rowLines and 5 or 8) or 0)
            end
        end

        click, rightClick = drawSectionCard(s, tx, ty, tw, s._h, clipTop, clipBottom, click, held, rightClick, popupBlocking)
    end

    if tab.maxScroll > 0 then
        local va = ProjectState.contentFade * ProjectState.drawVisible
        local trackX = px + pw + 4
        local barH = max(34, (contH / contentH) * contH)
        local barY = contY + (tab.scrollY / tab.maxScroll) * (contH - barH)
        local dragging = ProjectState.scrollDrag and ProjectState.scrollDrag.tab == tab
        local hov = over(trackX - 7, barY, 18, barH) or dragging
        tab._sbGlow = approach(tab._sbGlow or 0, hov and 1 or 0, 12)
        local accentMid = ProjectState._accentMid
        rect(trackX + 0.5, contY, 3, contH, WHITE, 34, 2, 0.07 * va)
        local bw = 3.5 + tab._sbGlow * 1.5
        local bx = trackX + 2 - bw / 2
        rect(bx - 2, barY - 3, bw + 4, barH + 6, accentMid, 35, (bw + 4) / 2, 0.18 * tab._sbGlow * va)
        rect(bx, barY, bw, barH, accentMid, 36, bw / 2, (0.65 + 0.35 * tab._sbGlow) * va)
        if click and not popupBlocking and over(trackX - 7, contY, 18, contH) then
            local grab = over(trackX - 7, barY, 18, barH) and (ProjectState.mouseY - barY) or (barH / 2)
            ProjectState.scrollDrag = { tab = tab, grab = grab }
            click = false
        end
        if Input.m1.held and ProjectState.scrollDrag and ProjectState.scrollDrag.tab == tab then
            local denom = max(1, contH - barH)
            tab.targetScrollY = clamp((ProjectState.mouseY - contY - ProjectState.scrollDrag.grab) / denom, 0, 1) * tab.maxScroll
        end
    elseif ProjectState.scrollDrag and ProjectState.scrollDrag.tab == tab then
        ProjectState.scrollDrag = nil
    end

    if tab.maxScroll > 0 and click and not popupBlocking and over(px, contY, pw, contH) and not ProjectState.scrollDrag then
        ProjectState.contentDrag = { tab = tab, my = ProjectState.mouseY, start = tab.targetScrollY }
        click = false
    end
    if Input.m1.held and ProjectState.contentDrag and ProjectState.contentDrag.tab == tab then
        tab.targetScrollY = clamp(ProjectState.contentDrag.start - (ProjectState.mouseY - ProjectState.contentDrag.my), 0, tab.maxScroll)
    end
    return click, rightClick
end

-- ===================== background effects (decorative particles behind the menu) =====================
local FX_LIST = { "Off", "Snow", "Matrix", "Rain" }
local FX_COUNT = { Snow = 48, Rain = 80 }
local MATRIX_GLYPHS = "01ABCDEFGHJKLMNPRSTUVXYZ#$%&@"
local function fxGlyph() local i = 1 + floor(math.random() * #MATRIX_GLYPHS); return string.sub(MATRIX_GLYPHS, i, i) end
local function fxSpawn(name, rw)
    local arr = {}
    local lite = ProjectState.lite and 0.55 or 1
    if name == "Matrix" then
        local cols = max(6, floor(rw / 18 * lite))
        for i = 1, cols do
            local trail = 6 + floor(math.random() * 6)
            local g = {}; for k = 1, trail do g[k] = fxGlyph() end
            arr[i] = { col = (i - 0.5) / cols, y = math.random() * 1.4 - 0.4, v = 0.25 + math.random() * 0.55, trail = trail, g = g }
        end
        return arr
    end
    local n = max(6, floor((FX_COUNT[name] or 80) * lite))
    for i = 1, n do
        arr[i] = { x = math.random(), y = math.random(), ph = math.random() * 6.2832, sp = 0.3 + math.random() * 0.9,
                   sz = 1 + math.random() * 2.2, a = 0.35 + math.random() * 0.6,
                   depth = math.random(),                       -- even spread of flake sizes (near big .. far small)
                   swayAmp = 0.005 + math.random() * 0.018, fl = 1.6 + math.random() * 1.8 }
    end
    return arr
end
local function drawBgEffect(x, y, w, h, titleH, v)
    local name = ProjectState.bgEffect
    if not name or name == "Off" then ProjectState._fx = nil; ProjectState._fxName = nil; return end
    if v <= 0.02 then return end
    local rx, ry = x + 2, y + titleH + 2
    local rw, rh = w - 4, h - titleH - 4
    if rw <= 12 or rh <= 12 then return end
    if ProjectState._fxName ~= name or not ProjectState._fx then ProjectState._fx = fxSpawn(name, rw); ProjectState._fxName = name end
    local p = ProjectState._fx
    local t = clock() or 0
    local dt = ProjectState.dt or 1/60; if dt > 0.1 then dt = 0.1 end
    local A = v
    local fxc = ProjectState.bgEffectColor
    pcall(function()
        if name == "Snow" then
            local wind = sin(t * 0.13) * 0.5 + sin(t * 0.31 + 1.3) * 0.22 + sin(t * 0.07) * 0.3   -- layered, slowly shifting gusts
            for i = 1, #p do local q = p[i]
                local d = q.depth                                      -- 0 far .. 1 near
                q.y = q.y + (0.035 + d * 0.11) * dt                    -- near flakes fall faster (parallax)
                if q.y > 1.04 then q.y = -0.04; q.x = math.random() end
                local sway = sin(t * q.sp + q.ph) * q.swayAmp + sin(t * q.sp * q.fl + q.ph) * q.swayAmp * 0.45  -- drift + flutter
                local ax = rx + (q.x + sway + wind * (0.012 + d * 0.03)) * rw
                local ay = ry + q.y * rh
                local r = 2 + d * 4.5                                 -- small arms 2 .. 6.5px
                local col = fxc or lerpColor(c3(215, 228, 255), c3(255, 255, 255), d)
                local al = (0.3 + d * 0.5) * (0.85 + 0.15 * sin(t * 2 + q.ph)) * A
                local rot = t * q.sp * 0.3 + q.ph                     -- slow spin
                if d > 0.55 then circ(ax, ay, r * 1.4, col, 12, true, 1, 12, al * 0.08) end   -- faint halo on the nearest
                for s = 0, 2 do                                       -- clean 6-point flake: 3 lines straight through the centre (fully symmetric)
                    local an = rot + s * 1.0472
                    local ux, uy = cos(an) * r, sin(an) * r
                    lineD(ax - ux, ay - uy, ax + ux, ay + uy, col, 13, 1, al)
                end
                circ(ax, ay, max(1, r * 0.28), col, 13, true, 1, 8, al)   -- centre
            end
        elseif name == "Rain" then
            for i = 1, #p do local q = p[i]
                q.y = q.y + (0.85 + q.sz * 0.25) * dt
                if q.y > 1.04 then q.y = -0.05; q.x = math.random() end
                local ax = rx + q.x * rw; local ay = ry + q.y * rh
                lineD(ax, ay, ax + 2.5, ay + (6 + q.sz * 5), fxc or c3(170, 200, 255), 12, 1, q.a * A * 0.5)
            end
        elseif name == "Matrix" then
            local gh = 14
            for i = 1, #p do local q = p[i]
                q.y = q.y + q.v * dt
                if q.y * rh - q.trail * gh > rh then q.y = -math.random() * 0.3; for k = 1, q.trail do q.g[k] = fxGlyph() end end
                local cx = rx + q.col * rw
                for k = 1, q.trail do
                    local ay = ry + q.y * rh - (k - 1) * gh
                    if ay >= ry and ay <= ry + rh then
                        local fade = 1 - (k - 1) / q.trail
                        local col = (k == 1) and (fxc and lerpColor(fxc, WHITE, 0.35) or c3(205, 255, 215)) or (fxc and lerpColor(c3(0, 0, 0), fxc, 0.3 + 0.5 * fade) or c3(40 + 60 * fade, 200, 80 + 40 * fade))
                        txt(q.g[k] or "0", cx, ay, col, 13, FontSystem, 12, false, false, nil, fade * A * 0.9)
                    end
                end
                if sin(t * 3 + q.col * 30) > 0.985 then q.g[1] = fxGlyph() end
            end
        end
    end)
end

-- ===================== window frame, sidebar & tabs =====================
local function drawWindow(click, held, rightClick)
    local v = ProjectState.drawVisible
    local titleH = 31
    local m = 6
    if ProjectState.activeTab ~= ProjectState._tabSeen then
        ProjectState.dropdown = nil; ProjectState.colorpicker = nil; ProjectState.keyMenu = nil; ProjectState.focus = nil
        ProjectState._tabSeen = ProjectState.activeTab
    end

    if held and ProjectState.drag then
        ProjectState.drag.tx = ProjectState.mouseX - ProjectState.drag.ox
        ProjectState.drag.ty = ProjectState.mouseY - ProjectState.drag.oy
    end
    if ProjectState.drag and ProjectState.drag.tx then
        local oldX, oldY = ProjectState.x, ProjectState.y
        ProjectState.x = approach(ProjectState.x, ProjectState.drag.tx, 28)
        ProjectState.y = approach(ProjectState.y, ProjectState.drag.ty, 28)
        clampWindow()
        local ddx, ddy = ProjectState.x - oldX, ProjectState.y - oldY
        if ddx ~= 0 or ddy ~= 0 then
            local pop = ProjectState.dropdown;    if pop and pop.x then pop.x = pop.x + ddx; pop.y = pop.y + ddy end
            local cpk = ProjectState.colorpicker; if cpk and cpk.x then cpk.x = cpk.x + ddx; cpk.y = cpk.y + ddy end
            local kmn = ProjectState.keyMenu;     if kmn and kmn.x then kmn.x = kmn.x + ddx; kmn.y = kmn.y + ddy end
        end
    end
    if held and ProjectState.resizeEdge then
        local rs = ProjectState.resizeStart
        local e = ProjectState.resizeEdge
        if e == "r" or e == "br" then ProjectState.wTarget = max(420, rs.w + (ProjectState.mouseX - rs.mx)) end
        if e == "b" or e == "br" then ProjectState.hTarget = max(300, rs.h + (ProjectState.mouseY - rs.my)) end
    end

    ProjectState.wTarget = ProjectState.wTarget or ProjectState.w
    ProjectState.hTarget = ProjectState.hTarget or ProjectState.h
    ProjectState.w = approach(ProjectState.w, ProjectState.wTarget, 16)
    ProjectState.h = approach(ProjectState.h, ProjectState.hTarget, 16)
    local x, y, w, h = ProjectState.x, ProjectState.y, ProjectState.w, ProjectState.h
    local sideMode = (ProjectState.tabLayout ~= "top")
    local tabStripH = 42
    local swC, swE = 58, max(150, floor(w * 0.29))
    local swPrev = swC + (swE - swC) * (ProjectState._sbX or 0)
    local noPopup = not ProjectState.dropdown and not ProjectState.colorpicker and not ProjectState.keyMenu and not ProjectState.spotlightOpen
    local sidebarHov = sideMode and noPopup and over(x, y + titleH, swPrev, h - titleH)
    ProjectState._sbX = approach(ProjectState._sbX or 0, sidebarHov and 1 or 0, 10)
    local expand = (ProjectState.lite or ProjectState.sidebarPinned or not sideMode) and 1 or ProjectState._sbX
    local sw = sideMode and (swC + (swE - swC) * expand) or 0

    if not ProjectState.lite then
        local sh = AL.winShadow
        for i = 1, #sh do
            local o = i * 4
            rect(x - o, y - o + 6, w + o * 2, h + o * 2, c3(0, 0, 0), 9, 16, sh[i] * v)
        end
    end

    local baseAlpha = ProjectState.menuOpacity or 0.92
    rect(x, y, w, h, Theme.bg, 10, 8, baseAlpha * v)
    if ProjectState.bgImg then
        pcall(function()
            local iw = (h - titleH) * 0.6
            ProjectState.bgImg.Position = v2(x + (w - iw) / 2, y + titleH); ProjectState.bgImg.Size = v2(iw, h - titleH)
            ProjectState.bgImg.ZIndex = 119999; ProjectState.bgImg.Transparency = (ProjectState.bgImgAlpha or 0.12) * v
            ProjectState.bgImg.Visible = v > 0.01
        end)
    end
    ProjectState._winRect = { x = x, y = y, w = w, h = h, th = titleH, v = v }   -- drawn last in the frame (see bg fx) so particles never shift UI pool slots
    strokeRect(x, y, w, h, WHITE, 12, 8, AL.hairline * v)

    lineD(x, y + titleH, x + w, y + titleH, WHITE, 12, 1, AL.hairline * v)
    if sideMode then lineD(x + sw, y + titleH, x + sw, y + h, WHITE, 61, 1, AL.hairline * v) end

    local tlY = y + titleH / 2
    local gemX = x + 20
    local accentMidT = ProjectState._accentMid

    local bsz = 16
    if ProjectState.iconImg then                              -- custom corner icon (both layouts)
        local lsz = bsz + 6
        pcall(function()
            ProjectState.iconImg.Position = v2(gemX - lsz / 2, tlY - lsz / 2); ProjectState.iconImg.Size = v2(lsz, lsz)
            pcall(function() ProjectState.iconImg.Rounding = 5 end)
            ProjectState.iconImg.ZIndex = 169999; ProjectState.iconImg.Transparency = v; ProjectState.iconImg.Visible = v > 0.01
        end)
    elseif ProjectState.logoImg and not sideMode then
        local lsz = bsz + 6
        pcall(function()
            ProjectState.logoImg.Position = v2(gemX - lsz / 2, tlY - lsz / 2); ProjectState.logoImg.Size = v2(lsz, lsz)
            pcall(function() ProjectState.logoImg.Rounding = 5 end)
            ProjectState.logoImg.ZIndex = 169999; ProjectState.logoImg.Transparency = v; ProjectState.logoImg.Visible = v > 0.01
        end)
    else
        rect(gemX - bsz / 2, tlY - bsz / 2, bsz, bsz, accentMidT, 14, 2.5, 0.95 * v)
        drawMenuBars(gemX, tlY, bsz, c3(36, 38, 50), v, 15)
    end

    local function ctrlBtn(cxp, kind)
        local gx, gy = floor(cxp + 0.5), floor(tlY + 0.5)
        local bs = 20
        local bx, by = gx - bs / 2, gy - bs / 2
        local hov = over(bx, by, bs, bs)
        local key = "_ctl_" .. kind
        ProjectState[key] = approach(ProjectState[key] or 0, hov and 1 or 0, 14)
        local hf = ProjectState[key]
        rect(bx, by, bs, bs, accentMidT, 13, 6, 0.14 * hf * v)
        strokeRect(bx, by, bs, bs, accentMidT, 14, 6, 0.55 * hf * v)
        local col = lerpColor(WHITE, accentMidT, hf)
        local aa = (0.5 + 0.45 * hf) * v
        if kind == "close" then

            local r = 4
            thickBar(gx - r, gy - r, gx + r, gy + r, 1.8, col, 16, aa)
            thickBar(gx + r, gy - r, gx - r, gy + r, 1.8, col, 16, aa)
        elseif kind == "search" then
            circ(gx - 1, gy - 1, 3.2, col, 16, false, 1.5, 18, aa)
            thickBar(gx + 1.3, gy + 1.3, gx + 4.2, gy + 4.2, 1.7, col, 16, aa)
        else
            thickBar(gx - 4, gy, gx + 4, gy, 1.8, col, 15, aa)
        end
        return hov
    end
    local function openSearch() ProjectState.spotlightOpen = true; ProjectState.spotlight = { query = "", sel = 1 } end
    local sst = ProjectState.searchStyle or "bar"
    if sst == "icon" then
        local searchHov = ctrlBtn(x + w - 71, "search")
        if searchHov then tooltipReq("Search  \194\183  Ctrl+Space", ProjectState.mouseX, ProjectState.mouseY) end
        if searchHov and click then openSearch(); click = false end
    elseif sst == "bar" then
        local barW = floor(min(190, max(100, w * 0.28)))
        local bx, by = x + w - 66 - barW, tlY - 9
        local sHov = over(bx, by, barW, 18)
        ProjectState._sbHov = approach(ProjectState._sbHov or 0, sHov and 1 or 0, 12)
        local sh = ProjectState._sbHov
        rect(bx, by, barW, 18, WHITE, 13, 9, (AL.field + 0.04 * sh) * v)
        strokeRect(bx, by, barW, 18, accentMidT, 14, 9, (0.12 + 0.4 * sh) * v)
        circ(bx + 10, tlY - 1, 3, accentMidT, 15, false, 1.3, 18, (0.7 + 0.3 * sh) * v)
        thickBar(bx + 11.8, tlY + 1.2, bx + 14.4, tlY + 3.8, 1.4, accentMidT, 15, (0.7 + 0.3 * sh) * v)
        txt("Search", bx + 20, textTop(by, 18, 12), WHITE, 12, FontSystem, 15, false, false, barW - 26, (AL.dim + 0.12 * sh) * v)
        if sHov then tooltipReq("Ctrl+Space", ProjectState.mouseX, ProjectState.mouseY) end
        if click and sHov then openSearch(); click = false end
    end
    if ctrlBtn(x + w - 21, "close") and click then setOpen(false); click = false end
    if ctrlBtn(x + w - 46, "min") and click then
        ProjectState.minimized = not ProjectState.minimized
        if ProjectState.minimized then
            ProjectState.minPos = { x = x + 6, y = y + 4 }
            ProjectState.dropdown = nil; ProjectState.colorpicker = nil; ProjectState.keyMenu = nil; ProjectState.focus = nil
        end
        click = false
    end

    if click and not ProjectState.drag and not ProjectState.resizeEdge and over(x, y, w, titleH) then
        ProjectState.drag = { ox = ProjectState.mouseX - x, oy = ProjectState.mouseY - y }; click = false
    end

    if sideMode then
    local hdrX = x + 16
    if ProjectState.logoImg then
        local lsz = 30
        local lcy = y + titleH + (ProjectState.subtitle ~= "" and 28 or 20)
        pcall(function()
            ProjectState.logoImg.Position = v2(hdrX, lcy - lsz / 2); ProjectState.logoImg.Size = v2(lsz, lsz)
            pcall(function() ProjectState.logoImg.Rounding = 7 end)
            ProjectState.logoImg.ZIndex = 629999; ProjectState.logoImg.Transparency = v * expand; ProjectState.logoImg.Visible = (v * expand) > 0.01
        end)
        hdrX = hdrX + lsz + 9
    end
    do
        local twMax = max(2, (x + sw - 14) - hdrX)
        local tTop, tA = y + titleH + 12, AL.text * v * expand
        txt(ProjectState.title, hdrX, tTop + 1, c3(0, 0, 0), 16, FontBold, 60, false, false, twMax, 0.28 * tA)   -- soft drop shadow (clean, no blur glow)
        txt(ProjectState.title, hdrX, tTop, ProjectState._accentMid, 16, FontBold, 61, false, false, twMax, tA)
    end
    local infoBottom = y + titleH + 36
    if ProjectState.subtitle ~= "" then
        txt(ProjectState.subtitle, hdrX, y + titleH + 34, WHITE, 11, FontSystem, 61, false, false, max(2, (x + sw - 14) - hdrX), AL.dim * v * expand)
        infoBottom = y + titleH + 52
    end
    lineD(x + 12, infoBottom, x + sw - 12, infoBottom, WHITE, 61, 1, AL.hairline * v * expand)

    local pillH = 34
    local ty = floor((y + titleH + 14) + ((infoBottom + 12) - (y + titleH + 14)) * expand)
    for i, tab in ipairs(ProjectState.tabs) do
        if not tab.hidden then
        local active = ProjectState.activeTab == tab
        local inPill = over(x + 12, ty, sw - 24, pillH)
        local hov = inPill and ProjectState.hoverEffects ~= false
        local af = approach(tab._af or 0, active and 1 or 0, 13); tab._af = af
        rect(x + 12, ty, sw - 24, pillH, ProjectState._accentMid, 61, 4, 0.13 * af * v)
        strokeRect(x + 12, ty, sw - 24, pillH, WHITE, 61, 4, AL.cardStrk * af * v)
        rect(x + 9, ty + pillH / 2 - 9 * af, 3.5, max(1, 18 * af), accentMidT, 62, 1.75, 0.95 * af * v)
        rect(x + 12, ty, sw - 24, pillH, WHITE, 61, 4, ((hov and not active) and 0.07 or 0) * v)
        local la = (active and AL.hover or (hov and AL.label or AL.dim)) * v
        local ia = (active and 0.96 or (hov and 0.82 or 0.58)) * v
        local labelX = x + 24
        if tab.icon then
            local iiy = ty + (pillH - 16) / 2
            if IconBytes[tab.icon] then
                if not tab._img then
                    pcall(function() tab._img = Drawing.new("Image"); tab._img.Data = IconBytes[tab.icon] end)
                end
                if tab._img then
                    pcall(function()
                        tab._img.Position = v2(x + 22, iiy); tab._img.Size = v2(16, 16)
                        tab._img.ZIndex = 629999; tab._img.Transparency = ia; tab._img.Visible = ia > 0.01
                    end)
                end
            else
                drawIcon(tab.icon, x + 22, iiy, 16, WHITE, 62, ia)
            end
            labelX = x + 48
        end
        txt(tab.name, labelX, textTop(ty, pillH, 14), active and accentMidT or WHITE, 14, FontBold, 62, false, false, max(2, (x + sw - 18) - labelX), la * expand)
        if click and inPill then
            if ProjectState.activeTab ~= tab then ProjectState.activeTab = tab; ProjectState.activeIndex = i; ProjectState.contentFade = 0 end
            click = false
        end
        ty = ty + pillH + 12
        end
    end

    do
        if not ProjectState._plResolved and LocalPlayer then
            local name, disp = "player", "player"
            pcall(function() if LocalPlayer then name = tostring(LocalPlayer.Name or "player") end end)
            pcall(function() if LocalPlayer and LocalPlayer.DisplayName and LocalPlayer.DisplayName ~= "" then disp = tostring(LocalPlayer.DisplayName) else disp = name end end)
            ProjectState._plDisp = disp
            ProjectState._plInitial = string.upper(string.sub(disp, 1, 1))
            ProjectState._plHandle = "@" .. name
            ProjectState._plResolved = true
        end
        local disp = ProjectState._plDisp or "player"
        local uy = y + h - 46
        lineD(x + 14, uy - 10, x + sw - 14, uy - 10, WHITE, 61, 1, AL.hairline * v * expand)
        local acx, acy = x + 29, uy + 16
        if ProjectState.avatarImg then
            pcall(function()
                ProjectState.avatarImg.Position = v2(acx - 14, acy - 14); ProjectState.avatarImg.Size = v2(28, 28)
                ProjectState.avatarImg.ZIndex = 629999; ProjectState.avatarImg.Transparency = v
                pcall(function() ProjectState.avatarImg.Rounding = 14 end)
                ProjectState.avatarImg.Visible = v > 0.01
            end)
            circ(acx, acy, 14, WHITE, 63, false, 1, 28, AL.hairline * v)
        else
            circ(acx, acy, 14, ProjectState._accentMid, 61, true, 1, 28, 0.18 * v)
            circ(acx, acy, 14, WHITE, 62, false, 1, 28, AL.hairline * v)
            local letter = ProjectState._plInitial or "P"
            local lw0 = textWidth(letter, 13, FontBold)
            txt(letter, acx - lw0 / 2, acy - 7, WHITE, 13, FontBold, 62, false, false, nil, AL.text * v)
        end
        txt(disp, x + 50, uy + 6, WHITE, 12, FontBold, 62, false, false, max(2, sw - 100), AL.text * v * expand)
        txt(ProjectState._plHandle or "@player", x + 50, uy + 22, WHITE, 11, FontSystem, 62, false, false, max(2, sw - 100), AL.dim * v * expand)

        if ProjectState.settingsTab then
            local gcx, gcy = x + sw - 26, acy
            local ghov = expand > 0.5 and over(gcx - 15, gcy - 15, 30, 30)
            local gActive = ProjectState.activeTab == ProjectState.settingsTab
            local ga = (gActive and AL.hover or (ghov and AL.label or AL.dim)) * v * expand
            local gf = approach(ProjectState._gearAf or 0, (gActive or ghov) and 1 or 0, 13); ProjectState._gearAf = gf
            rect(gcx - 15, gcy - 15, 30, 30, WHITE, 61, 8, AL.tabFill * (gActive and 1 or 0.6) * gf * v * expand)
            strokeRect(gcx - 15, gcy - 15, 30, 30, WHITE, 61, 8, AL.cardStrk * gf * v * expand)
            local gi = ProjectState.settingsIcon or "cog"
            local isz = 20
            if IconBytes[gi] then
                if not ProjectState._gearImg then pcall(function() ProjectState._gearImg = Drawing.new("Image"); ProjectState._gearImg.Data = IconBytes[gi] end) end
                if ProjectState._gearImg then pcall(function()
                    ProjectState._gearImg.Position = v2(gcx - isz / 2, gcy - isz / 2); ProjectState._gearImg.Size = v2(isz, isz)
                    ProjectState._gearImg.ZIndex = 629999; ProjectState._gearImg.Transparency = ga; ProjectState._gearImg.Visible = ga > 0.01
                end) end
            else
                drawIcon(gi, gcx - isz / 2, gcy - isz / 2, isz, WHITE, 62, ga)
            end
            if click and ghov then
                if gActive then
                    ProjectState.activeTab = ProjectState._prevTab or ProjectState.tabs[1]
                    ProjectState.activeIndex = ProjectState._prevIndex or 1
                else
                    ProjectState._prevTab = ProjectState.activeTab; ProjectState._prevIndex = ProjectState.activeIndex
                    ProjectState.activeTab = ProjectState.settingsTab; ProjectState.activeIndex = ProjectState.settingsIndex or #ProjectState.tabs
                end
                ProjectState.contentFade = 0; click = false
            end
        end
    end
    else

        local yStrip = y + titleH
        local sMid = yStrip + tabStripH / 2
        local accentMid = accentMidT
        local rightEdge = x + w - 14
        if ProjectState.settingsTab then
            local gcx, gcy = x + w - 26, sMid
            local ghov = over(gcx - 14, gcy - 14, 28, 28)
            local gActive = ProjectState.activeTab == ProjectState.settingsTab
            local ga = (gActive and AL.hover or (ghov and AL.label or AL.dim)) * v
            local gf = approach(ProjectState._gearAf or 0, (gActive or ghov) and 1 or 0, 13); ProjectState._gearAf = gf
            rect(gcx - 14, gcy - 14, 28, 28, WHITE, 13, 8, AL.tabFill * (gActive and 1 or 0.6) * gf * v)
            local gi = ProjectState.settingsIcon or "cog"
            if IconBytes[gi] then
                if not ProjectState._gearImg then pcall(function() ProjectState._gearImg = Drawing.new("Image"); ProjectState._gearImg.Data = IconBytes[gi] end) end
                if ProjectState._gearImg then pcall(function() ProjectState._gearImg.Position = v2(gcx - 9, gcy - 9); ProjectState._gearImg.Size = v2(18, 18); ProjectState._gearImg.ZIndex = 169999; ProjectState._gearImg.Transparency = ga; ProjectState._gearImg.Visible = ga > 0.01 end) end
            else drawIcon(gi, gcx - 9, gcy - 9, 18, WHITE, 15, ga) end
            if click and ghov then
                if gActive then ProjectState.activeTab = ProjectState._prevTab or ProjectState.tabs[1]; ProjectState.activeIndex = ProjectState._prevIndex or 1
                else ProjectState._prevTab = ProjectState.activeTab; ProjectState._prevIndex = ProjectState.activeIndex; ProjectState.activeTab = ProjectState.settingsTab; ProjectState.activeIndex = ProjectState.settingsIndex or #ProjectState.tabs end
                ProjectState.contentFade = 0; click = false
            end
            rightEdge = gcx - 22
        end
        local acx, acy = rightEdge - 13, sMid
        if ProjectState.avatarImg then
            pcall(function()
                ProjectState.avatarImg.Position = v2(acx - 11, acy - 11); ProjectState.avatarImg.Size = v2(22, 22)
                ProjectState.avatarImg.ZIndex = 169999; ProjectState.avatarImg.Transparency = v
                pcall(function() ProjectState.avatarImg.Rounding = 11 end)
                ProjectState.avatarImg.Visible = v > 0.01
            end)
            circ(acx, acy, 11, WHITE, 17, false, 1, 24, AL.hairline * v)
        else
            local letter = ProjectState._plInitial or string.upper(string.sub((LocalPlayer and LocalPlayer.Name) or "P", 1, 1))
            circ(acx, acy, 11, ProjectState._accentMid, 13, true, 1, 24, 0.18 * v)
            circ(acx, acy, 11, WHITE, 14, false, 1, 24, AL.hairline * v)
            local lw0 = textWidth(letter, 12, FontBold)
            txt(letter, acx - lw0 / 2, acy - 6, WHITE, 12, FontBold, 15, false, false, nil, AL.text * v)
        end
        local tx = x + 14
        for i, tab in ipairs(ProjectState.tabs) do
            if not tab.hidden then
                local active = ProjectState.activeTab == tab
                local iconW = tab.icon and 22 or 0
                local pw0 = iconW + textWidth(tab.name, 14, FontBold) + 24
                local ph = 26
                local pyy = sMid - ph / 2
                local inPill = over(tx, pyy, pw0, ph)
                local hov = inPill and ProjectState.hoverEffects ~= false
                local af = approach(tab._af or 0, active and 1 or 0, 13); tab._af = af
                rect(tx, pyy, pw0, ph, WHITE, 13, 7, AL.tabFill * af * v)
                strokeRect(tx, pyy, pw0, ph, WHITE, 14, 7, AL.cardStrk * af * v)
                rect(tx + pw0 / 2 - 8 * af, yStrip + tabStripH - 3, max(1, 16 * af), 2, accentMid, 15, 1, 0.95 * af * v)
                rect(tx, pyy, pw0, ph, WHITE, 13, 7, ((hov and not active) and 0.07 or 0) * v)
                local la = (active and AL.hover or (hov and AL.label or AL.dim)) * v
                local lblX = tx + 12
                if tab.icon then
                    local iiy = sMid - 8
                    if IconBytes[tab.icon] then
                        if not tab._img then pcall(function() tab._img = Drawing.new("Image"); tab._img.Data = IconBytes[tab.icon] end) end
                        if tab._img then pcall(function() tab._img.Position = v2(tx + 10, iiy); tab._img.Size = v2(16, 16); tab._img.ZIndex = 169999; tab._img.Transparency = la; tab._img.Visible = la > 0.01 end) end
                    else drawIcon(tab.icon, tx + 10, iiy, 16, WHITE, 15, la) end
                    lblX = tx + 30
                end
                txt(tab.name, lblX, textTop(pyy, ph, 14), active and accentMidT or WHITE, 14, FontBold, 15, false, false, pw0, la)
                if click and inPill then
                    if ProjectState.activeTab ~= tab then ProjectState.activeTab = tab; ProjectState.activeIndex = i; ProjectState.contentFade = 0 end
                    click = false
                end
                tx = tx + pw0 + 6
            end
        end
        lineD(x, yStrip + tabStripH, x + w, yStrip + tabStripH, WHITE, 12, 1, AL.hairline * v)
    end

    local cx, cw, contY, px, pw
    if sideMode then
        cx = x + sw; cw = w - sw
        local ctopH = 40
        if ProjectState.activeTab then
            txt(ProjectState.activeTab.name, cx + 16, textTop(y + titleH, ctopH, 14), WHITE, 14, FontBold, 13, false, false, cw - 32, AL.label * v)
        end
        local cgc = shimmerColor(Theme.accentA, Theme.accentB)
        lineD(cx, y + titleH + ctopH, x + w, y + titleH + ctopH, cgc, 11, 3, 0.12 * v)
        lineD(cx, y + titleH + ctopH, x + w, y + titleH + ctopH, cgc, 12, 1, 0.5 * v)
        contY = y + titleH + ctopH + 8
        px = cx + 12; pw = cw - 24 - 6
    else
        cx = x; cw = w
        contY = y + titleH + tabStripH + 8
        px = x + 14; pw = w - 28 - 6
    end

    lineD(x + w - 14, y + h - 5, x + w - 5, y + h - 14, WHITE, 13, 1, AL.dim * v)
    lineD(x + w - 11, y + h - 5, x + w - 5, y + h - 11, WHITE, 13, 1, AL.dim * v)
    lineD(x + w - 8, y + h - 5, x + w - 5, y + h - 8, WHITE, 13, 1, AL.dim * v)

    if click and not ProjectState.drag and not ProjectState.resizeEdge then
        local corner = over(x + w - 22, y + h - 22, 24, 24)   -- generous bottom-right grip for diagonal resize
        local right = over(x + w - m, y, m + 2, h)
        local bottom = over(x, y + h - m, w, m + 2)
        local edge = corner and "br" or ((right and bottom) and "br") or (right and "r") or (bottom and "b") or nil
        if edge then
            ProjectState.resizeEdge = edge
            ProjectState.resizeStart = { w = w, h = h, mx = ProjectState.mouseX, my = ProjectState.mouseY }
            click = false
        end
    end

    local contH = (y + h) - contY - 10
    ProjectState.contentFade = approach(ProjectState.contentFade, 1, 12)
    if ProjectState.contentFade > 0.997 then ProjectState.contentFade = 1 end
    if ProjectState.activeTab then
        click, rightClick = drawSections(ProjectState.activeTab, click, held, rightClick, px, contY, pw, contH)
    end
    return click, held, rightClick
end

local function drawNotifications()
    local notes = ProjectState.notifications
    while #notes > 10 do remove(notes, 1) end
    local vw, vh = viewportSize()
    local width = 292
    local stackY = vh - 16
    local i = 1
    while i <= #notes do
        local n = notes[i]
        n.elapsed = n.elapsed + (ProjectState.dt or 1/60)
        if n.elapsed >= n.duration then remove(notes, i)
        else
            local descLines = wrapLines(n.description or "", width - 32, 12, FontSystem)
            if #descLines == 0 then descLines = { "" } end
            if #descLines > 4 then local t4 = {}; for li = 1, 4 do t4[li] = descLines[li] end; descLines = t4 end
            local height = 24 + #descLines * 15 + 14
            stackY = stackY - height
            n.targetX = vw - width - 16
            n.targetY = stackY
            n.currentX = approach(n.currentX or vw, n.targetX, 12)
            n.currentY = approach(n.currentY or n.targetY, n.targetY, 12)
            local fade = 1
            if n.elapsed < 0.25 then fade = n.elapsed / 0.25
            elseif n.duration - n.elapsed < 0.35 then fade = (n.duration - n.elapsed) / 0.35 end
            local nx, ny = n.currentX, n.currentY
            local typ = n.ntype or (n.title == "error" and "error") or nil
            local tc = (typ == "success" and c3(95, 210, 135)) or (typ == "warning" and c3(255, 190, 70))
                       or (typ == "error" and Theme.bad) or ProjectState._accentMid
            rect(nx + 2, ny + 3, width, height, c3(0, 0, 0), 299, 12, 0.16 * fade)
            rect(nx, ny, width, height, Theme.bg, 300, 12, 0.97 * fade)
            strokeRect(nx, ny, width, height, WHITE, 301, 12, 0.1 * fade)
            circ(nx + 17, ny + 16, 3.5, tc, 302, true, 1, 16, fade)
            txt(n.title, nx + 29, ny + 9, typ and tc or WHITE, 13, FontBold, 302, false, false, width - 42, (typ and 1 or AL.text) * fade)
            for li = 1, #descLines do
                txt(descLines[li], nx + 29, ny + 26 + (li - 1) * 15, WHITE, 12, FontSystem, 302, false, false, width - 40, AL.label * fade)
            end
            local frac = clamp(1 - n.elapsed / n.duration, 0, 1)
            local trackX, trackW, trackY = nx + 29, width - 45, ny + height - 9
            rect(trackX, trackY, trackW, 2, WHITE, 302, 1, 0.12 * fade)
            local barW = trackW * frac
            local barA = 0.95 * fade * clamp(barW, 0, 1)
            if typ then rect(trackX, trackY, max(1, barW), 2, tc, 303, 1, barA)
            else gradRectH(trackX, trackY, max(1, barW), 2, Theme.accentA, Theme.accentB, 303, barA) end
            stackY = stackY - 8
            i = i + 1
        end
    end
end

local function drawTooltip()
    if not ProjectState.tooltipsEnabled then return end
    local text = ProjectState.tooltipText
    if not text or text == "" then return end
    if (clock() or 0) - (ProjectState.tooltipAt or 0) < 0.35 then return end
    if ProjectState._ttText ~= text then ProjectState._ttText = text; ProjectState._ttLines = wrapLines(text, 240, 12, FontUI) end
    local lines = ProjectState._ttLines
    local maxW = 0
    for _, l in ipairs(lines) do maxW = max(maxW, textWidth(l, 12, FontUI)) end
    local width = floor(maxW * 1.04) + 14
    local hgt = 7 + 15 * #lines
    local vw, vh = viewportSize()
    local x = clamp(ProjectState.tooltipX + 12, 8, vw - width - 8)
    local yy = clamp(ProjectState.tooltipY + 18, 8, vh - hgt - 4)
    rect(x, yy, width, hgt, Theme.bg, 320, 6, 0.96)
    strokeRect(x, yy, width, hgt, WHITE, 321, 6, AL.cardStrk)
    for i, l in ipairs(lines) do txt(l, x + 8, yy + 4 + (i - 1) * 15, WHITE, 12, FontUI, 322, false, false, nil, AL.text) end
end

-- ===================== config: save / load / auto-save =====================
local CFG_LEGACY = LIB_NAME .. "_configs"
local function sanitizeFolder(s)
    s = tostring(s or ""):gsub("[^%w%-_ ]", " "):gsub("%s+", " "):gsub("^ +", ""):gsub(" +$", "")
    return s
end
local function cfgDir() return ProjectState.cfgFolder or CFG_LEGACY end
local function ensureFolder() pcall(function() local d = cfgDir(); if not isfolder(d) then makefolder(d) end end) end
local function serializeConfig()
    local data = { flags = {}, keybinds = {}, uiFont = ProjectState.uiFontName, layout = ProjectState.tabLayout, search = ProjectState.searchStyle }
    for _, tab in ipairs(ProjectState.tabs) do
        for _, sec in ipairs(tab.sections) do
            for _, item in ipairs(sec.items) do
                if item.type == "rangeslider" and not item.noSave then
                    local key = tab.name .. "." .. sec.name .. "." .. item.label
                    data.flags[key] = { item.valueLo, item.valueHi }   -- range slider keeps two values, not item.value
                    if item.keybind then data.keybinds[key] = { item.keybind.value, item.keybind.mode } end
                elseif item.value ~= nil and item.type ~= "button" and not item.noSave then
                    local key = tab.name .. "." .. sec.name .. "." .. item.label
                    if item.type == "colorpicker" then
                        data.flags[key] = { item.value.R, item.value.G, item.value.B, item.alpha or 1 }
                    elseif item.type == "dropdown" then
                        data.flags[key] = copyArray(item.value)
                    else
                        data.flags[key] = item.value
                    end
                    if item.keybind then data.keybinds[key] = { item.keybind.value, item.keybind.mode } end
                end
            end
        end
    end

    local bA = ProjectState.baseAccentA or Theme.accentA
    local bB = ProjectState.baseAccentB or Theme.accentB
    data.settings = {
        accentA = { bA.R, bA.G, bA.B }, accentB = { bB.R, bB.G, bB.B },
        rainbow = ProjectState.rainbow == true, rainbowSpeed = ProjectState.rainbowSpeed,
        menuOpacity = ProjectState.menuOpacity, noAnim = ProjectState.noAnim == true,
        notifyDur = ProjectState.notifyDur, hoverEffects = ProjectState.hoverEffects ~= false,
        hotkeyEnabled = ProjectState.hotkeyEnabled ~= false, menuKey = menuKey,
        w = ProjectState.w, h = ProjectState.h,
        bg = { Theme.bg.R, Theme.bg.G, Theme.bg.B }, txt = { Theme.text.R, Theme.text.G, Theme.text.B }, glowMul = ProjectState.glowMul,
        cardStrk = AL.cardStrk, hairline = AL.hairline, cardFill = AL.card,
        lite = ProjectState.lite == true, roundScale = ProjectState.roundScale, smartFps = ProjectState.smartFps ~= false, sidebarPinned = ProjectState.sidebarPinned == true, dropdownInline = ProjectState.dropdownInline == true, bgImg = ProjectState.bgImgUrl, bgImgA = ProjectState.bgImgAlpha, bgFx = ProjectState.bgEffect, bgFxColor = ProjectState.bgEffectColor and { ProjectState.bgEffectColor.R, ProjectState.bgEffectColor.G, ProjectState.bgEffectColor.B } or nil, logo = ProjectState.logoSrc, icon = ProjectState.iconSrc,
    }
    return data
end
function ui:SaveConfig(name)
    name = tostring(name or ProjectState.configName or "default")
    ensureFolder()
    local enc = jsonEncode(serializeConfig())
    if enc and writefile then pcall(writefile, cfgDir() .. "/" .. name .. ".json", enc) end
    return self
end
local function applyConfigData(data)
    if not data then return end
    ProjectState._loadingConfig = true
    if data.uiFont then ui:SetFont(data.uiFont) end
    if data.layout then ProjectState.tabLayout = data.layout end
    if data.search then ProjectState.searchStyle = data.search end
    for _, tab in ipairs(ProjectState.tabs) do
        for _, sec in ipairs(tab.sections) do
            for _, item in ipairs(sec.items) do
                if item.type == "rangeslider" and item.label and not item.noSave then
                    local key = tab.name .. "." .. sec.name .. "." .. item.label
                    local fv = data.flags and data.flags[key]
                    if type(fv) == "table" then
                        local lo, hi = tonumber(fv[1]), tonumber(fv[2])
                        if lo and hi then
                            item.valueLo = snapValue(lo, item); item.valueHi = snapValue(hi, item)
                            if item.valueLo > item.valueHi then item.valueLo, item.valueHi = item.valueHi, item.valueLo end
                            invoke(item.callback, item.valueLo, item.valueHi)
                        end
                    end
                    local kb = data.keybinds and data.keybinds[key]
                    if kb and item.keybind then item.keybind.value = kb[1]; item.keybind.mode = normalizeMode(kb[2]) end
                elseif item.value ~= nil and item.label and item.type ~= "button" and not item.noSave then
                    local key = tab.name .. "." .. sec.name .. "." .. item.label
                    local fv = data.flags and data.flags[key]
                    if fv ~= nil then
                        if item.type == "colorpicker" and type(fv) == "table" then
                            item.value = c3((fv[1] or 1) * 255, (fv[2] or 1) * 255, (fv[3] or 1) * 255)
                            item.alpha = fv[4] or 1; invoke(item.callback, item.value, item.alpha)
                        elseif item.type == "dropdown" then setDropdownValue(item, fv, true)
                        else setItemValue(item, fv, true) end
                    end
                    local kb = data.keybinds and data.keybinds[key]
                    if kb and item.keybind then item.keybind.value = kb[1]; item.keybind.mode = normalizeMode(kb[2]) end
                end
            end
        end
    end

    local s = data.settings
    if s then
        if s.accentA and s.accentB then
            local a = c3((s.accentA[1] or 0) * 255, (s.accentA[2] or 0) * 255, (s.accentA[3] or 0) * 255)
            local b = c3((s.accentB[1] or 0) * 255, (s.accentB[2] or 0) * 255, (s.accentB[3] or 0) * 255)
            ProjectState.baseAccentA = a; ProjectState.baseAccentB = b
            if not s.rainbow then Theme.accentA = a; Theme.accentB = b end
        end
        if s.rainbow ~= nil then ProjectState.rainbow = s.rainbow == true end
        if s.rainbowSpeed then ProjectState.rainbowSpeed = s.rainbowSpeed end
        if s.menuOpacity then ProjectState.menuOpacity = s.menuOpacity end
        if s.noAnim ~= nil then ProjectState.noAnim = s.noAnim == true end
        if s.notifyDur then ProjectState.notifyDur = s.notifyDur end
        if s.hoverEffects ~= nil then ProjectState.hoverEffects = s.hoverEffects ~= false end
        if s.hotkeyEnabled ~= nil then ProjectState.hotkeyEnabled = s.hotkeyEnabled ~= false end
        if s.menuKey then ui:SetMenuKey(s.menuKey) end
        if tonumber(s.w) and tonumber(s.h) then ui:SetSize(s.w, s.h) end
        if s.bg then Theme.bg = c3((s.bg[1] or 0) * 255, (s.bg[2] or 0) * 255, (s.bg[3] or 0) * 255); Theme.sidebar = Theme.bg end
        if s.txt then Theme.text = c3((s.txt[1] or 1) * 255, (s.txt[2] or 1) * 255, (s.txt[3] or 1) * 255) end
        if s.glowMul then ProjectState.glowMul = s.glowMul end
        if s.cardStrk then AL.cardStrk = s.cardStrk end
        if s.hairline then AL.hairline = s.hairline end
        if s.cardFill then AL.card = s.cardFill end
        if s.lite ~= nil then ProjectState.lite = s.lite == true end
        if s.roundScale then ProjectState.roundScale = clamp(tonumber(s.roundScale) or 1, 0, 2.5) end
        if s.smartFps ~= nil then ProjectState.smartFps = s.smartFps == true end
        if s.sidebarPinned ~= nil then ProjectState.sidebarPinned = s.sidebarPinned == true end
        if s.dropdownInline ~= nil then ProjectState.dropdownInline = s.dropdownInline == true end
        if s.bgImg then ui:SetBackgroundImage(s.bgImg, s.bgImgA) else ui:SetBackgroundImage(nil) end
        ui:SetBackgroundEffect(s.bgFx)
        if s.bgFxColor then ProjectState.bgEffectColor = c3((s.bgFxColor[1] or 1) * 255, (s.bgFxColor[2] or 1) * 255, (s.bgFxColor[3] or 1) * 255) else ProjectState.bgEffectColor = nil end
        if s.logo then ui:SetLogo(s.logo) end
        if s.icon then ui:SetIcon(s.icon) end
    end
    if ProjectState.settingsTab then
        local mirror = {
            ["Performance mode"] = ProjectState.lite == true, ["Smart FPS"] = ProjectState.smartFps ~= false,
            ["Animations"] = ProjectState.noAnim ~= true, ["Hover effects"] = ProjectState.hoverEffects ~= false,
            ["Keybind overlay"] = ProjectState.hotkeyEnabled ~= false, ["Collapse sidebar"] = not ProjectState.sidebarPinned,
            ["Inline dropdowns"] = ProjectState.dropdownInline == true, ["Rainbow"] = ProjectState.rainbow == true,
        }
        for _, sec in ipairs(ProjectState.settingsTab.sections or {}) do
            for _, it in ipairs(sec.items or {}) do
                if it.type == "checkbox" and mirror[it.label] ~= nil then it.value = mirror[it.label] end
            end
        end
    end
    ProjectState._loadingConfig = nil
end
function ui:LoadConfig(name)
    name = tostring(name or ProjectState.configName or "default")
    ProjectState._lastLoadOk = false
    local path = cfgDir() .. "/" .. name .. ".json"
    if not (isfile and isfile(path) and readfile) then return self end
    local raw; pcall(function() raw = readfile(path) end)
    local data = raw and jsonDecode(raw)
    if type(data) ~= "table" then return self end   -- missing / torn / corrupt file: don't claim success
    pcall(applyConfigData, data)
    ProjectState._loadingConfig = nil               -- never leave this stuck true if an apply branch errored mid-way
    ProjectState._lastLoadOk = true
    return self
end

local function autoloadFile() return cfgDir() .. "/_autoload.json" end
local function readAutoloadPrefs()
    local f = autoloadFile()
    if not (isfile and isfile(f) and readfile) then return {} end
    local raw; pcall(function() raw = readfile(f) end)
    local t = raw and jsonDecode(raw); return (type(t) == "table") and t or {}
end
local function readAutoloadPref(base) local t = readAutoloadPrefs(); return base and t[tostring(base)] end
local function writeAutoloadPref(base, name)
    if not base then return end
    local t = readAutoloadPrefs(); t[tostring(base)] = name
    ensureFolder(); local enc = jsonEncode(t); if enc and writefile then pcall(writefile, autoloadFile(), enc) end
end
-- auto-SAVE preference, stored per-base in the same file (key prefixed so it never clashes with auto-load names)
local function readAutoSavePref(base) local t = readAutoloadPrefs(); local v = base and t["autosave:" .. tostring(base)]; if v == nil then return nil end; return v == true end
local function writeAutoSavePref(base, on)
    if not base then return end
    local t = readAutoloadPrefs(); t["autosave:" .. tostring(base)] = on == true
    ensureFolder(); local enc = jsonEncode(t); if enc and writefile then pcall(writefile, autoloadFile(), enc) end
end

function ui:ExportConfig()
    local enc = jsonEncode(serializeConfig())
    if not enc or not base64encode then return nil end
    local ok, code = pcall(base64encode, enc)
    return (ok and code) and ("INScfg_" .. code) or nil
end
function ui:ImportConfig(code)
    code = tostring(code or "")
    local b = string.match(code, "^INScfg_(.+)$") or code
    if not base64decode or b == "" then return self end
    local ok, json = pcall(base64decode, b)
    if ok and type(json) == "string" then applyConfigData(jsonDecode(json)) end
    return self
end
function ui:ListConfigs()
    local out = {}
    pcall(function()
        for _, f in ipairs(listfiles(cfgDir())) do
            local n = string.match(f, "([^/\\]+)%.json$")
            if n and n:sub(1, 1) ~= "_" then out[#out + 1] = n end
        end
    end)
    return out
end
function ui:DeleteConfig(name)
    name = tostring(name or "")
    if name ~= "" and delfile then pcall(delfile, cfgDir() .. "/" .. name .. ".json") end
    return self
end
function ui:SetBackgroundEffect(name)
    local valid = false
    if name then for _, e in ipairs(FX_LIST) do if e == name then valid = true; break end end end
    ProjectState.bgEffect = (valid and name ~= "Off") and name or nil
    return self
end
function ui:BackgroundEffects() return FX_LIST end
function ui:SetBackgroundEffectColor(c) ProjectState.bgEffectColor = c; return self end
function ui:SetBackgroundImage(url, alpha)
    ProjectState.bgImgUrl = (url ~= nil and url ~= "") and tostring(url) or nil
    ProjectState.bgImgAlpha = alpha or ProjectState.bgImgAlpha or 0.5
    if ProjectState.bgImg then pcall(function() ProjectState.bgImg.Visible = false; ProjectState.bgImg:Remove() end); ProjectState.bgImg = nil end
    local target = ProjectState.bgImgUrl
    if not target then return self end
    task.spawn(function()
        pcall(function()
            local cache = "INSui_bg_" .. tostring(#target) .. ".dat"
            local b
            if isfile and readfile then local ok; pcall(function() ok = isfile(cache) end); if ok then pcall(function() b = readfile(cache) end) end end
            if not (b and #b > 12) then
                b = game:HttpGet(target)
                if b and #b > 12 and writefile then pcall(function() writefile(cache, b) end) end
            end
            if b and #b > 12 then
                local b1, b2 = string.byte(b, 1, 2)
                if (b1 == 0x89 and b2 == 0x50) or (b1 == 0xFF and b2 == 0xD8) then
                    if ProjectState.bgImgUrl == target then
                        local img = Drawing.new("Image"); img.Data = b; ProjectState.bgImg = img
                    end
                end
            end
        end)
    end)
    return self
end
function ui:SetLogo(src)
    if ProjectState.logoImg then pcall(function() ProjectState.logoImg.Visible = false; ProjectState.logoImg:Remove() end); ProjectState.logoImg = nil end
    if src == nil or src == "" then ProjectState.logoSrc = nil; return self end
    local target = tostring(src)
    local s1, s2 = string.byte(target, 1, 2)
    if #target > 24 and ((s1 == 0x89 and s2 == 0x50) or (s1 == 0xFF and s2 == 0xD8)) then
        ProjectState.logoSrc = nil   -- raw bytes: render it, but NEVER serialize binary (jsonEncode would nil out -> silent save failure)
        pcall(function() local img = Drawing.new("Image"); img.Data = target; img.Visible = false; ProjectState.logoImg = img end)   -- hidden until the draw loop positions it (no top-left flash)
        return self
    end
    ProjectState.logoSrc = target   -- URL / path: safe to serialize
    task.spawn(function()
        pcall(function()
            local cache = "INSui_logo_" .. tostring(#target) .. ".dat"
            local b
            if isfile and readfile then local ok; pcall(function() ok = isfile(cache) end); if ok then pcall(function() b = readfile(cache) end) end end
            if not (b and #b > 12) then
                b = game:HttpGet(target)
                if b and #b > 12 and writefile then pcall(function() writefile(cache, b) end) end
            end
            if b and #b > 12 then
                local b1, b2 = string.byte(b, 1, 2)
                if (b1 == 0x89 and b2 == 0x50) or (b1 == 0xFF and b2 == 0xD8) then
                    if ProjectState.logoSrc == target then local img = Drawing.new("Image"); img.Data = b; img.Visible = false; ProjectState.logoImg = img end
                end
            end
        end)
    end)
    return self
end
function ui:SetIcon(src)   -- the corner gem + minimized bubble icon (separate from the header logo)
    if ProjectState.iconImg then pcall(function() ProjectState.iconImg.Visible = false; ProjectState.iconImg:Remove() end); ProjectState.iconImg = nil end
    if src == nil or src == "" then ProjectState.iconSrc = nil; return self end
    local target = tostring(src)
    local s1, s2 = string.byte(target, 1, 2)
    if #target > 24 and ((s1 == 0x89 and s2 == 0x50) or (s1 == 0xFF and s2 == 0xD8)) then
        ProjectState.iconSrc = nil   -- raw bytes: render it, but NEVER serialize binary (jsonEncode would nil out -> silent save failure)
        pcall(function() local img = Drawing.new("Image"); img.Data = target; img.Visible = false; ProjectState.iconImg = img end)   -- hidden until positioned
        return self
    end
    ProjectState.iconSrc = target   -- URL / path: safe to serialize
    task.spawn(function()
        pcall(function()
            local cache = "INSui_icon_" .. tostring(#target) .. ".dat"
            local b
            if isfile and readfile then local ok; pcall(function() ok = isfile(cache) end); if ok then pcall(function() b = readfile(cache) end) end end
            if not (b and #b > 12) then
                b = game:HttpGet(target)
                if b and #b > 12 and writefile then pcall(function() writefile(cache, b) end) end
            end
            if b and #b > 12 then
                local b1, b2 = string.byte(b, 1, 2)
                if (b1 == 0x89 and b2 == 0x50) or (b1 == 0xFF and b2 == 0xD8) then
                    if ProjectState.iconSrc == target then local img = Drawing.new("Image"); img.Data = b; img.Visible = false; ProjectState.iconImg = img end
                end
            end
        end)
    end)
    return self
end
local WAIFU_BG = "https://raw.githubusercontent.com/nvqren/Matcha-Waifu/refs/heads/main/waifu.png"
local function applyThemeExtras(name)
    if name == "Waifu" then
        Theme.bg = c3(15, 19, 13); Theme.sidebar = Theme.bg
        ui:SetBackgroundImage(WAIFU_BG, 0.12)
    elseif name == "NeverBlox" then
        Theme.bg = c3(15, 16, 21); Theme.sidebar = c3(12, 13, 17)
        ui:SetBackgroundImage(nil)
    elseif name == "Lemon" then
        Theme.bg = c3(18, 17, 13); Theme.sidebar = c3(18, 17, 13)
        ui:SetBackgroundImage(nil)
    else
        Theme.bg = c3(15, 15, 15); Theme.sidebar = Theme.bg
        ui:SetBackgroundImage(nil)
    end
end
function ui:ApplyThemePreset(name)
    local p = ThemePresets[name]
    if p then Theme.accentA = p[1]; Theme.accentB = p[2]; applyThemeExtras(name) end
    return self
end
function ui:ThemePresets()
    local out = {}
    for k in pairs(ThemePresets) do out[#out + 1] = k end
    table.sort(out)
    return out
end
function ui:FontChoices()
    local out = {}
    for _, c in ipairs(FONT_LIST) do out[#out + 1] = c[1] end
    return out
end
function ui:SetFont(name)
    ProjectState.uiFont = fontByName(name)
    ProjectState.uiFontName = name
    return self
end
function ui:SetLayout(mode)
    ProjectState.tabLayout = (mode == "Top" or mode == "top") and "top" or "side"
    return self
end


local function finalDestroy()
    if ProjectState.destroyed then return end
    ProjectState.destroyed = true
    ProjectState.open = false
    ProjectState.dropdown = nil; ProjectState.colorpicker = nil; ProjectState.focus = nil
    pcall(setrobloxinput, true); ProjectState.inputState = true
    removeAllDrawings()
    for _, t in ipairs(ProjectState.tabs) do
        if t._img then pcall(function() t._img:Remove() end); t._img = nil end
        for _, sec in ipairs(t.sections) do
            for _, it in ipairs(sec.items) do
                if it._img then pcall(function() it._img:Remove() end); it._img = nil end
            end
        end
    end
    if ProjectState._gearImg then pcall(function() ProjectState._gearImg:Remove() end); ProjectState._gearImg = nil end
    if ProjectState.bgImg then pcall(function() ProjectState.bgImg:Remove() end); ProjectState.bgImg = nil end
    if ProjectState.avatarImg then pcall(function() ProjectState.avatarImg:Remove() end); ProjectState.avatarImg = nil end
    if ProjectState.logoImg then pcall(function() ProjectState.logoImg:Remove() end); ProjectState.logoImg = nil end
    if ProjectState.iconImg then pcall(function() ProjectState.iconImg:Remove() end); ProjectState.iconImg = nil end
end
function ui:Destroy()
    ProjectState.alive = false; ProjectState.open = false
    if not ProjectState.rendering then finalDestroy() end
end
ui.Unload = ui.Destroy

local function anyListening()
    if ProjectState.kbCapture or ProjectState.spotlightOpen then return true end
    if ProjectState.colorpicker and ProjectState.colorpicker.hexInput then return true end
    for _, it in ipairs(keybindItems) do if it.keybind and it.keybind.listening then return true end end
    return false
end

local function updateRainbow()
    if not ProjectState.rainbow then return end
    local t = (clock() or 0) * (ProjectState.rainbowSpeed or 0.3) * 0.3
    Theme.accentA = hsv(t % 1, 0.65, 1)
    Theme.accentB = hsv((t + 0.12) % 1, 0.72, 1)
end

local function drawDialog(click)
    local d = ProjectState.dialog
    ProjectState._dlgA = approach(ProjectState._dlgA or 0, d and 1 or 0, 18)
    local a = ProjectState._dlgA
    if a < 0.01 then return click end
    local vw, vh = viewportSize()
    rect(0, 0, vw, vh, c3(0, 0, 0), 450, 0, 0.5 * a)
    if not d then return click end
    local dw = 344
    local lines = wrapLines(d.text or "", dw - 44, 13, FontSystem)
    if #lines == 0 then lines = { "" } end
    local dh = 92 + #lines * 18
    local dx = floor(vw / 2 - dw / 2)
    local dy = floor(vh / 2 - dh / 2) - floor((1 - a) * 12)
    local accentMid = ProjectState._accentMid
    rect(dx + 3, dy + 6, dw, dh, c3(0, 0, 0), 451, 12, 0.3 * a)
    rect(dx, dy, dw, dh, Theme.bg, 452, 12, 0.99 * a)
    strokeRect(dx - 1, dy - 1, dw + 2, dh + 2, accentMid, 453, 13, 0.10 * a)
    strokeRect(dx, dy, dw, dh, WHITE, 453, 12, 0.22 * a)
    txt(d.title, dx + 22, dy + 18, accentMid, 16, FontBold, 454, false, false, dw - 44, a)
    for i = 1, #lines do
        txt(lines[i], dx + 22, dy + 48 + (i - 1) * 18, WHITE, 13, FontSystem, 454, false, false, dw - 44, AL.label * a)
    end
    local bh, gap = 30, 10
    local by = dy + dh - bh - 16
    local bw = (dw - 44 - gap) / 2
    local cancelX = dx + 22
    local confirmX = cancelX + bw + gap
    local cancHov = over(cancelX, by, bw, bh)
    local confHov = over(confirmX, by, bw, bh)
    strokeRect(cancelX, by, bw, bh, WHITE, 454, 6, (cancHov and 0.4 or AL.hairline) * a)
    txtC(d.cancel, cancelX + bw / 2, by + bh / 2, WHITE, 13, FontBold, 455, (cancHov and AL.text or AL.dim) * a)
    rect(confirmX, by, bw, bh, accentMid, 454, 6, (confHov and 0.32 or 0.2) * a)
    strokeRect(confirmX, by, bw, bh, accentMid, 455, 6, (confHov and 0.95 or 0.6) * a)
    txtC(d.confirm, confirmX + bw / 2, by + bh / 2, accentMid, 13, FontBold, 455, a)
    if a > 0.5 then
        if Input.esc.click then ProjectState.dialog = nil; if d.onCancel then pcall(d.onCancel) end; Input.esc.click = false; return false end
        if click then
            if over(confirmX, by, bw, bh) then ProjectState.dialog = nil; if d.onConfirm then pcall(d.onConfirm) end; return false end
            if over(cancelX, by, bw, bh) or not over(dx, dy, dw, dh) then ProjectState.dialog = nil; if d.onCancel then pcall(d.onCancel) end; return false end
        end
    end
    return false
end

-- ===================== render step & main loop =====================
local function step()
    resetPool()
    ProjectState.tooltipText = nil
    ProjectState._vpW = nil
    local now = clock() or 0
    ProjectState.dt = clamp(now - ProjectState.lastFrame, 0, 0.05)
    ProjectState.lastFrame = now

    getMouse()
    updateInput()

    ProjectState.drawVisible = approach(ProjectState.drawVisible, ProjectState.open and 1 or 0, 12)

    if (Input.lctrl.held or Input.rctrl.held or Input.ctrl.held) and Input.space.click then
        ProjectState.spotlightOpen = not ProjectState.spotlightOpen
        if ProjectState.spotlightOpen then ProjectState.spotlight = { query = "", sel = 1 } end
        Input.space.click = false
    end

    local mk = Input[menuKey]
    if mk and mk.click and not ProjectState.focus and not anyListening() then
        if ProjectState.minimized then
            ProjectState.minimized = false
            if ProjectState.minPos then ProjectState.x = ProjectState.minPos.x; ProjectState.y = ProjectState.minPos.y; clampWindow() end
            setOpen(true)
        else setOpen(not ProjectState.open) end
    end

    processTextInput()
    if not ProjectState.spotlightOpen then processKeybinds() end
    updateRainbow()
    ProjectState._accentMid = lerpColor(Theme.accentA, Theme.accentB, 0.5)   -- once a frame instead of ~20 Color3.new across the draw path

    if ProjectState.open and not ProjectState.spotlightOpen and not ProjectState.focus and not ProjectState.dropdown and not ProjectState.colorpicker and #ProjectState.tabs > 0 then
        if Input.left.click then
            local i = ProjectState.activeIndex
            repeat i = i - 1 until i < 1 or not ProjectState.tabs[i].hidden
            if i >= 1 then ProjectState.activeIndex = i; ProjectState.activeTab = ProjectState.tabs[i]; ProjectState.contentFade = 0 end
        end
        if Input.right.click then
            local i = ProjectState.activeIndex
            repeat i = i + 1 until i > #ProjectState.tabs or not ProjectState.tabs[i].hidden
            if i <= #ProjectState.tabs then ProjectState.activeIndex = i; ProjectState.activeTab = ProjectState.tabs[i]; ProjectState.contentFade = 0 end
        end
    end

    if Input.m1.released then
        ProjectState.drag = nil; ProjectState.resizeEdge = nil; ProjectState.sliderDrag = nil
        ProjectState.scrollDrag = nil; ProjectState.cpDrag = nil; ProjectState.hkDrag = nil
        ProjectState.contentDrag = nil; ProjectState.textDrag = nil; ProjectState.spTextDrag = nil
        if ProjectState.dropdown then ProjectState.dropdown._sbDrag = nil end
        if ProjectState.spotlight then ProjectState.spotlight._sbDrag = nil end
    end

    local click, held, rightClick = Input.m1.click, Input.m1.held, Input.m2.click

    if ProjectState.drawVisible < 0.01 and not ProjectState.open then
        hideWindowDrawings()
        click = drawBoxes(click, held)
        click = drawHotkeyOverlay(click, held)
        click = drawSpotlight(click)
        drawNotifications()
        drawDialog(click)
        hideUnused()
        return
    end

    clampWindow()

    local wasSpotOpen = ProjectState.spotlightOpen
    local spotClick = click
    local dlgClick = click
    if wasSpotOpen then click = false; rightClick = false; held = false end
    if ProjectState.dialog then click = false; rightClick = false; held = false end
    if (ProjectState.minA or 0) < 0.06 then
        click, held, rightClick = drawWindow(click, held, rightClick)
        click, rightClick = drawDropdown(click, rightClick)
        click = drawColorpicker(click, held)
        click = drawKeyMenu(click)
        drawTooltip()
        ProjectState.lastTooltipText = ProjectState.tooltipText

        if click and ProjectState.focus then ProjectState.focus = nil end
    else
        hideWindowDrawings()
    end
    applyInputState(false)
    click = drawMinBubble(click, held)
    local mA = ProjectState.minA or 0
    if mA > 0.06 and mA < 0.9 then click = false end
    click = drawBoxes(click, held)
    click = drawHotkeyOverlay(click, held)
    click = drawSpotlight(wasSpotOpen and spotClick or false)
    drawNotifications()
    drawDialog(dlgClick)
    if not ProjectState.lite and (ProjectState.minA or 0) < 0.06 then local r = ProjectState._winRect; if r then drawBgEffect(r.x, r.y, r.w, r.h, r.th, r.v) end end   -- no bg fx in perf mode
    hideUnused()
end

local function runStepSafe()
    if safeReadGlobal(LIB_NAME .. "InstanceId") ~= instanceId then ProjectState.alive = false end
    if not ProjectState.alive then
        finalDestroy()
        return
    end
    ProjectState.rendering = true
    local ok, err = pcall(step)
    ProjectState.rendering = false
    if not ok then
        ui:Notify("error", tostring(err), 6)
        ProjectState.errorCount = ProjectState.errorCount + 1
        pcall(setrobloxinput, true); ProjectState.inputState = true
        hideAll()
        if ProjectState.errorCount >= 3 then ProjectState.alive = false; finalDestroy() end
    else
        ProjectState.errorCount = 0
    end
end

local function frameDelay()
    local full = ProjectState.lite and (1 / 60) or (1 / 144)
    if ProjectState.smartFps == false then return full end
    local mx, my = ProjectState.mouseX or 0, ProjectState.mouseY or 0
    local moved = mx ~= (ProjectState._lastMX or -1) or my ~= (ProjectState._lastMY or -1)
    ProjectState._lastMX, ProjectState._lastMY = mx, my
    if moved
        or (Input.m1 and Input.m1.held) or (Input.m2 and Input.m2.held)
        or ProjectState.drag or ProjectState.resizeEdge or ProjectState.scrollDrag
        or ProjectState.dropdown or ProjectState.colorpicker or ProjectState.focus
        or ProjectState.kbCapture or ProjectState.spotlightOpen then
        ProjectState._lastAct = clock() or 0
    end
    local dv, mA, cf = ProjectState.drawVisible or 0, ProjectState.minA or 0, ProjectState.contentFade or 1
    local animating = (dv > 0.01 and dv < 0.99) or (mA > 0.01 and mA < 0.99) or (cf < 0.99)
        or (ProjectState.rainbow and ProjectState.open)
    if animating then return full end
    if ProjectState.open and ((clock() or 0) - (ProjectState._lastAct or 0)) < 0.5 then return full end
    return 1 / 30
end

task.spawn(function()
    while ProjectState.alive do
        if ProjectState._winReady and not ProjectState._didAutoload and safeReadGlobal(LIB_NAME .. "InstanceId") == instanceId then
            -- first frame after the script's whole synchronous setup (incl. AddSettingsTab).
            -- ONLY loads a config when the user picked one in the Auto-load dropdown (pref). autoSave on its
            -- own just SAVES and must NOT load on launch. Runs before the first autosave so the baseline is set.
            -- The instanceId check stops a stale duplicate instance (double-loaded lib) touching configs.
            ProjectState._didAutoload = true
            local asPref = readAutoSavePref(ProjectState._baseConfigName)
            if asPref ~= nil then ProjectState.autoSave = asPref end
            local pref = readAutoloadPref(ProjectState._baseConfigName)
            if pref then
                ProjectState.configName = pref
                pcall(function() ui:LoadConfig(ProjectState.configName) end)
                if ProjectState._lastLoadOk then pcall(function() ui:Notify("config", "auto-loaded: " .. tostring(pref), 4, "info") end) end
            end
            pcall(function() ProjectState._lastCfgEnc = jsonEncode(serializeConfig()) end)
        end
        runStepSafe()
        if ProjectState.alive and ProjectState._didAutoload and ProjectState.autoSave and ((clock() or 0) - (ProjectState._autoSaveT or 0)) > 1.2 then
            ProjectState._autoSaveT = clock() or 0
            pcall(function()
                local enc = jsonEncode(serializeConfig())
                if enc and enc ~= ProjectState._lastCfgEnc then
                    local p = cfgDir() .. "/" .. tostring(ProjectState.configName or "default") .. ".json"
                    if writefile and (ProjectState.configName == ProjectState._baseConfigName or (isfile and isfile(p))) then ensureFolder(); writefile(p, enc); ProjectState._lastCfgEnc = enc end
                end
            end)
        end
        if ProjectState.alive then task.wait(frameDelay()) end
    end
end)

-- ===================== settings tab =====================
local function buildSettingsTab(win, icon)
    local tab = win:Tab("Settings", icon or "cog")
    tab._tab.hidden = true
    ProjectState.settingsTab = tab._tab
    ProjectState.settingsIcon = icon or "cog"
    ProjectState.settingsIndex = #ProjectState.tabs

    local th = tab:Section("Theme", "Left")

    ProjectState.baseAccentA = ProjectState.baseAccentA or Theme.accentA
    ProjectState.baseAccentB = ProjectState.baseAccentB or Theme.accentB
    if not ProjectState.defaultTheme then
        ProjectState.defaultTheme = { accentA = Theme.accentA, accentB = Theme.accentB, bg = Theme.bg, text = Theme.text, sidebar = Theme.sidebar }
    end
    local presetChoices = { "Default" }
    for _, n in ipairs(ui:ThemePresets()) do presetChoices[#presetChoices + 1] = n end
    local presetDrop, c1pick, c2pick
    local function applyAccents(a, b)
        ProjectState.baseAccentA = a; ProjectState.baseAccentB = b
        if not ProjectState.rainbow then Theme.accentA = a; Theme.accentB = b end
    end
    presetDrop = th:Dropdown("Preset", { "Default" }, presetChoices, false, function(v)
        local name = v[1]
        if name == "Default" then
            local dt = ProjectState.defaultTheme
            applyAccents(dt.accentA, dt.accentB)
            Theme.bg = dt.bg; Theme.text = dt.text; Theme.sidebar = dt.sidebar
            if c1pick then c1pick.item.value = dt.accentA end
            if c2pick then c2pick.item.value = dt.accentB end
        elseif name and name ~= "Custom" then
            local p = ThemePresets[name]
            if p then
                applyAccents(p[1], p[2])
                applyThemeExtras(name)
                if c1pick then c1pick.item.value = p[1] end
                if c2pick then c2pick.item.value = p[2] end
            end
        end
    end, "Default = the look this script ships with; pick a preset, or a colour below for Custom", true)
    c1pick = th:Colorpicker("Color 1", Theme.accentA, function(c) applyAccents(c, ProjectState.baseAccentB); if presetDrop and not ProjectState._loadingConfig then presetDrop:Set({ "Custom" }) end end)
    c2pick = th:Colorpicker("Color 2", Theme.accentB, function(c) applyAccents(ProjectState.baseAccentA, c); if presetDrop and not ProjectState._loadingConfig then presetDrop:Set({ "Custom" }) end end)
    th:Toggle("Rainbow", ProjectState.rainbow == true, function(on)
        if on then
            ProjectState.baseAccentA = ProjectState.baseAccentA or Theme.accentA
            ProjectState.baseAccentB = ProjectState.baseAccentB or Theme.accentB
        else
            Theme.accentA = ProjectState.baseAccentA or Theme.accentA
            Theme.accentB = ProjectState.baseAccentB or Theme.accentB
        end
        ProjectState.rainbow = on
    end)
    th:Slider("Rainbow speed", 30, 1, 5, 200, "%", function(v) ProjectState.rainbowSpeed = v / 100 end)

    local apr = tab:Section("Appearance", "Left")
    apr:Colorpicker("Background", Theme.bg, function(c) Theme.bg = c; Theme.sidebar = c end, 1)
    apr:Colorpicker("Text color", Theme.text, function(c) Theme.text = c end, 1)
    apr:Slider("Card glow", 100, 5, 0, 200, "%", function(v) ProjectState.glowMul = v / 100 end, "strength of the accent glow when you hover a section card")
    apr:Dropdown("Background FX", { ProjectState.bgEffect or "Off" }, FX_LIST, false, function(v) ProjectState.bgEffect = (v[1] and v[1] ~= "Off") and v[1] or nil end, "decorative particles behind the menu (off by default)")
    apr:Colorpicker("FX colour", c3(255, 255, 255), function(c) ProjectState.bgEffectColor = c end, 1):Tooltip("recolour the background particles; untouched = each effect's own colour")
    apr:Slider("Border", 6, 1, 0, 30, "", function(v) AL.cardStrk = v / 100; AL.hairline = v / 100 * 1.6 end, "how visible the card / control outlines are")
    apr:Slider("Frost", 3, 1, 0, 12, "", function(v) AL.card = v / 100 end, "how milky the card fills are")
    apr:Slider("Corner radius", floor((ProjectState.roundScale or 1) * 100 + 0.5), 5, 0, 250, "%", function(v) ProjectState.roundScale = clamp((tonumber(v) or 100) / 100, 0, 2.5) end, "roundness of every corner; 100% = default, 0% = sharp")
    apr:Toggle("Performance mode", ProjectState.lite == true, function(on) ProjectState.lite = on end,
        "lite rendering for weak PCs: 60fps, no shadow / outer glow / animations, sidebar stays open")
    apr:Toggle("Smart FPS", ProjectState.smartFps ~= false, function(on) ProjectState.smartFps = on end,
        "drop to ~30fps when idle / minimized / closed and jump to full speed on activity, frees the CPU for the game")

    local ifa = tab:Section("Interface", "Right")
    ifa:Keybind("Menu key", menuKey, function(k) ui:SetMenuKey(k); ui:Notify("menu key", "set to " .. string.upper(k), 2) end,
        "the key that opens / closes this menu")
    ifa:Toggle("Keybind overlay", ProjectState.hotkeyEnabled ~= false, function(on) ProjectState.hotkeyEnabled = on end)
    ifa:Toggle("Hover effects", ProjectState.hoverEffects ~= false, function(on) ProjectState.hoverEffects = on end)
    ifa:Toggle("Collapse sidebar", not ProjectState.sidebarPinned, function(on) ProjectState.sidebarPinned = not on end,
        "on = the sidebar shrinks to an icon rail and expands on hover; off = it always stays open")
    ifa:Toggle("Inline dropdowns", ProjectState.dropdownInline == true, function(on) ProjectState.dropdownInline = on end,
        "put the dropdown box on the same row as its label instead of below it")
    ifa:Dropdown("Tab layout", { ProjectState.tabLayout == "top" and "Top" or "Sidebar" }, { "Sidebar", "Top" }, false,
        function(v) if v[1] then ui:SetLayout(v[1] == "Top" and "top" or "side") end end, "tabs on the left rail or across the top")
    local sstCur = ProjectState.searchStyle or "bar"
    ifa:Dropdown("Search", { sstCur:sub(1, 1):upper() .. sstCur:sub(2) }, { "Bar", "Icon", "Off" }, false,
        function(v) if v[1] then ProjectState.searchStyle = string.lower(v[1]) end end, "titlebar search: a bar, just an icon, or hidden (Ctrl+Space always works)")
    ifa:Dropdown("Font", { ProjectState.uiFontName or "Default" }, ui:FontChoices(), false,
        function(v) if v[1] then ui:SetFont(v[1]); ui:Notify("ui", "font: " .. v[1], 2) end end,
        "UI font, Matcha built-ins only (custom web fonts can't be loaded into Drawing)", true)
    ifa:Slider("Menu opacity", 92, 1, 40, 100, "%", function(v) ProjectState.menuOpacity = v / 100 end)
    ifa:Toggle("Animations", ProjectState.noAnim ~= true, function(on) ProjectState.noAnim = not on end)
    ifa:Slider("Notify time", 5, 1, 1, 15, "s", function(v) ProjectState.notifyDur = v end)

    local cf = tab:Section("Configs", "Right")
    local nameBox = cf:Textbox("Name", ProjectState.configName or "default", function(t) ProjectState.configName = (t ~= "" and t) or "default" end)
    nameBox.item.noSave = true   -- config-management controls must NOT be stored in a config: else loading a
    local saved, autoDrop        -- config rewrites configName / the Config + Auto-load selections (feedback loop)
    local function autoChoices() local c = { "Off" }; for _, n in ipairs(ui:ListConfigs()) do c[#c + 1] = n end; return c end
    local function refresh()
        if saved then saved:UpdateChoices(ui:ListConfigs()) end
        if autoDrop then autoDrop:UpdateChoices(autoChoices()) end
    end
    cf:Button("Save", function() ui:SaveConfig(ProjectState.configName); refresh(); ui:Notify("config", "saved: " .. tostring(ProjectState.configName), 4, "success") end)
       :AddButton("Load", function() local n = ProjectState.configName; local ok = false; for _, c in ipairs(ui:ListConfigs()) do if c == n then ok = true; break end end; if ok then ui:LoadConfig(n); ui:Notify("config", "loaded: " .. tostring(n), 3) else ui:Notify("config", "no config named " .. tostring(n), 3, "warning") end end)
       :AddButton("Delete", function() ui:DeleteConfig(ProjectState.configName); if saved then saved:Set({}) end; refresh(); ui:Notify("config", "deleted", 3, "warning") end)
    saved = cf:Dropdown("Config", {}, ui:ListConfigs(), false, function(v) if v[1] then ProjectState.configName = v[1]; nameBox:Set(v[1]) end end, "pick a saved config, then Load or Delete it", true)
    saved.item.noSave = true
    local asPref = readAutoSavePref(ProjectState._baseConfigName)
    if asPref ~= nil then ProjectState.autoSave = asPref end
    local autoSaveT = cf:Toggle("Auto-save", ProjectState.autoSave == true, function(on) ui:SetAutoSave(on); writeAutoSavePref(ProjectState._baseConfigName, on); ui:Notify("config", on and "auto-save on" or "auto-save off", 2) end,
        "save changes to the current config automatically as you change things; off = nothing is written until you press Save")
    autoSaveT.item.noSave = true
    autoDrop = cf:Dropdown("Auto-load", { readAutoloadPref(ProjectState._baseConfigName) or "Off" }, autoChoices(), false, function(v)
        local sel = v[1]
        if sel and sel ~= "Off" then writeAutoloadPref(ProjectState._baseConfigName, sel); ui:Notify("config", "auto-load: " .. sel, 3)
        else writeAutoloadPref(ProjectState._baseConfigName, nil); ui:Notify("config", "auto-load off", 2) end
    end, "load a config every launch (Off = none); separate from Auto-save", true)
    autoDrop.item.noSave = true

    local sys = tab:Section("System", "Right")
    sys:Button("Re-center window", function() ui:Center(); ui:Notify("ui", "re-centered", 2) end)
    sys:Button("Minimize", function() ProjectState.minimized = not ProjectState.minimized; if ProjectState.minimized then ProjectState.minPos = { x = ProjectState.x + 6, y = ProjectState.y + 4 }; ProjectState.dropdown = nil; ProjectState.colorpicker = nil; ProjectState.keyMenu = nil; ProjectState.focus = nil end end)

    return tab
end

-- ===================== CreateWindow (entry point) =====================
local function stripGlyphs(s)
    s = tostring(s or "")
    if s == "" then return s end
    local ok, out = pcall(function()
        local parts = {}
        for _, cp in utf8.codes(s) do
            if cp < 0x2190 and not (cp >= 0x200B and cp <= 0x200F) then
                parts[#parts + 1] = utf8.char(cp)
            end
        end
        return table.concat(parts)
    end)
    if not ok then out = (s:gsub("[\240-\244][\128-\191]*", "")) end
    return (out:gsub("%s+$", ""):gsub("^%s+", ""))
end
function ui:CreateWindow(config)
    config = type(config) == "table" and config or {}
    ProjectState.title = stripGlyphs(config.title or "uilib")
    if config.subtitle == "auto" then
        ProjectState.subtitle = ""
        task.spawn(function()
            local nm
            pcall(function() nm = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name end)
            if not (type(nm) == "string" and nm ~= "") then
                pcall(function()
                    local u = game:HttpGet("https://apis.roblox.com/universes/v1/places/" .. tostring(game.PlaceId) .. "/universe")
                    local uid = u and u:match('"universeId":%s*(%d+)')
                    if uid then
                        local g = game:HttpGet("https://games.roblox.com/v1/games?universeIds=" .. uid)
                        if g then nm = g:match('"name":"(.-)"') end
                    end
                end)
            end
            if not (type(nm) == "string" and nm ~= "") then
                pcall(function() local n = game.Name; if type(n) == "string" and n ~= "" and n ~= "Game" and n ~= "Ugc" then nm = n end end)
            end
            if type(nm) == "string" and nm ~= "" then ProjectState.subtitle = stripGlyphs(nm) end
        end)
    else
        ProjectState.subtitle = stripGlyphs(config.subtitle or "")
    end
    if config.configFolder and sanitizeFolder(config.configFolder) ~= "" then
        ProjectState.cfgFolder = sanitizeFolder(config.configFolder)
    else
        local t = sanitizeFolder(ProjectState.title)
        if t ~= "" and t ~= "uilib" then ProjectState.cfgFolder = LIB_NAME .. "_" .. t end
    end
    if config.size then ProjectState.w = config.size.X; ProjectState.h = config.size.Y; ProjectState.wTarget = ProjectState.w; ProjectState.hTarget = ProjectState.h end
    if config.configName then ProjectState.configName = tostring(config.configName) end
    ProjectState._baseConfigName = ProjectState.configName

    local vw, vh = viewportSize()
    ProjectState.x = config.position and config.position.X or floor(vw / 2 - ProjectState.w / 2)
    ProjectState.y = config.position and config.position.Y or floor(vh / 2 - ProjectState.h / 2)
    if config.menuKey then ui:SetMenuKey(config.menuKey) end
    if config.gameInput ~= nil then ui:SetGameInput(config.gameInput) end
    if config.logo then ui:SetLogo(config.logo) end
    if config.icon then ui:SetIcon(config.icon) end
    if config.opacity then ui:SetOpacity(config.opacity) end
    if config.rounding ~= nil then ui:SetRounding(config.rounding) end
    if config.rowLines ~= nil then ui:SetRowLines(config.rowLines) end
    if config.smartFps ~= nil then ProjectState.smartFps = config.smartFps == true end
    if config.theme then ui:SetTheme(config.theme) end
    if config.autoSave then ui:SetAutoSave(true) end

    local win = setmetatable({}, { __index = ui })
    function win:Tab(name, icon) return ui:Tab(name, icon) end
    function win:AddSettingsTab(icon)
        if ProjectState.settingsApi then return ProjectState.settingsApi end   -- only build it once
        ProjectState.settingsApi = buildSettingsTab(win, icon)
        return ProjectState.settingsApi
    end
    function win:GetSettingsTab() return ProjectState.settingsApi end   -- nil till the settings tab's been made
    function win:SettingsSection(name, side, desc)                       -- drop your own card into the settings tab
        return win:AddSettingsTab():Section(name, side or "Right", desc)
    end
    function win:SetLogo(src) return ui:SetLogo(src) end
    function win:SetIcon(src) return ui:SetIcon(src) end
    function win:SetOpacity(v) return ui:SetOpacity(v) end
    function win:SaveConfig(n) return ui:SaveConfig(n) end
    function win:LoadConfig(n) return ui:LoadConfig(n) end
    function win:autoloadConfig(n) ui:LoadConfig(n or ProjectState.configName); return self end
    task.spawn(function()
        ProjectState._avLog = {}
        local function alog(m) local t = ProjectState._avLog; if t then t[#t + 1] = tostring(m) end end
        local function isPng(b)
            if not b or #b < 12 then return false end
            local a, c, d, e = string.byte(b, 1, 4)
            return (a == 0x89 and c == 0x50 and d == 0x4E and e == 0x47) or (a == 0xFF and c == 0xD8)
        end
        local function setImg(b)
            if not isPng(b) then return false end
            local img
            local ok = pcall(function() img = Drawing.new("Image"); img.Data = b; img.Visible = false end)
            if ok and img then ProjectState.avatarImg = img; return true end
            return false
        end
        local uid, uname
        for _ = 1, 30 do
            local lp; pcall(function() lp = game:GetService("Players").LocalPlayer end)
            if lp then
                pcall(function() if lp.Name and lp.Name ~= "" then uname = tostring(lp.Name) end end)
                local u; pcall(function() u = lp.UserId end)
                if u and u ~= 0 then uid = u; break end
            end
            task.wait(0.12)
        end
        alog("UserId poll -> uid=" .. tostring(uid) .. " name=" .. tostring(uname))
        if (not uid) and uname then
            pcall(function()
                local body = '{"usernames":["' .. uname .. '"],"excludeBannedUsers":false}'
                local resp
                if httppost then resp = httppost("https://users.roblox.com/v1/usernames/users", body, "application/json")
                elseif httprequest then local r = httprequest({ Url = "https://users.roblox.com/v1/usernames/users", Method = "POST", Body = body, Headers = { ["Content-Type"] = "application/json" } }); resp = r and (r.Body or r.body) end
                local id = resp and string.match(resp, '"id":%s*(%d+)')
                if id then uid = tonumber(id) end
            end)
            alog("name->id fallback -> uid=" .. tostring(uid))
        end
        if not uid then alog("FAILED: could not resolve a UserId"); return end
        local cache = "INSui_av_" .. tostring(uid) .. ".dat"
        if isfile and readfile then
            local ok; pcall(function() ok = isfile(cache) end)
            if ok then local c; pcall(function() c = readfile(cache) end); if setImg(c) then alog("loaded from disk cache"); return end end
        end
        local endpoints = {
            "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=" .. tostring(uid) .. "&size=150x150&format=Png&isCircular=false",
            "https://thumbnails.roproxy.com/v1/users/avatar-headshot?userIds=" .. tostring(uid) .. "&size=150x150&format=Png&isCircular=false",
            "https://thumbnails.roblox.com/v1/users/avatar-bust?userIds=" .. tostring(uid) .. "&size=150x150&format=Png&isCircular=false",
        }
        for attempt = 1, 5 do
            for ei, ep in ipairs(endpoints) do
                local got = false
                pcall(function()
                    local meta = game:HttpGet(ep)
                    local state = meta and string.match(meta, '"state":%s*"(%w+)"')
                    local url = meta and string.match(meta, '"imageUrl":"([^"]+)"')
                    alog("ep" .. ei .. " try" .. attempt .. ": state=" .. tostring(state) .. " url=" .. (url and "yes" or "no"))
                    if url and url ~= "" then
                        url = url:gsub("\\/", "/")
                        local b = game:HttpGet(url)
                        alog("  cdn bytes=" .. (b and #b or 0) .. " img=" .. tostring(isPng(b)))
                        if setImg(b) then if writefile then pcall(function() writefile(cache, b) end) end; alog("  OK avatar set"); got = true end
                    end
                end)
                if got then return end
            end
            task.wait(0.7)
        end
        alog("FAILED: no usable image after retries")
    end)
    applyInputState(true)
    -- config auto-load is driven from the render loop's first frame (NOT a task.wait-deferred coroutine):
    -- that guarantees it runs after the script's full synchronous setup incl. AddSettingsTab, so Settings-tab
    -- widgets restore, and before the first autosave so a stale autosave can't clobber the saved config.
    -- open only now that the window exists; the default is open=false so a transient/superseded lib instance
    -- (which never reaches CreateWindow) never paints the screen-dim -> no load-time flicker
    ProjectState.open = (config.startOpen ~= false)
    ProjectState._autoSaveT = clock() or 0   -- real 1.2s warm-up before the first autosave (os.clock may already be huge)
    ProjectState._winReady = true
    return win
end

safeWriteGlobal(LIB_NAME, ui)
safeWriteGlobal(LIB_NAME .. "UI", ui)
return ui
-- ===================== INSUI_FILE_END (loader completeness sentinel - keep last) =====================
