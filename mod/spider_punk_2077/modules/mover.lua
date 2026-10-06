-- Traversal state machine. One mode per row of design/sheets/abilities.json:
--   idle (game in control) | swing (web_swing) | flight (momentum_carry) | glide (web_wings) | zip (web_zip)
-- soft_landing is the hand-back from any driven mode to idle.
-- Every number comes from the tuning sheet through T(id); every game call goes through api.
local vec = require("modules/vec")

local BODY = 1.0      -- metres from feet to the body centre used for sweeps and the rope
local HEAD = 1.6      -- metres from feet to where anchor searches start
local RADIUS = 0.45   -- clearance kept from walls during sweeps
local RETRY = 0.12    -- seconds between anchor searches while the swing button is held

local mover = {}
mover.__index = mover

function mover.new(api, T)
    return setmetatable({
        api = api, T = T,
        mode = "idle",
        pos = nil, vel = vec.new(), lastPos = nil,
        airTime = 0, retryIn = 0,
        swingHeld = false, aimHeld = false,
        anchor = nil, rope = 0, wingsCooldown = 0,
        zipTarget = nil, zipLandOnArrival = false,
        enabled = true,
        events = {},          -- recent state changes, for the overlay and the simulator
    }, mover)
end

function mover:log(what)
    self.events[#self.events + 1] = what
    if #self.events > 32 then table.remove(self.events, 1) end
end

-- inputs.swing_hold / swing_release / zip_press / wings_toggle / aim_state
function mover:onSwing(down)
    if down and self.aimHeld then
        self:onZip()
        return
    end
    self.swingHeld = down
    if down then self.retryIn = 0 end
    if not down and self.mode == "swing" then self:release() end
end

function mover:onAim(down) self.aimHeld = down end

function mover:onWings()
    -- ToggleCrouch and Crouch can both arrive for one key press: ignore the second.
    if self.wingsCooldown > 0 then return end
    self.wingsCooldown = 0.2
    if self.mode == "glide" then
        self:setMode("flight")
    elseif self.mode == "flight" or (self.mode == "idle" and self:airborne()) then
        self:takeControl()
        self:setMode("glide")
    end
end

function mover:onZip()
    if not self.enabled then return end
    local player = self.api.player()
    if not player then return end
    local cam = self.api.camera(player)
    local hit = self.api.raycast(cam.pos, vec.add(cam.pos, vec.scale(cam.fwd, self.T("zip_range"))))
    if not hit then return end
    self:takeControl()
    if hit.normal.z > 0.7 then
        self.zipTarget = vec.add(hit.pos, vec.new(0, 0, self.T("ground_clearance")))
        self.zipLandOnArrival = true
    else
        -- stop short of the wall, at feet height a little under the aimed point
        local off = vec.add(hit.pos, vec.scale(hit.normal, RADIUS + 0.2))
        self.zipTarget = vec.sub(off, vec.new(0, 0, BODY))
        self.zipLandOnArrival = false
    end
    self.anchor = hit.pos
    self:setMode("zip")
end

function mover:setMode(m)
    if self.mode ~= m then
        self:log(self.mode .. "->" .. m)
        self.mode = m
    end
    if m ~= "swing" and m ~= "zip" then self.anchor = nil end
end

-- Start driving the player from where the game has them, keeping their current momentum.
function mover:takeControl()
    if self.mode == "idle" then
        local player = self.api.player()
        if player then self.pos = self.api.playerPos(player) end
    end
end

function mover:groundBelow(pos, depth)
    local from = vec.add(pos, vec.new(0, 0, BODY))
    local hit = self.api.raycast(from, vec.sub(pos, vec.new(0, 0, depth)))
    if hit and hit.normal.z > 0.5 then return hit end
    return nil
end

function mover:airborne()
    return self.pos ~= nil and self:groundBelow(self.pos, self.T("ground_probe")) == nil
end

-- web_swing anchor search: a fan of rays up and ahead of the camera heading; best-scoring hit wins.
function mover:findAnchor(cam)
    local T = self.T
    local heading = vec.flat(cam.fwd)
    local origin = vec.add(self.pos, vec.new(0, 0, HEAD))
    local range = T("anchor_max_range")
    local pmin, pmax, spread = T("anchor_pitch_min"), T("anchor_pitch_max"), T("anchor_yaw_spread")
    local best, bestScore = nil, -math.huge
    for pi = 0, 4 do
        local pitch = pmin + (pmax - pmin) * pi / 4
        for yi = -2, 2 do
            local yaw = spread * yi / 2
            local flat = vec.yaw(heading, yaw)
            local dir = vec.add(vec.scale(flat, math.cos(math.rad(pitch))), vec.new(0, 0, math.sin(math.rad(pitch))))
            local hit = self.api.raycast(origin, vec.add(origin, vec.scale(dir, range)))
            if hit then
                local d = vec.dist(hit.pos, origin)
                local height = hit.pos.z - origin.z
                if height > 3 and d > 6 then
                    local ahead = vec.dot(flat, heading)
                    local score = ahead * 2 + math.min(height / 20, 1) + (1 - math.abs(d - 30) / 40) + vec.dot(vec.flat(vec.sub(hit.pos, origin)), heading)
                    if score > bestScore then best, bestScore = hit, score end
                end
            end
        end
    end
    return best
end

function mover:tryStartSwing()
    local player = self.api.player()
    if not player then return end
    local cam = self.api.camera(player)
    self:takeControl()
    local hit = self:findAnchor(cam)
    if not hit then
        self.retryIn = RETRY
        return
    end
    self.anchor = hit.pos
    self.rope = math.max(vec.dist(vec.add(self.pos, vec.new(0, 0, BODY)), self.anchor), self.T("rope_min_length"))
    self:setMode("swing")
end

-- Longest web that keeps the bottom of the arc swing_floor_clearance above the ground under the player.
function mover:ropeLimit()
    local T = self.T
    local ground = self.api.raycast(vec.add(self.pos, vec.new(0, 0, BODY)), vec.sub(self.pos, vec.new(0, 0, 300)))
    if not ground then return math.huge end
    return math.max(self.anchor.z - ground.pos.z - T("swing_floor_clearance") - BODY, T("rope_min_length"))
end

function mover:release()
    local v, speed = vec.norm(self.vel)
    if self.vel.z > 0 then
        self.vel = vec.scale(v, speed + self.T("release_boost"))
    end
    self:setMode("flight")
end

function mover:land(groundZ)
    self.pos = vec.new(self.pos.x, self.pos.y, groundZ + self.T("ground_clearance"))
    self.vel = vec.new()
    self.lastLanding = { pos = vec.copy(self.pos) }
    self:setMode("idle")
    self.landedThisFrame = true
end

-- Move from self.pos by delta with collision. Returns the new position, or nil if it landed.
function mover:sweep(delta)
    local from = vec.add(self.pos, vec.new(0, 0, BODY))
    local dir, dist = vec.norm(delta)
    if dist < 1e-6 then return self.pos end
    local hit = self.api.raycast(from, vec.add(from, vec.scale(dir, dist + RADIUS)))
    if not hit then return vec.add(self.pos, delta) end
    local n = hit.normal
    if n.z > 0.6 then
        self:land(hit.pos.z)
        return nil
    end
    -- wall or ceiling: stop at the surface, keep the sliding part of the velocity
    local travel = math.max(vec.dist(hit.pos, from) - RADIUS, 0)
    local stopped = vec.add(self.pos, vec.scale(dir, travel))
    local vn = vec.dot(self.vel, n)
    if vn < 0 then
        self.vel = vec.scale(vec.sub(self.vel, vec.scale(n, vn)), self.T("wall_slide_keep"))
    end
    return stopped
end

function mover:integrateCommon(dt)
    self.vel.z = self.vel.z - self.T("gravity") * dt
end

function mover:updateSwing(dt, cam)
    local T = self.T
    self:integrateCommon(dt)
    local steer = vec.scale(vec.flat(cam.fwd), T("swing_steer_accel") * dt)
    self.vel = vec.clampLen(vec.add(self.vel, steer), T("max_speed"))
    local limit = self:ropeLimit()
    if self.rope > limit then
        self.rope = math.max(self.rope - T("rope_fast_reel") * dt, limit)
    else
        self.rope = math.max(self.rope - T("rope_reel_speed") * dt, T("rope_min_length"))
    end

    local body = vec.add(vec.add(self.pos, vec.new(0, 0, BODY)), vec.scale(self.vel, dt))
    local d = vec.sub(body, self.anchor)
    local n, l = vec.norm(d)
    if l > self.rope then
        body = vec.add(self.anchor, vec.scale(n, self.rope))
        local vr = vec.dot(self.vel, n)
        if vr > 0 then self.vel = vec.sub(self.vel, vec.scale(n, vr)) end
    end
    local target = vec.sub(body, vec.new(0, 0, BODY))
    local moved = self:sweep(vec.sub(target, self.pos))
    if not moved then return end
    self.pos = moved
    -- Past the top of the arc: let go, like Spider-Man 2's automatic release.
    if self.pos.z + BODY > self.anchor.z - 1 then self:release() end
end

function mover:updateFlight(dt)
    local T = self.T
    self:integrateCommon(dt)
    self.vel = vec.clampLen(vec.scale(self.vel, math.max(1 - T("air_drag") * dt, 0)), T("max_speed"))
    local moved = self:sweep(vec.scale(self.vel, dt))
    if moved then self.pos = moved end
end

function mover:updateGlide(dt, cam)
    local T = self.T
    local want = vec.scale(vec.flat(cam.fwd), T("glide_speed"))
    local k = math.min(T("glide_turn_rate") * dt, 1)
    local vx = self.vel.x + (want.x - self.vel.x) * k
    local vy = self.vel.y + (want.y - self.vel.y) * k
    local vz = math.max(self.vel.z - T("gravity") * dt, -T("glide_sink"))
    self.vel = vec.new(vx, vy, vz)
    local moved = self:sweep(vec.scale(self.vel, dt))
    if moved then self.pos = moved end
end

function mover:updateZip(dt)
    local T = self.T
    local to = vec.sub(self.zipTarget, self.pos)
    local dir, dist = vec.norm(to)
    local step = T("zip_speed") * dt
    self.vel = vec.scale(dir, T("zip_speed"))
    if dist <= step then
        self.pos = self.zipTarget
        if self.zipLandOnArrival then
            self:land(self.zipTarget.z - T("ground_clearance"))
        else
            self.vel = vec.add(vec.scale(vec.flat(dir), math.min(T("zip_speed") * 0.25, 10)), vec.new(0, 0, T("zip_pop")))
            self:setMode("flight")
        end
        return
    end
    local moved = self:sweep(vec.scale(dir, step))
    if not moved then return end
    if vec.dist(moved, self.pos) < step * 0.5 then
        self.pos = moved
        self:setMode("flight") -- blocked: fall back to ballistic flight
        return
    end
    self.pos = moved
end

function mover:update(dt)
    self.landedThisFrame = false
    if not self.enabled or dt <= 0 then return end
    dt = math.min(dt, 0.05)
    self.wingsCooldown = math.max(self.wingsCooldown - dt, 0)
    local api = self.api
    local player = api.player()
    if not player or api.isPaused() then return end
    if api.inVehicle(player) then
        if self.mode ~= "idle" then self:setMode("idle") end
        return
    end

    if self.mode == "idle" then
        local pos = api.playerPos(player)
        if self.lastPos then
            local v = vec.scale(vec.sub(pos, self.lastPos), 1 / dt)
            self.vel = vec.add(vec.scale(self.vel, 0.5), vec.scale(v, 0.5))
        end
        self.lastPos, self.pos = pos, pos
        if self:airborne() then self.airTime = self.airTime + dt else self.airTime = 0 end
        self.retryIn = self.retryIn - dt
        if self.swingHeld and not self.aimHeld and self.airTime >= self.T("swing_arm_delay") and self.retryIn <= 0 then
            self:tryStartSwing()
        end
        if self.mode == "idle" then return end
    end

    local cam = api.camera(player)
    if (self.mode == "flight" or self.mode == "glide") and self.swingHeld then
        self.retryIn = self.retryIn - dt
        if self.retryIn <= 0 then self:tryStartSwing() end
    end

    if self.mode == "swing" then self:updateSwing(dt, cam)
    elseif self.mode == "flight" then self:updateFlight(dt)
    elseif self.mode == "glide" then self:updateGlide(dt, cam)
    elseif self.mode == "zip" then self:updateZip(dt) end

    -- soft_landing: near the ground while falling -> put the feet on it and hand back to the game.
    if self.mode ~= "idle" and self.mode ~= "zip" and self.vel.z <= 0 then
        local g = self:groundBelow(self.pos, self.T("ground_probe"))
        if g then self:land(g.pos.z) end
    end

    api.teleport(player, self.pos, api.playerEuler(player))
    self.lastPos = self.pos
    if self.mode == "idle" then self.airTime = 0 end
end

return mover
