-- Offline oracle for Spider-Punk 2077.
-- Mocks the exact CET / game calls listed in design/sheets/hooks.json, runs the real mod files
-- (init.lua and modules/*), and drives scripted scenarios through a box city.
-- Passing here means the mod's logic works; it says nothing about the real game until tested there.
local H = {}

---------------------------------------------------------------- world
local boxes = {}
local function box(x1, y1, z1, x2, y2, z2) boxes[#boxes + 1] = { x1, y1, z1, x2, y2, z2 } end

function H.buildCity()
    boxes = {}
    box(-400, -400, -2, 400, 600, 0)          -- street level, top at z = 0
    box(-6, -40, 0, 6, 0, 40)                 -- start roof (40 m), facing +Y
    for i = 0, 7 do                           -- towers both sides of a 24 m wide avenue
        local y = 10 + i * 40
        local h = 70 + (i % 3) * 20             -- Night City megabuildings: 70-110 m
        box(-40, y, 0, -12, y + 30, h)
        box(12, y, 0, 40, y + 30, h)
    end
    box(-15, 350, 0, 15, 380, 30)             -- end building for zip tests
end

local function rayBox(o, d, b)
    local tmin, tmax, nAxis, nSign = -math.huge, math.huge, nil, 0
    local oo, dd = { o.x, o.y, o.z }, { d.x, d.y, d.z }
    for a = 1, 3 do
        local lo, hi = b[a], b[a + 3]
        if math.abs(dd[a]) < 1e-9 then
            if oo[a] < lo or oo[a] > hi then return nil end
        else
            local t1, t2 = (lo - oo[a]) / dd[a], (hi - oo[a]) / dd[a]
            local s = -1
            if t1 > t2 then t1, t2 = t2, t1; s = 1 end
            if t1 > tmin then tmin, nAxis, nSign = t1, a, s end
            if t2 < tmax then tmax = t2 end
            if tmin > tmax then return nil end
        end
    end
    if tmin < 0 or nAxis == nil then return nil end -- origin inside, or behind
    local n = { 0, 0, 0 }
    n[nAxis] = nSign
    return tmin, { x = n[1], y = n[2], z = n[3] }
end

function H.raycast(from, to)
    local d = { x = to.x - from.x, y = to.y - from.y, z = to.z - from.z }
    local best, bn
    for _, b in ipairs(boxes) do
        local t, n = rayBox(from, d, b)
        if t and t <= 1 and (not best or t < best) then best, bn = t, n end
    end
    if not best then return nil end
    H.stats.rays = H.stats.rays + 1
    return { x = from.x + d.x * best, y = from.y + d.y * best, z = from.z + d.z * best }, bn
end

function H.insideAny(p)
    for _, b in ipairs(boxes) do
        if p.x > b[1] + 0.01 and p.x < b[4] - 0.01 and p.y > b[2] + 0.01 and p.y < b[5] - 0.01 and p.z > b[3] + 0.01 and p.z < b[6] - 0.01 then
            return true
        end
    end
    return false
end

---------------------------------------------------------------- CET / game mocks
local events, observers, inputs = {}, {}, {}
local P -- the simulated player

local function V(x, y, z) return { x = x, y = y, z = z } end
Vector4 = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w or 0 } end }
EulerAngles = { new = function(r, p, y) return { roll = r, pitch = p, yaw = y } end }

function registerForEvent(name, fn) events[name] = fn end
function registerInput(id, label, fn) inputs[id] = fn end
function Observe(cls, method, fn) observers[cls .. "." .. method] = fn end
function GetDisplayResolution() return 1920, 1080 end
function GetSingleton(name)
    return { GetSystemRequestsHandler = function() return {
        IsGamePaused = function() return H.paused end,
        IsPreGame = function() return false end,
    } end }
end

json = {
    encode = function() return "{}" end,
    decode = function() return {} end,
}
local realOpen = io.open
io = setmetatable({ open = function(path, mode)
    if path == "settings.json" then return nil end -- sim never touches the real mod folder
    return realOpen(path, mode)
end }, { __index = io })

local function camBasis()
    local cy, sy = math.cos(math.rad(P.yaw)), math.sin(math.rad(P.yaw))
    local cp, sp = math.cos(math.rad(P.pitch)), math.sin(math.rad(P.pitch))
    local fwd = V(-sy * cp, cy * cp, sp)     -- yaw 0 looks along +Y
    local right = V(cy, sy, 0)
    local up = V(sy * sp, -cy * sp, cp) -- right x forward
    return fwd, right, up
end

local playerObj = {
    GetWorldPosition = function() return Vector4.new(P.pos.x, P.pos.y, P.pos.z, 1) end,
    GetWorldForward = function() local f = camBasis(); return V(f.x, f.y, 0) end,
    GetWorldOrientation = function() return { ToEulerAngles = function() return EulerAngles.new(0, 0, P.yaw) end } end,
    GetFPPCameraComponent = function() return {
        GetLocalToWorld = function()
            local f, r, u = camBasis()
            if H.cameraTurn then -- reproduce the turned basis Melty reported: inverse of the fix
                local function t(v) if H.cameraTurn == 1 then return V(-v.y, v.x, v.z) end return V(v.y, -v.x, v.z) end
                f, r, u = t(f), t(r), t(u)
            end
            return {
            GetTranslation = function() return V(P.pos.x, P.pos.y, P.pos.z + 1.7) end,
            GetAxisY = function() return f end,
            GetAxisX = function() return r end,
            GetAxisZ = function() return u end,
        } end,
        GetFOV = function() return 68 end,
    } end,
}
-- CET passes methods with ':' so the first arg is the object itself; mocks ignore it.
for k, f in pairs(playerObj) do playerObj[k] = function(_, ...) return f(...) end end

Game = {
    GetPlayer = function() return playerObj end,
    NameToString = function(n) return n end,
    GetMountedVehicle = function() return nil end,
    GetTeleportationFacility = function() return { Teleport = function(_, who, pos, rot)
        P.pos = V(pos.x, pos.y, pos.z)
        P.vel = V(0, 0, 0) -- worst case: a teleport kills the game's own velocity
        P.teleported = true
        H.stats.teleports = H.stats.teleports + 1
    end } end,
    GetCameraSystem = function() return { ProjectPoint = function(_, p)
        local f, r, u = camBasis()
        local c = V(P.pos.x, P.pos.y, P.pos.z + 1.7)
        local d = V(p.x - c.x, p.y - c.y, p.z - c.z)
        local z = d.x * f.x + d.y * f.y + d.z * f.z
        local t = math.tan(math.rad(34))
        return V((d.x * r.x + d.y * r.y + d.z * r.z) / (z * t * 16 / 9), (d.x * u.x + d.y * u.y + d.z * u.z) / (z * t), 0)
    end } end,
    GetSpatialQueriesSystem = function() error("not used when the state-machine interface exists") end,
}

local scriptInterface = {
    GetActionValue = function(_, name)
        if H.noPolling then error("GetActionValue unavailable (route test)") end
        return H.buttons[name] and 1.0 or 0.0
    end,
    RaycastWithASingleGroup = function(_, from, to, group)
        assert(group == "PlayerBlocker")
        local p, n = H.raycast(from, to)
        return {
            IsValid = function() return p ~= nil end,
            position = p or V(0, 0, 0),
            normal = n or V(0, 0, 0),
        }
    end,
}

ImGui = {
    GetBackgroundDrawList = function() return {} end,
    ImDrawListAddLine = function(_, x1, y1, x2, y2, col, th) H.stats.webLines = H.stats.webLines + 1 end,
    Begin = function() return true end, End = function() end,
    Checkbox = function(_, v) return v, false end,
    SliderFloat = function(_, v) return v, false end,
    Button = function() return false end, Text = function() end, Separator = function() end,
}

local function fakeAction(name, kind)
    if H.noActionNames then
        -- what Melty reports for CET 1.37.1: the callback fires, the name can't be read
        return { GetName = function() error("name unreadable") end, GetType = function() return { value = kind } end }
    end
    return { GetName = function() return name end, GetType = function() return { value = kind } end }
end

---------------------------------------------------------------- game physics for the un-driven player
local GAME_G = 16
local function grounded()
    local p = H.raycast(V(P.pos.x, P.pos.y, P.pos.z + 0.3), V(P.pos.x, P.pos.y, P.pos.z - 0.05))
    return p ~= nil, p
end

local function gameStep(dt)
    if P.teleported then P.teleported = false; return end
    local onGround, gp = grounded()
    if onGround and P.vel.z <= 0 then
        if P.airborne then
            if -P.vel.z > H.FALL_DAMAGE_SPEED then H.stats.fallDamage = H.stats.fallDamage + 1 end
            H.stats.lastGameLandingSpeed = -P.vel.z
            P.airborne = false
        end
        P.pos.z = gp.z
        P.vel = V(0, 0, 0)
        if P.running then
            local f = camBasis()
            local fl = math.sqrt(f.x * f.x + f.y * f.y)
            P.vel = V(f.x / fl * 7, f.y / fl * 7, 0)
        end
        if P.jumpQueued then P.vel.z = 5.5; P.airborne = true end
    else
        P.airborne = true
        P.vel.z = P.vel.z - GAME_G * dt
    end
    P.jumpQueued = false
    local np = V(P.pos.x + P.vel.x * dt, P.pos.y + P.vel.y * dt, P.pos.z + P.vel.z * dt)
    -- the game's own collision: stop at whatever the move would cross
    local hit = H.raycast(V(P.pos.x, P.pos.y, P.pos.z + 0.3), V(np.x, np.y, np.z + 0.3))
    if hit then np = V(P.pos.x, P.pos.y, P.pos.z); P.vel.x, P.vel.y = 0, 0 end
    -- step down off ledges / land on surfaces below
    if np.z < P.pos.z then
        local g = H.raycast(V(np.x, np.y, P.pos.z + 0.3), V(np.x, np.y, np.z))
        if g then np.z = g.z end
    end
    P.pos = np
end

---------------------------------------------------------------- scenario runner
function H.load(modDir)
    H.FALL_DAMAGE_SPEED = 12
    H.stats = { rays = 0, teleports = 0, webLines = 0, fallDamage = 0 }
    events, observers, inputs = {}, {}, {}
    package.path = modDir .. "/?.lua;" .. package.path
    for k in pairs(package.loaded) do
        if k:match("^modules/") or k:match("^generated/") then package.loaded[k] = nil end
    end
    -- Strict mode: the mod may not create globals or read undefined ones (catches typos the sim would miss).
    setmetatable(_G, {
        __newindex = function(_, k) error("mod wrote global '" .. tostring(k) .. "'", 2) end,
        __index = function(_, k) error("mod read undefined global '" .. tostring(k) .. "'", 2) end,
    })
    H.mod = dofile(modDir .. "/init.lua")
end

function H.getMover() return H.mod.mover end

-- script: list of { t = seconds, action = name, kind = type } or { t, run = bool } or { t, look = {yaw, pitch} }
function H.run(start, script, duration, onFrame)
    H.buildCity()
    H.stats = { rays = 0, teleports = 0, webLines = 0, fallDamage = 0, maxSpeed = 0, insideBuilding = 0, modes = {} }
    P = { pos = V(start.pos.x, start.pos.y, start.pos.z), vel = V(0, 0, 0), yaw = start.yaw or 0, pitch = start.pitch or 0,
          running = false, airborne = false, teleported = false }
    H.player = P
    H.prevMode = nil
    events.onInit()
    -- exercise the settings window once (CET overlay open -> draw -> close)
    events.onOverlayOpen(); events.onDraw(); events.onOverlayClose()
    local onAction = observers["PlayerPuppet.OnAction"]
    H.buttons = {}
    H.fire = function(name, kind)
        H.buttons[name] = (kind == "BUTTON_PRESSED")
        onAction({}, fakeAction(name, kind), {})
    end
    -- count how many presses reach the mover, to catch double handling when both routes work
    H.swingPresses = 0
    local m0 = H.getMover()
    local cls = getmetatable(m0).__index
    rawset(m0, "onSwing", function(self, down)
        if down then H.swingPresses = H.swingPresses + 1 end
        return cls.onSwing(self, down)
    end)
    local onLoco = observers["LocomotionEventsTransition.OnUpdate"]
    local dt, t, si = 1 / 60, 0, 1
    local mod = H.getMover()
    local track = { }
    while t < duration do
        while script[si] and script[si].t <= t do
            local s = script[si]
            if s.action then
                if s.action == "Jump" and s.kind == "BUTTON_PRESSED" then P.jumpQueued = true end
                H.fire(s.action, s.kind)
            end
            if s.run ~= nil then P.running = s.run end
            if s.look then P.yaw, P.pitch = s.look[1], s.look[2] end
            si = si + 1
        end
        onLoco({}, dt, {}, scriptInterface)
        local before = V(P.pos.x, P.pos.y, P.pos.z)
        events.onUpdate(dt)
        gameStep(dt)
        events.onDraw()
        local mode = H.getMover().mode
        local sp = math.sqrt((P.pos.x - before.x) ^ 2 + (P.pos.y - before.y) ^ 2 + (P.pos.z - before.z) ^ 2) / dt
        if sp > H.stats.maxSpeed then H.stats.maxSpeed = sp end
        if mode ~= "idle" and mode == (H.prevMode or "idle") and sp > (H.stats.maxDrivenSpeed or 0) then H.stats.maxDrivenSpeed = sp end
        H.prevMode = mode
        if H.insideAny(V(P.pos.x, P.pos.y, P.pos.z + 1.0)) then H.stats.insideBuilding = H.stats.insideBuilding + 1 end
        local m = H.getMover()
        H.stats.modes[m.mode] = (H.stats.modes[m.mode] or 0) + 1
        if onFrame then onFrame(t, P, m, H.stats) end
        t = t + dt
    end
    H.stats.final = V(P.pos.x, P.pos.y, P.pos.z)
    H.stats.events = H.getMover().events
    return H.stats
end

return H
