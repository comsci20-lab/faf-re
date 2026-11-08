-- Classic engines can keep this UI mod enabled; the offline bridge is x64-only.
if rawget(_G, 'MicrochipQueueTranslation') then
local Translator = import('/fafengine/lua/ui/translation.lua')
Translator.Reset()
local originalAppendEntry = AppendEntry

function AppendEntry(entry)
    originalAppendEntry(entry)
    -- Only translate visible, already-filtered player chat. Never camera links or system lines.
    if not entry.ArmyID or entry.ArmyID == 0 or entry.Camera or entry.Location then return end
    local original = table.copy(entry)
    Translator.Translate(entry.Text, function(english)
        local translated = table.copy(original)
        translated.Text = english
        translated.Id = nil
        originalAppendEntry(translated)
    end)
end
end
