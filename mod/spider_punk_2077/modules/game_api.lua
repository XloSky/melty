-- The only file that talks to Cyberpunk 2077 / Cyber Engine Tweaks.
-- Each function implements one row of design/sheets/hooks.json (named in its comment).
-- Calls whose hooks row is not source-verified run inside pcall and use the row's fallback.
local vec = require("modules/vec")

local api = { scriptInterface = nil, warned = {}, basisTurn = 0 }

local function warnOnce(key, msg)
    if not api.warned[key] then
        api.warned[key] = true
        print("[SpiderPunk2077] " .. msg)
    end
end

local function toV4(p) return Vector4.new(p.x, p.y, p.z, 1) end
local function fromV(v) return { x = v.x, y = v.y, z = v.z } end

-- hooks.locomotion_interface
function api.observeLocomotion()
    Observe("LocomotionEventsTransition", "OnUpdate", function(_, _, _, scriptInterface)
        if scriptInterface then api.scriptInterface = scriptInterface end
    end)
end

-- hooks.on_action (backup input route): calls handler(actionName, actionType).
-- Melty reports that reading the name fails on CET 1.37.1, so try every known way and stay silent if none works.
local function readName(a)
    local tries = {
        function() return a:GetName(a) end,
        function() return ListenerAction.GetName(a) end,
        function() return a:GetName() end,
    }
    for _, try in ipairs(tries) do
        local ok, n = pcall(try)
        if ok and n ~= nil then
            if type(n) == "string" then return n end
            local okS, s = pcall(function() return Game.NameToString(n) end)
            if okS and type(s) == "string" and s ~= "" and s ~= "None" then return s end
            local okV, v = pcall(function() return n.value end)
            if okV and type(v) == "string" and v ~= "" then return v end
        end
    end
    return nil
end

local function readType(a)
    local tries = {
        function() return a:GetType(a).value end,
        function() return ListenerAction.GetType(a).value end,
        function() return a:GetType().value end,
    }
    for _, try in ipairs(tries) do
        local ok, t = pcall(try)
        if ok and type(t) == "string" then return t end
    end
    return ""
end

function api.observeActions(handler)
    Observe("PlayerPuppet", "OnAction", function(...)
        for i = 1, select("#", ...) do
            local a = select(i, ...)
            if type(a) == "userdata" or type(a) == "table" then
                local name = readName(a)
                if name then
                    handler(name, readType(a))
                    return
                end
            end
        end
    end)
end

-- hooks.action_poll (main input route): the action's current value, or nil when unavailable.
function api.pollAction(name)
    local si = api.scriptInterface
    if si == nil then return nil end
    local ok, v = pcall(function() return si:GetActionValue(name) end)
    if ok and type(v) == "number" then return v end
    return nil
end

-- hooks.player_position / player handle
function api.player()
    local p = Game.GetPlayer()
    if p == nil then return nil end
    return p
end

function api.playerPos(player)
    return fromV(player:GetWorldPosition())
end

-- hooks.player_orientation
function api.playerEuler(player)
    local ok, e = pcall(function() return player:GetWorldOrientation():ToEulerAngles() end)
    if ok and e then return e end
    return EulerAngles.new(0, 0, 0)
end

-- Turn a vector 90 degrees about Z: sign 1 maps (x, y, z) -> (y, -x, z), sign -1 the other way.
local function turn(v, sign)
    if sign == 1 then return { x = v.y, y = -v.x, z = v.z } end
    return { x = -v.y, y = v.x, z = v.z }
end

