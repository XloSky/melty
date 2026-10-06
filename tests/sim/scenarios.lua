-- One function per row of design/sheets/tests.json. Each returns ok, details.
local H = require("harness")
local S = {}

local function has(list, item)
    for _, v in ipairs(list) do if v == item then return true end end
    return false
end

local function T(id) return H.mod.mover.T(id) end

-- Feet height above the street or roof below, measured with the sim's own raycast.
local function heightAboveGround(p)
    local hit = H.raycast({ x = p.x, y = p.y, z = p.z + 0.5 }, { x = p.x, y = p.y, z = p.z - 200 })
    return hit and (p.z - hit.z) or math.huge
end

-- Run off the roof holding Jump; let go on each up-swing; grab a second web; let go again.
local function twoSwings(duration, extra)
    local swings, released, lowest = 0, 0, math.huge
    local prev = "idle"
    local s = H.run({ pos = { x = 0, y = -8, z = 40 }, yaw = 0, pitch = 5 }, {
        { t = 0.0, run = true },
        { t = 0.9, action = "Jump", kind = "BUTTON_PRESSED" },
    }, duration, function(t, P, m, stats)
        if m.mode == "swing" and prev ~= "swing" then swings = swings + 1 end
        if m.mode == "swing" then
            lowest = math.min(lowest, heightAboveGround(P.pos))
            if m.vel.z > 2 and released < swings then
                released = released + 1
                H.fire("Jump", "BUTTON_RELEASED")
                if swings < 2 then H.pendingPress = t + 0.5 end
            end
        end
        if H.pendingPress and t >= H.pendingPress then
            H.pendingPress = nil
            H.fire("Jump", "BUTTON_PRESSED")
        end
        prev = m.mode
        if extra then extra(t, P, m, stats) end
    end)
    return s, swings, lowest
end

function S.t_swing_from_roof()
    local start = { x = 0, y = -8, z = 40 }
    local s, swings, lowest = twoSwings(10)
    local dist = math.sqrt((s.final.x - start.x) ^ 2 + (s.final.y - start.y) ^ 2)
    local ok = swings >= 2 and lowest >= T("swing_floor_clearance") - 1 and dist >= 80 and s.maxSpeed >= 18
        and (s.maxDrivenSpeed or 0) <= T("max_speed") + 1 and s.insideBuilding == 0
    return ok, string.format("swings=%d lowest=%.1fm travelled=%.1fm peak=%.1fm/s drivenPeak=%.1fm/s inside=%d webLines=%d events=%s",
        swings, lowest, dist, s.maxSpeed, s.maxDrivenSpeed or 0, s.insideBuilding, s.webLines, table.concat(s.events, ","))
end

function S.t_glide()
    local worstSink, bestH = 0, 0
    local script = {
        { t = 0.0, run = true },
        { t = 0.9, action = "Jump", kind = "BUTTON_PRESSED" },
        { t = 1.0, action = "Jump", kind = "BUTTON_RELEASED" },
        { t = 1.4, action = "ToggleCrouch", kind = "BUTTON_PRESSED" },
        { t = 1.4, action = "Crouch", kind = "BUTTON_PRESSED" }, -- both can arrive for one press
    }
    local s = H.run({ pos = { x = 0, y = -8, z = 40 }, yaw = 0, pitch = 0 }, script, 8, function(t, P, m)
        if m.mode == "glide" then
            worstSink = math.max(worstSink, -m.vel.z)
            bestH = math.max(bestH, math.sqrt(m.vel.x ^ 2 + m.vel.y ^ 2))
        end
    end)
    local ok = (s.modes.glide or 0) > 0 and worstSink <= T("glide_sink") + 0.5 and bestH >= 0.9 * T("glide_speed") and s.insideBuilding == 0
    return ok, string.format("glideFrames=%d worstSink=%.2f bestHorizontal=%.1f inside=%d events=%s",
        s.modes.glide or 0, worstSink, bestH, s.insideBuilding, table.concat(s.events, ","))
end

function S.t_zip()
    local aimed = { x = 0, y = 350, z = 1.7 + 50 * math.tan(math.rad(10)) }
    local closest = math.huge
    local script = {
        { t = 0.0, look = { 0, 10 } },
        { t = 0.2, action = "CameraAim", kind = "BUTTON_PRESSED" },
        { t = 0.4, action = "Jump", kind = "BUTTON_PRESSED" },
        { t = 0.45, action = "Jump", kind = "BUTTON_RELEASED" },
        { t = 0.6, action = "CameraAim", kind = "BUTTON_RELEASED" },
    }
    local s = H.run({ pos = { x = 0, y = 300, z = 0 }, yaw = 0, pitch = 10 }, script, 4, function(t, P)
        local d = math.sqrt((P.pos.x - aimed.x) ^ 2 + (P.pos.y - aimed.y) ^ 2 + (P.pos.z + 1.0 - aimed.z) ^ 2)
        closest = math.min(closest, d)
    end)
    local ok = has(s.events, "idle->zip") and closest <= 3 and s.insideBuilding == 0 and s.fallDamage == 0
    return ok, string.format("closest=%.2fm inside=%d fallDamage=%d events=%s", closest, s.insideBuilding, s.fallDamage, table.concat(s.events, ","))
end

function S.t_landing()
    local handbacks, worst = 0, 0
    local prev = "idle"
    local s = twoSwings(16, function(t, P, m)
        if prev ~= "idle" and m.mode == "idle" then
            handbacks = handbacks + 1
            worst = math.max(worst, heightAboveGround(P.pos))
        end
        prev = m.mode
    end)
    local ok = handbacks >= 1 and worst <= T("ground_probe") and s.fallDamage == 0 and (s.lastGameLandingSpeed or 0) < 3
    return ok, string.format("handbacks=%d worstHeight=%.2fm fallDamage=%d gameLandingSpeed=%.2f events=%s", handbacks, worst, s.fallDamage, s.lastGameLandingSpeed or 0, table.concat(s.events, ","))
end

function S.t_jump_not_stolen()
    local script = {
        { t = 0.2, action = "Jump", kind = "BUTTON_PRESSED" },
        { t = 0.3, action = "Jump", kind = "BUTTON_RELEASED" },
    }
    local s = H.run({ pos = { x = 0, y = 200, z = 0 }, yaw = 0, pitch = 0 }, script, 2)
    local ok = (s.modes.swing or 0) == 0
    return ok, string.format("swingFrames=%d events=%s", s.modes.swing or 0, table.concat(s.events, ","))
end

return S
