-- Append-only UI hook. Original F11 layout, update loop and close controls remain intact.
local LagLinks = import('/mods/Microchip-F11-Lag-Links/modules/analysis.lua')
local lagTracker = LagLinks.New()
local originalGetClients = GetSessionClients
local originalClose = CloseWindow

-- This override belongs only to the connectivity module: simulation, scoreboards
-- and the disconnect/ejection dialog continue to read the original player names.
function GetSessionClients()
    local clients = originalGetClients()
    if type(clients) ~= 'table' then return clients end
    local labels = lagTracker:Update(clients, GetSystemTimeSeconds())
    local display = {}
    for id, client in pairs(clients) do
        local copy = {}
        for key, value in pairs(client) do copy[key] = value end
        copy.name = tostring(client.name or '') .. (labels[id] or '')
        display[id] = copy
    end
    return display
end

function CloseWindow()
    lagTracker = LagLinks.New()
    return originalClose()
end
