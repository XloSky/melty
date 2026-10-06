-- Spider-Punk 2077: Spider-Man 2 style web-swinging for Cyberpunk 2077 (Cyber Engine Tweaks mod).
-- Behaviour, numbers and game hooks are defined in design/sheets/*.json and generated into generated/sheets.lua.
local sheets = require("generated/sheets")
local api = require("modules/game_api")
local mover = require("modules/mover")
local settings = require("modules/settings")
local ui = require("modules/ui")

local SpiderPunk2077 = { version = "0.1.0" }
local m

-- Route a game action to the trigger rows in the inputs sheet.
local function actionMatches(row, name)
    for _, a in ipairs(row.game_actions) do if a == name then return true end end
    return false
end

local function onGameAction(name, kind)
    local I = sheets.inputs
    if actionMatches(I.aim_state, name) then
        if kind == "BUTTON_PRESSED" then m:onAim(true) elseif kind == "BUTTON_RELEASED" then m:onAim(false) end
    end
    if actionMatches(I.swing_hold, name) then
        if kind == "BUTTON_PRESSED" then m:onSwing(true) elseif kind == "BUTTON_RELEASED" then m:onSwing(false) end
    end
    if actionMatches(I.wings_toggle, name) and kind == "BUTTON_PRESSED" then
        if m.mode ~= "idle" or m:airborne() then m:onWings() end
    end
end

-- Two input routes feed one press/release state per action (inputs sheet "about"):
-- polling is authoritative for an action while it is producing readings (within the last half second);
-- game events cover the rest, including if polling stops working later.
local watched, held, polledAt = {}, {}, {}
local now = 0
local inputRoute = "none yet"
for _, row in pairs(sheets.inputs) do
    for _, a in ipairs(row.game_actions) do watched[a] = true end
end

local function setAction(name, isDown, route)
    if route == "event" and polledAt[name] and now - polledAt[name] < 0.5 then return end
    if (held[name] or false) == isDown then return end
    held[name] = isDown
    if settings.logActions then print("[SpiderPunk2077] " .. route, name, isDown and "pressed" or "released") end
    onGameAction(name, isDown and "BUTTON_PRESSED" or "BUTTON_RELEASED")
end

local function pollInputs()
    for name in pairs(watched) do
        local v = api.pollAction(name)
        if v ~= nil then
            polledAt[name] = now
            inputRoute = "polling"
            setAction(name, v > 0.5, "poll")
        end
    end
end

registerForEvent("onInit", function()
    settings.init(sheets)
    m = mover.new(api, settings.T)
    m.enabled = settings.enabled
    SpiderPunk2077.mover = m -- reachable from other mods via GetMod("spider_punk_2077")
    api.observeLocomotion()
    api.observeActions(function(name, kind)
        if not watched[name] then return end
        if inputRoute == "none yet" then inputRoute = "game events" end
        if kind == "BUTTON_PRESSED" then setAction(name, true, "event")
        elseif kind == "BUTTON_RELEASED" then setAction(name, false, "event") end
    end)
    print("[SpiderPunk2077] " .. SpiderPunk2077.version .. " ready")
end)

registerInput(sheets.inputs.swing_hold.cet_input_id, "Web swing (hold)", function(down) if m then m:onSwing(down) end end)
registerInput(sheets.inputs.wings_toggle.cet_input_id, "Web wings", function(down) if m and down then m:onWings() end end)
registerInput(sheets.inputs.zip_press.cet_input_id, "Web zip", function(down) if m and down then m:onZip() end end)

registerForEvent("onUpdate", function(dt)
    if not m then return end
    now = now + dt
    pollInputs()
    m:update(dt)
end)

registerForEvent("onDraw", function()
    if not m then return end
    pcall(ui.drawWeb, api, m, sheets)
    ui.drawSettings(settings, m, sheets, inputRoute)
end)

registerForEvent("onOverlayOpen", function() ui.overlayOpen = true end)
registerForEvent("onOverlayClose", function() ui.overlayOpen = false end)

return SpiderPunk2077
