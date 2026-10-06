-- Plain-table 3D vectors {x, y, z}. Cyberpunk is Z-up.
local vec = {}

function vec.new(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function vec.copy(a) return { x = a.x, y = a.y, z = a.z } end
function vec.add(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
function vec.sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
function vec.scale(a, s) return { x = a.x * s, y = a.y * s, z = a.z * s } end
function vec.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function vec.len(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vec.dist(a, b) return vec.len(vec.sub(a, b)) end

function vec.norm(a)
    local l = vec.len(a)
    if l < 1e-6 then return { x = 0, y = 0, z = 0 }, 0 end
    return { x = a.x / l, y = a.y / l, z = a.z / l }, l
end

-- Horizontal part of a direction, normalised (falls back to +Y when it points straight up/down).
function vec.flat(a)
    local f = vec.norm({ x = a.x, y = a.y, z = 0 })
    if f.x == 0 and f.y == 0 then return { x = 0, y = 1, z = 0 } end
    return f
end

function vec.clampLen(a, maxLen)
    local l = vec.len(a)
    if l > maxLen and l > 0 then return vec.scale(a, maxLen / l) end
    return a
end

-- Rotate around the world Z axis by deg degrees (counter-clockwise seen from above).
function vec.yaw(a, deg)
    local r = math.rad(deg)
    local c, s = math.cos(r), math.sin(r)
    return { x = a.x * c - a.y * s, y = a.x * s + a.y * c, z = a.z }
end

vec.UP = { x = 0, y = 0, z = 1 }

return vec