-- hooks.camera_transform -> { pos, fwd, right, up }
-- Melty saw the camera basis turned 90 degrees about Z on some game versions, so match it to the way V faces.
function api.camera(player)
    local ok, cam = pcall(function()
        local m = player:GetFPPCameraComponent():GetLocalToWorld()
        return {
            pos = fromV(m:GetTranslation()),
            fwd = vec.norm(fromV(m:GetAxisY())),
            right = vec.norm(fromV(m:GetAxisX())),
            up = vec.norm(fromV(m:GetAxisZ())),
        }
    end)
    if ok and cam then
        local okF, pf = pcall(function() return vec.flat(fromV(player:GetWorldForward())) end)
        local horizontal = math.sqrt(cam.fwd.x * cam.fwd.x + cam.fwd.y * cam.fwd.y)
        if okF and horizontal < 0.2 and api.basisTurn ~= 0 then
            -- looking nearly straight up/down: keep the last correction instead of re-deciding
            local b = api.basisTurn
            cam.fwd, cam.right, cam.up = turn(cam.fwd, b), turn(cam.right, b), turn(cam.up, b)
        elseif okF and horizontal >= 0.2 then
            local best, bestDot = 0, vec.dot(vec.flat(cam.fwd), pf)
            for _, sign in ipairs({ 1, -1 }) do
                local d = vec.dot(vec.flat(turn(cam.fwd, sign)), pf)
                if d > bestDot + 0.5 then best, bestDot = sign, d end
            end
            if api.basisTurn ~= best then
                api.basisTurn = best
                if best ~= 0 then print("[SpiderPunk2077] camera basis is turned; correcting (" .. best .. ")") end
            end
            if best ~= 0 then
                cam.fwd, cam.right, cam.up = turn(cam.fwd, best), turn(cam.right, best), turn(cam.up, best)
            end
        end
        return cam
    end
    local pos = api.playerPos(player)
    local fwd = vec.norm(fromV(player:GetWorldForward()))
    return { pos = vec.add(pos, vec.new(0, 0, 1.7)), fwd = fwd, right = vec.yaw(vec.flat(fwd), -90), up = vec.UP }
end

-- hooks.raycast (+ hooks.raycast_alt) -> { pos, normal } or nil
function api.raycast(from, to)
    local si = api.scriptInterface
    if si ~= nil then
        local ok, r = pcall(function() return si:RaycastWithASingleGroup(toV4(from), toV4(to), "PlayerBlocker") end)
        if ok and r ~= nil then
            if r:IsValid() then return { pos = fromV(r.position), normal = fromV(r.normal) } end
            return nil
        end
        warnOnce("raycast", "state-machine raycast failed, trying spatial queries")
        api.scriptInterface = nil
    end
    local ok, hit, r = pcall(function()
        return Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(toV4(from), toV4(to), "Static", false, false)
    end)
    if ok and hit and r ~= nil then
        return { pos = fromV(r.position), normal = fromV(r.normal) }
    end
    if not ok then warnOnce("raycast_alt", "no raycast available yet") end
    return nil
end

-- hooks.teleport
function api.teleport(player, pos, euler)
    Game.GetTeleportationFacility():Teleport(player, toV4(pos), euler)
end

-- hooks.game_paused
function api.isPaused()
    local ok, paused = pcall(function()
        return GetSingleton("inkMenuScenario"):GetSystemRequestsHandler():IsGamePaused()
    end)
    if ok then return paused == true end
    warnOnce("paused", "IsGamePaused unavailable, using IsPreGame")
    local ok2, pre = pcall(function()
        return GetSingleton("inkMenuScenario"):GetSystemRequestsHandler():IsPreGame()
    end)
    return ok2 and pre == true
end

-- hooks.mounted_vehicle
function api.inVehicle(player)
    local ok, v = pcall(function() return Game.GetMountedVehicle(player) end)
    return ok and v ~= nil
end

-- hooks.display_resolution
function api.resolution()
    return GetDisplayResolution()
end

-- hooks.project_point -> screen pixels or nil
function api.project(point)
    local ok, ndc = pcall(function() return Game.GetCameraSystem():ProjectPoint(toV4(point)) end)
    if not ok or ndc == nil then return nil end
    local w, h = api.resolution()
    return (ndc.x + 1) * w / 2, (1 - ndc.y) * h / 2
end

-- hooks.draw_line
function api.drawLine(x1, y1, x2, y2, rgba, thickness)
    local col = (math.floor(rgba[4]) * 16777216) + (math.floor(rgba[3]) * 65536) + (math.floor(rgba[2]) * 256) + math.floor(rgba[1])
    if col >= 2147483648 then col = col - 4294967296 end -- ImU32 as a signed int for the binding
    ImGui.ImDrawListAddLine(ImGui.GetBackgroundDrawList(), x1, y1, x2, y2, col, thickness)
end

return api
