-- Web of Night City: Spider-Man 2 style web-swinging for Cyberpunk 2077 (Cyber Engine Tweaks mod).
-- Behaviour, numbers and game hooks are defined in design/sheets/*.json and generated into generated/sheets.lua.
local sheets = require("generated/sheets")
local api = require("modules/game_api")
local mover = require("modules/mover")
local settings = require("modules/settings")
local ui = require("modules/ui")

local WebOfNightCity = { version = "0.1.0" }
local m

-- Route a game action or CET binding to the trigger rows in the inputs sheet.
local function actionMatches(row, name)
    for _, a in ipairs(row.game_actions) do if a == name then return true end end
    return false
end

local function onGameAction(name, kind)
    if settings.logActions then print("[WebOfNightCity] action", name, kind) end
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

registerForEvent("onInit", function()
    settings.init(sheets)
    m = mover.new(api, settings.T)
    m.enabled = settings.enabled
    WebOfNightCity.mover = m -- reachable from other mods via GetMod("web_of_night_city")
    api.observeLocomotion()
    api.observeActions(onGameAction)
    print("[WebOfNightCity] " .. WebOfNightCity.version .. " ready")
end)

registerInput(sheets.inputs.swing_hold.cet_input_id, "Web swing (hold)", function(down) if m then m:onSwing(down) end end)
registerInput(sheets.inputs.wings_toggle.cet_input_id, "Web wings", function(down) if m and down then m:onWings() end end)
registerInput(sheets.inputs.zip_press.cet_input_id, "Web zip", function(down) if m and down then m:onZip() end end)

registerForEvent("onUpdate", function(dt)
    if m then m:update(dt) end
end)

registerForEvent("onDraw", function()
    if not m then return end
    pcall(ui.drawWeb, api, m, sheets)
    ui.drawSettings(settings, m, sheets)
end)

registerForEvent("onOverlayOpen", function() ui.overlayOpen = true end)
registerForEvent("onOverlayClose", function() ui.overlayOpen = false end)

return WebOfNightCity
