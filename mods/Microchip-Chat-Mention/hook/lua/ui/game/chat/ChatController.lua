local Mention = import('/mods/Microchip-Chat-Mention/modules/mentions.lua')
local oldReceive, oldAppend = OnReceive, AppendEntry
local incoming

function OnReceive(sender, message)
    local previous = incoming
    incoming = {sender = sender, message = message}
    oldReceive(sender, message)
    incoming = previous
end

function AppendEntry(entry)
    oldAppend(entry)
    -- Observe only chat that survived FAF routing, duplicate and mute filters.
    -- Locally echoed outgoing/private messages and system lines cannot trigger.
    if incoming and entry and IsValidEntry(entry) then
        Mention.Receive(incoming.sender, incoming.message, entry)
    end
end
