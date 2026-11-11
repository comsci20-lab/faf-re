local UI = import('/lua/ui/uiutil.lua')
local L = import('/lua/maui/layouthelpers.lua')
local Group = import('/lua/maui/group.lua').Group
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local Edit = import('/lua/maui/edit.lua').Edit
local Popup = import('/lua/ui/controls/popups/popup.lua').Popup
local Mention = import('/mods/Microchip-Chat-Mention/modules/mentions.lua')
local window

function Open(parent)
    if window and not IsDestroyed(window) then return window end
    parent = parent or GetFrame(0)
    local panel = Group(parent)
    panel.Width:Set(L.ScaleNumber(620)); panel.Height:Set(L.ScaleNumber(355))
    local bg = Bitmap(panel); bg:SetSolidColor('ff0c1520')
    L.FillParent(bg, panel); bg:DisableHitTest()
    local popup = Popup(parent, panel)
    window = popup
    local oldClosed = popup.OnClosed
    popup.OnClosed = function(self) window = nil; oldClosed(self) end
    local function Text(value, size, x, y, color)
        local t = UI.CreateText(panel, value, size, UI.bodyFont)
        t:SetColor(color or 'ffeaf2fa'); L.AtLeftTopIn(t, panel, x, y); t:DisableHitTest()
        return t
    end
    local function Input(value, x, y, width, limit)
        local e = Edit(panel)
        e.Width:Set(L.ScaleNumber(width)); e.Height:Set(L.ScaleNumber(28))
        L.AtLeftTopIn(e, panel, x, y)
        UI.SetupEditStd(e, 'ffeaf2fa', 'ff182635', 'ff000000', 'ff59e0cf', UI.bodyFont, 16, limit)
        e:SetText(value)
        return e
    end
    local function Button(value, x, y, click)
        local b = UI.CreateButtonWithDropshadow(panel, '/BUTTON/medium/', value)
        L.AtLeftTopIn(b, panel, x, y); b.OnClick = click
        return b
    end
    local config = Mention.Settings()
    local enabled = config.enabled
    Text('Microchip Chat Mention', 24, 22, 15, 'ff59e0cf')
    Text('Player name is detected automatically. Nicknames are additional matches.', 13, 22, 53)
    Text('Your player name: ' .. (Mention.PlayerName() ~= '' and Mention.PlayerName() or '(available in game)'), 14, 22, 83)
    Text('Nicknames (separate with commas)', 15, 22, 120)
    local names = Input(config.nicknames, 22, 147, 566, 256)
    Text('Display time in seconds (1-120)', 15, 22, 192)
    local seconds = Input(tostring(config.seconds), 395, 187, 85, 3)
    local toggle
    toggle = Button(enabled and 'Enabled: On' or 'Enabled: Off', 10, 230, function()
        enabled = not enabled
        toggle.label:SetText(enabled and 'Enabled: On' or 'Enabled: Off')
    end)
    local status = Text('Case insensitive; whole names only. Default: 10 seconds.', 12, 22, 278, 'ff9fb1c2')
    local function Draft()
        local value = tonumber(seconds:GetText())
        if not value or value ~= math.floor(value) or value < 1 or value > 120 then
            status:SetText('Enter a whole number of seconds from 1 to 120.'); return nil
        end
        return {enabled = enabled, seconds = value, nicknames = names:GetText()}
    end
    Button('Test Popup', 204, 230, function()
        local draft = Draft()
        if draft then import('/mods/Microchip-Chat-Mention/modules/popup.lua').Push({
            sender = 'Teammate', channel = 'ALLIES', seconds = draft.seconds,
            text = (Mention.PlayerName() ~= '' and Mention.PlayerName() or 'Microchip') .. ', can you cover the north side?',
        }) end
    end)
    Button('Save', 204, 303, function()
        local draft = Draft()
        if draft then Mention.Save(draft); popup:Close() end
    end)
    Button('Close', 398, 303, function() popup:Close() end)
    return popup
end
