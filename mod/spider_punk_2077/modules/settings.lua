-- Player settings: the tuning sheet's exposed rows plus on/off switches, saved to settings.json
-- in the mod folder (hooks.settings_io). Missing or broken files fall back to the sheet defaults.
local settings = { values = {}, enabled = true, logActions = false }

local FILE = "settings.json"

function settings.init(sheets)
    settings.sheets = sheets
    settings.reset()
    settings.load()
end

function settings.reset()
    settings.values = {}
    for id, row in pairs(settings.sheets.tuning) do settings.values[id] = row.value end
end

-- T(id): the current value of a tuning row, clamped to the sheet's range.
function settings.T(id)
    local row = settings.sheets.tuning[id]
    if row == nil then error("unknown tuning row " .. tostring(id)) end
    local v = settings.values[id]
    if type(v) ~= "number" then v = row.value end
    return math.max(row.min, math.min(row.max, v))
end

function settings.load()
    local ok, data = pcall(function()
        local f = io.open(FILE, "r")
        if not f then return nil end
        local text = f:read("*a")
        f:close()
        return json.decode(text)
    end)
    if not ok or type(data) ~= "table" then return end
    if type(data.enabled) == "boolean" then settings.enabled = data.enabled end
    if type(data.tuning) == "table" then
        for id, v in pairs(data.tuning) do
            local row = settings.sheets.tuning[id]
            if row and row.exposed and type(v) == "number" then settings.values[id] = v end
        end
    end
end

function settings.save()
    local tuning = {}
    for id, row in pairs(settings.sheets.tuning) do
        if row.exposed then tuning[id] = settings.values[id] end
    end
    pcall(function()
        local f = io.open(FILE, "w")
        if not f then return end
        f:write(json.encode({ enabled = settings.enabled, tuning = tuning }))
        f:close()
    end)
end

return settings
