-- Drawing: the web strand (visuals.web_line) every frame, and the settings window while the CET overlay is open.
local vec = require("modules/vec")

local ui = { overlayOpen = false }

function ui.drawWeb(api, mover, sheets)
    local anchor = mover.anchor
    if anchor == nil then return end
    local player = api.player()
    if not player then return end
    local cam = api.camera(player)
    if vec.dot(vec.sub(anchor, cam.pos), cam.fwd) <= 0.1 then return end -- behind the camera
    local wrist = vec.add(vec.add(vec.add(cam.pos, vec.scale(cam.right, 0.25)), vec.scale(cam.up, -0.30)), vec.scale(cam.fwd, 0.6))
    local x1, y1 = api.project(wrist)
    local x2, y2 = api.project(anchor)
    if not (x1 and x2) then return end
    local style = sheets.visuals.web_line
    api.drawLine(x1, y1, x2, y2, style.color_rgba, style.thickness)
end

function ui.drawSettings(settings, mover, sheets)
    if not ui.overlayOpen then return end
    if ImGui.Begin("Web of Night City") then
        local changed
        settings.enabled, changed = ImGui.Checkbox("Web-swinging on", settings.enabled)
        if changed then mover.enabled = settings.enabled; settings.save() end
        settings.logActions = ImGui.Checkbox("Log input action names to the CET console", settings.logActions)
        ImGui.Separator()
        ImGui.Text("Hold Jump in the air: swing   |   Crouch in the air: web wings")
        ImGui.Text("Aim + Jump: web zip   |   Let go of Jump: fling with your momentum")
        ImGui.Separator()
        local ids = {}
        for id, row in pairs(sheets.tuning) do if row.exposed then ids[#ids + 1] = id end end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local row = sheets.tuning[id]
            local v, used = ImGui.SliderFloat(row.label .. " (" .. row.unit .. ")", settings.T(id), row.min, row.max)
            if used then settings.values[id] = v; settings.save() end
        end
        if ImGui.Button("Reset to defaults") then settings.reset(); settings.save() end
        ImGui.Text("State: " .. mover.mode)
    end
    ImGui.End()
end

return ui
