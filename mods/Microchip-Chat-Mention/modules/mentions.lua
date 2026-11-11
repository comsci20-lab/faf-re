local Prefs = import('/lua/user/prefs.lua')
local Matching = import('/mods/Microchip-Chat-Mention/modules/matching.lua')
local settings
local recent = {}

function Settings()
    if not settings then settings = Matching.Normalize(Prefs.GetFromCurrentProfile('microchip_chat_mention')) end
    return settings
end

function Save(value)
    settings = Matching.Normalize(value)
    Prefs.SetToCurrentProfile('microchip_chat_mention', settings)
    if not settings.enabled then import('/mods/Microchip-Chat-Mention/modules/popup.lua').Clear() end
end

function PlayerName()
    for _, client in pairs(GetSessionClients() or {}) do
        if client['local'] and type(client.name) == 'string' then return client.name end
    end
    -- Never use the focus army: an observer may be watching another player.
    return ''
end

function Receive(sender, message, entry)
    local config = Settings()
    if not config.enabled or type(sender) ~= 'string' or type(message) ~= 'table' then return end
    if type(message.text) ~= 'string' or message.to == 'notify' then return end
    if entry.Camera or entry.Location or (entry.Type and entry.Type ~= 'Chat') then return end
    local player = PlayerName()
    if string.lower(sender) == string.lower(player) then return end
    local matched = Matching.Match(message.text, player, config.nicknames)
    if not matched then return end
    local now = GetSystemTimeSeconds()
    for key, seen in pairs(recent) do if now - seen > 2 then recent[key] = nil end end
    local key = sender .. '\0' .. tostring(message.Id or message.text) .. '\0' .. tostring(message.to)
    if recent[key] then return end
    recent[key] = now
    import('/mods/Microchip-Chat-Mention/modules/popup.lua').Push({
        sender = sender, text = message.text, matched = matched,
        channel = message.to == 'allies' and 'ALLIES' or (type(message.to) == 'number' and 'PRIVATE' or 'ALL'),
        seconds = config.seconds,
    })
end
