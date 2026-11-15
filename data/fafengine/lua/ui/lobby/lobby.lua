-- Expose the existing native UI scale in lobby Settings (#6). LayoutHelpers
-- scales control geometry and font point sizes, preserving native-resolution
-- text rendering instead of stretching a rendered menu. Keep FAF's supported
-- scales: some in-game artwork is selected by these exact values.
local rebuildingLobbyForScale = false
do
    local OriginalShowLobbyOptionsDialog = ShowLobbyOptionsDialog

    local function ApplyLobbyScale(scale)
        local chatHistory = GUI.chatDisplay.ChatHistory
        local draft = GUI.chatEdit:GetText()
        local chatTop = GUI.chatPanel.top
        local atBottom = GUI.chatPanel:IsScrolledToBottom()
        local slots = {}
        for index, slot in ipairs(GUI.slots) do
            slots[index] = {
                factions = slot.AvailableFactions,
                icons = slot.faction._array,
                hidden = slot:IsHidden(),
            }
        end

        -- Keep the lobby root, network callbacks and keepalive thread. Recreate
        -- the controls whose fonts and dimensions are fixed at construction.
        rebuildingLobbyForScale = true
        KillThread(GUI.pingThread)
        GUI.uiCreated = false
        GUI:ClearChildren()
        GUI.background = nil
        GUI.briefing = nil
        GUI.lobbyOptionsDialog = nil
        LrgMap = false
        GUI.optionControls = {}
        GUI.slots = {}
        EscapeHandler.PopEscapeHandler()
        LayoutHelpers.SetPixelScaleFactor(scale)
        CreateUI(LobbyComm.maxPlayerSlots)
        rebuildingLobbyForScale = false
        -- Keep map-specific faction indices and visibility so UpdateGame does
        -- not treat the new controls as a change to the map or player slots.
        for index, state in ipairs(slots) do
            local slot = GUI.slots[index]
            if state.icons then slot.faction:ChangeBitmapArray(state.icons) end
            slot.AvailableFactions = state.factions
            slot:SetHidden(state.hidden)
        end
        UpdateGame()

        GUI.chatDisplay.ChatHistory = chatHistory
        GUI.chatDisplay:ReflowLines()
        if atBottom then
            GUI.chatPanel:ScrollToBottom()
        else
            GUI.chatPanel:ScrollSetTop(nil, chatTop)
        end
        GUI.chatEdit:SetText(draft)
        ShowLobbyOptionsDialog()
    end

    function ShowLobbyOptionsDialog()
        OriginalShowLobbyOptionsDialog()
        local dialog = GUI.lobbyOptionsDialog
        local content = dialog.content
        local Layout = import('/lua/maui/layouthelpers.lua')
        local Preferences = import('/lua/user/prefs.lua')
        local frame = GUI:GetRootFrame()
        local fit = math.min(frame.Width() / GUI.panel.BitmapWidth(),
            frame.Height() / GUI.panel.BitmapHeight())
        local scales = {0.8, 1, 1.25, 1.5, 1.75, 2}
        local count = 1
        for index, scale in ipairs(scales) do
            if scale <= fit then count = index end
        end

        -- Popup copies its content size at construction; resize both so its
        -- border, centering and bottom-anchored Close button remain correct.
        Layout.SetHeight(content, 370)
        dialog.Height:Set(content.Height())
        local current = Layout.GetPixelScaleFactor()
        local selected = 1
        for index = 1, count do
            if math.abs(scales[index] - current) < math.abs(scales[selected] - current) then
                selected = index
            end
        end
        local label = UIUtil.CreateText(content,
            string.format('Lobby / menu scale: %d%%', math.floor(current * 100 + 0.5)), 14, 'Arial', true)
        Layout.AtLeftTopIn(label, content, 20, 250)
        local slider = Slider(content, false, 1, math.max(2, count),
            UIUtil.SkinnableFile('/slider02/slider_btn_up.dds'),
            UIUtil.SkinnableFile('/slider02/slider_btn_over.dds'),
            UIUtil.SkinnableFile('/slider02/slider_btn_down.dds'),
            UIUtil.SkinnableFile('/slider02/slider-back_bmp.dds'))
        Layout.AtLeftTopIn(slider, content, 20, 275)
        slider:SetValue(selected)
        local function GetScale(value)
            local index = math.max(1, math.min(count, math.floor(value + 0.5)))
            return scales[index]
        end
        slider.OnValueChanged = function(self, value)
            local scale = GetScale(value)
            label:SetText(string.format('Lobby / menu scale: %d%%', math.floor(scale * 100 + 0.5)))
        end
        slider.OnValueSet = function(self, value)
            local scale = GetScale(value)
            -- Wait for the native dragger to finish before destroying its slider.
            ForkThread(function()
                WaitFrames(1)
                if GUI and GUI.lobbyOptionsDialog == dialog and not IsDestroyed(dialog) and not dialog:IsHidden()
                    and scale ~= Layout.GetPixelScaleFactor() then
                    ApplyLobbyScale(scale)
                    Preferences.SetOption('ui_scale', scale)
                end
            end)
        end
        local hint = UIUtil.CreateText(content, 'Release the slider to apply the new scale.', 12, 'Arial', true)
        Layout.AtLeftTopIn(hint, content, 20, 305)
        Tooltip.AddControlTooltipManual(label, 'Lobby / menu scale',
            'Scales menus, dialogs, text and the in-game UI. Only sizes that fit this lobby window are offered. '
            .. 'Text is rendered at the larger font size; bitmap detail depends on the original artwork.')
    end
end

-- faf-re hook of FAF's lua/ui/lobby/lobby.lua (plan WP17.6): in a lobby a tournament organiser runs on a game server,
-- the screen shows what the organiser set and changes nothing. A player chats, readies up and leaves; nobody kicks,
-- moves, starts the game or changes an option, faction, colour or team. The server drops such requests anyway
-- (src/server/LobbyRelay.cpp); this keeps every screen showing the same lobby. The engine sets the global
-- ServerLobbyControl to 'organiser' before the lobby's Lua runs (src/moho/app/ServerLobbyUi.cpp); elsewhere it is nil,
-- and this hook does nothing. The engine appends this file to FAF's (SCR_LuaDoFileConcat), so FAF's file-level locals
-- GUI and UpdateGame are in scope here. FAF's Lua errors on reading an undefined global: if a later lobby.lua renames
-- either, the pcalls below leave a warning in the log instead of a broken lobby.
do
    local saidLocked = false
    local function LockLobbyScreen()
        if rawget(_G, 'ServerLobbyControl') ~= 'organiser' or not GUI then
            return
        end
        local disabled = 0
        local function Off(control)
            if control and control.Disable then
                control:Disable()
                disabled = disabled + 1
            end
        end
        Off(GUI.launchGameButton)
        Off(GUI.gameoptionsButton)
        Off(GUI.becomeObserver)
        Off(GUI.AIFillButton)
        Off(GUI.AIClearButton)
        Off(GUI.restrictedUnitsOrPresetsBtn)
        Off(GUI.loadButton)
        -- The observer panel's lobby-changing buttons (lobby.lua: default options, random map, close empty slots, auto
        -- teams, auto balance) and the AI fill choosers. The CPU test, Settings, patch notes, briefing and Exit stay.
        Off(GUI.defaultOptions)
        Off(GUI.randMap)
        Off(GUI.closeEmptySlots)
        Off(GUI.autoTeams)
        Off(GUI.PenguinAutoBalance)
        Off(GUI.AIFillCombo)
        Off(GUI.TeamCountSelector)
        if GUI.slots then
            for _, slot in GUI.slots do
                Off(slot.name)
                Off(slot.faction)
                Off(slot.color)
                Off(slot.team)
            end
        end
        if not saidLocked then
            saidLocked = true
            LOG('faf-re lobby hook (WP17.6): an organiser runs this lobby; ' .. disabled .. ' controls are read-only')
        end
    end

    local function Lock()
        local locked, why = pcall(LockLobbyScreen)
        if not locked then
            WARN('faf-re lobby hook (WP17.6): ' .. tostring(why))
        end
    end

    -- The host's HostUtils.RefreshButtonEnabledness turns options, map, teams and launch back on whenever someone's
    -- readiness changes; HostUtils is made when a lobby is, so it's wrapped the first time the lobby refreshes.
    local function WrapHostRefresh()
        if HostUtils and type(HostUtils.RefreshButtonEnabledness) == 'function' and not rawget(HostUtils, 'FafReLocked') then
            local OriginalRefresh = HostUtils.RefreshButtonEnabledness
            HostUtils.RefreshButtonEnabledness = function(...)
                local result = OriginalRefresh(unpack(arg))
                Lock()
                return result
            end
            rawset(HostUtils, 'FafReLocked', true)
        end
    end

    local hooked, problem = pcall(function()
        local OriginalUpdateGame = UpdateGame
        if type(OriginalUpdateGame) ~= 'function' then
            error('UpdateGame is not a function here')
        end
        UpdateGame = function(...)
            local result = OriginalUpdateGame(unpack(arg))
            pcall(WrapHostRefresh)
            Lock()
            return result
        end
        -- SetSlotInfo turns a player's own colour, faction and team back on whenever their slot is drawn.
        local OriginalSetSlotInfo = SetSlotInfo
        if type(OriginalSetSlotInfo) == 'function' then
            SetSlotInfo = function(...)
                local result = OriginalSetSlotInfo(unpack(arg))
                Lock()
                return result
            end
        end
    end)
    if not hooked then
        WARN('faf-re lobby hook (WP17.6) not installed: ' .. tostring(problem))
    end
end

--- Engine addition (plan WP2.14): on a game server a launch is a request the server may refuse. FAF's TryLaunch
--- flattens gameInfo (GameInfo.Flatten) and leaves windowed mode before it sends the launch, as a launch in a
--- peer-to-peer lobby always goes ahead. Until the server answers, the lobby keeps running (its ping thread walks
--- gameInfo.PlayerOptions:pairs() every second), so on a game server the host's game info is made whole again as soon
--- as the launch is sent, as a joiner's lobby rebuilds the host's flat game info (GameInfo.CreateGameInfo).
do
    local function RestoreGameInfo()
        if gameInfo and gameInfo.PlayerOptions and gameInfo.PlayerOptions.pairs == nil then
            gameInfo = GameInfo.CreateGameInfo(LobbyComm.maxPlayerSlots, gameInfo)
        end
    end
    local wrapped, problem = pcall(function()
        local launch = TryLaunch
        if type(launch) ~= 'function' then
            error('TryLaunch is not a function here')
        end
        TryLaunch = function(skipNoObserversCheck)
            launch(skipNoObserversCheck)
            if rawget(_G, 'ServerLobbySession') then
                local restored, why = pcall(RestoreGameInfo)
                if not restored then
                    WARN('faf-re lobby (WP2.14): the game info was not rebuilt after the launch: ' .. tostring(why))
                end
            end
        end
    end)
    if not wrapped then
        WARN('faf-re lobby (WP2.14): ' .. tostring(problem))
    end

    --- The game server refused the launch (`ELobbySignal::LaunchRefused`, sent to everyone in the lobby): back into the
    --- lobby window (the host's TryLaunch and a joiner's `Launch` handler left it), and the reason in the chat.
    function ServerLaunchRefused(text)
        local restored, why = pcall(function()
            RestoreGameInfo()
            SetWindowedLobby(true)
            UpdateGame()
        end)
        if not restored then
            WARN('faf-re lobby (WP2.14): the lobby was not restored after a refused launch: ' .. tostring(why))
        end
        AddChatText(text)
    end
end


do
-- Append-only engine hook; do not modify FAF's downloaded lobby files.
local ConnectionTest = import('/fafengine/lua/ui/lobby/connectiontest.lua')
local Communication = import('/lua/ui/lobby/lobbyComm.lua')
local UIUtil = import('/lua/ui/uiutil.lua')
-- Filled by the builder only when a local threading preference is saved.
local microchipSimWorkers = nil
local originalCreateComm = Communication.CreateLobbyComm
local connection, parent, buttonAnchor, optionsAnchor
local originalCreateButton = UIUtil.CreateButtonStd
UIUtil.CreateButtonStd = function(owner, texture, label, size, vertical, horizontal, click, rollover)
    local control = originalCreateButton(owner, texture, label, size, vertical, horizontal, click, rollover)
    if texture == '/BUTTON/closeslots/' then buttonAnchor = control end
    if texture == '/BUTTON/defaultoption/' then optionsAnchor = control end
    return control
end
local originalCreateScreen = UIUtil.CreateScreenGroup
UIUtil.CreateScreenGroup = function(root, name)
    local screen = originalCreateScreen(root, name)
    if name == 'CreateLobby ScreenGroup' then parent = screen end
    return screen
end
Communication.CreateLobbyComm = function(protocol, port, name, uid, traversal)
    connection = originalCreateComm(protocol, port, name, uid, traversal)
    return connection
end

local originalReallyCreateLobby = ReallyCreateLobby
function ReallyCreateLobby(protocol, localPort, name, uid, traversal, over, exitBehavior, hasGame)
    import('/fafengine/lua/ui/translation.lua').Reset()
    if microchipSimWorkers ~= nil then
        ConExecute('sim_Workers ' .. tostring(microchipSimWorkers))
        LOG('Microchip lobby: simulation workers requested=' .. tostring(microchipSimWorkers))
    end
    parent = nil
    originalReallyCreateLobby(protocol, localPort, name, uid, traversal, over, exitBehavior, hasGame)
    if connection then ConnectionTest.Attach(connection) end
end

local originalAddChatText = AddChatText
function AddChatText(text, playerID, scrollToBottom)
    originalAddChatText(text, playerID, scrollToBottom)
    if not playerID or not connection or tonumber(playerID) == tonumber(connection:GetLocalPlayerID()) then return end
    local currentConnection = connection
    import('/fafengine/lua/ui/translation.lua').Translate(text, function(english)
        if currentConnection and connection == currentConnection then
            originalAddChatText(english, playerID, false)
        end
    end)
end

local originalCreateUI = CreateUI
-- Ranked preferences are independent of LastColorFAF (FAF overwrites that on redraw).
local colourPrefs = Prefs.GetFromCurrentProfile('MicrochipLobbyColours') or {6, 11, 8}
if type(colourPrefs) ~= 'table' then colourPrefs = {6, 11, 8} end
local colourAttempt, applyingColour
local function ApplyPreferredColour()
    if applyingColour or singlePlayer or not GUI or not GUI.uiCreated or not lobbyComm
        or rawget(_G, 'ServerLobbyControl') == 'organiser'
        or not gameInfo or not gameInfo.PlayerOptions or not gameInfo.PlayerOptions.pairs then return end
    local slot = FindSlotForID(localPlayerID)
    local player = slot and gameInfo.PlayerOptions[slot]
    if not player or not player.Human or player.Ready then return end
    local signature = {tostring(slot), tostring(player.PlayerColor)}
    local occupied = {}
    for index, other in gameInfo.PlayerOptions:pairs() do
        if index ~= slot then occupied[other.PlayerColor] = true end
        table.insert(signature, tostring(index) .. ':' .. tostring(other.OwnerID) .. ':' .. tostring(other.PlayerColor))
    end
    table.sort(signature)
    for rank = 1, 3 do
        local colour = colourPrefs[rank]
        if type(colour) == 'number' and gameColors.PlayerColors[colour] and not occupied[colour] then
            if player.PlayerColor == colour then colourAttempt = nil; return end
            local attempt = tostring(colour) .. '/' .. table.concat(signature, ',')
            -- One request per observed roster state: rejection must not create a request loop.
            if colourAttempt == attempt then return end
            if lobbyComm:IsHost() then
                colourAttempt = attempt
                applyingColour = true
                GUI.slots[slot].color:OnClick(colour)
                applyingColour = false
            elseif hostID then
                colourAttempt = attempt
                -- Wait for the authoritative SetColor; never claim a colour locally before approval.
                lobbyComm:SendData(hostID, {Type = 'RequestColor', Color = colour})
            end
            return
        end
    end
end

local originalColourUpdate = UpdateGame
UpdateGame = function(...)
    local result = originalColourUpdate(unpack(arg))
    ApplyPreferredColour()
    return result
end
local originalColourSlot = SetSlotInfo
SetSlotInfo = function(...)
    local result = originalColourSlot(unpack(arg))
    ApplyPreferredColour()
    return result
end

-- Not in retail: a "Lag" column at the right of the Nickname column with each human's
-- average wait from past games where they were the worst (waitscores.lua). Empty when unknown.
local WaitScores = import('/fafengine/lua/ui/lobby/waitscores.lua')
local function LagCell(slot)
    if not slot or not slot.name then return nil end
    if not slot.microchipLag then
        local cell = UIUtil.CreateText(slot, '', 14, 'Arial')
        cell:SetColor('B9BFB9')
        cell:DisableHitTest()
        -- Narrow the nickname box so its dropdown arrow ends before the Lag column.
        slot.name.Width:Set(LayoutHelpers.ScaleNumber(257 - 52))
        LayoutHelpers.RightOf(cell, slot.name, 6)
        LayoutHelpers.AtVerticalCenterIn(cell, slot.name)
        slot.microchipLag = cell
    end
    return slot.microchipLag
end
local function LagHeader()
    local first = GUI.slots and GUI.slots[1]
    if not first or not first.name or not GUI.labelGroup or GUI.microchipLagHeaderFor == GUI.labelGroup then return end
    GUI.microchipLagHeaderFor = GUI.labelGroup
    -- A new lobby UI: reload the history so games played since the last lobby count.
    WaitScores.Reset()
    -- Every row, open ones included, gets the narrower nickname box so the arrows line up.
    for _, slot in pairs(GUI.slots) do LagCell(slot) end
    local header = UIUtil.CreateText(GUI.labelGroup, 'Lag', 14, UIUtil.titleFont)
    header:DisableHitTest()
    LayoutHelpers.AtLeftIn(header, first.name, 257 - 52 + 6)
    LayoutHelpers.AtVerticalCenterIn(header, GUI.labelGroup)
    GUI.microchipLagHeader = header
end
local originalWaitSlot = SetSlotInfo
SetSlotInfo = function(slotNum, playerInfo)
    local result = originalWaitSlot(slotNum, playerInfo)
    LagHeader()
    local cell = LagCell(GUI.slots and GUI.slots[slotNum])
    if cell then
        local text = ''
        if playerInfo and playerInfo.Human then
            local ok, score = pcall(WaitScores.Get, playerInfo.PlayerName, playerInfo.OwnerID)
            text = ok and score and string.format('%.1fs', score.average) or ''
        end
        cell:SetText(text)
    end
    return result
end
local originalWaitClear = ClearSlotInfo
ClearSlotInfo = function(slotIndex)
    local result = originalWaitClear(slotIndex)
    local slot = GUI.slots and GUI.slots[slotIndex]
    if slot and slot.microchipLag then slot.microchipLag:SetText('') end
    return result
end

local function ShowColourPreferences()
    local Layout = import('/lua/maui/layouthelpers.lua')
    local BitmapCombo = import('/lua/ui/controls/combo.lua').BitmapCombo
    local button = UIUtil.CreateButtonWithDropshadow(GUI.panel, '/BUTTON/medium/', 'Colour prefs')
    GUI.colourPreferencesButton = button
    -- Share the existing bottom row; Presets/Unit Manager was centered across
    -- both columns and would overlap a new button below Patchnotes.
    Layout.AtHorizontalCenterIn(GUI.restrictedUnitsOrPresetsBtn, GUI.gameoptionsButton)
    Layout.AtVerticalCenterIn(button, GUI.restrictedUnitsOrPresetsBtn)
    Layout.AtHorizontalCenterIn(button, GUI.patchnotesButton)
    Tooltip.AddControlTooltipManual(button, 'Colour preferences',
        'Choose your first, second and third preferred lobby colours.')
    button.OnClick = function()
        local content = import('/lua/maui/group.lua').Group(parent)
        Layout.SetDimensions(content, 430, 255)
        local title = UIUtil.CreateText(content, 'Preferred lobby colours', 18, UIUtil.titleFont)
        Layout.AtLeftTopIn(title, content, 20, 15)
        local hint = UIUtil.CreateText(content, 'Uses the first free colour; upgrades when available.', 12, UIUtil.bodyFont)
        Layout.AtLeftTopIn(hint, content, 20, 45)
        for rank = 1, 3 do
            local preference = rank
            local label = UIUtil.CreateText(content, 'Preference ' .. rank, 14, UIUtil.bodyFont)
            Layout.AtLeftTopIn(label, content, 25, 50 + rank * 35)
            local selected = colourPrefs[rank]
            if not gameColors.PlayerColors[selected] then selected = 6 end
            local combo = BitmapCombo(content, gameColors.PlayerColors, selected, true)
            Layout.SetWidth(combo, 150)
            Layout.AtLeftTopIn(combo, content, 200, 45 + rank * 35)
            combo.OnClick = function(self, index)
                colourPrefs[preference] = index
                Prefs.SetToCurrentProfile('MicrochipLobbyColours', colourPrefs)
                colourAttempt = nil
                ApplyPreferredColour()
            end
        end
        local popup = import('/lua/ui/controls/popups/popup.lua').Popup(parent, content)
        local close = UIUtil.CreateButtonStd(content, '/BUTTON/medium/', 'Close', 12)
        Layout.AtLeftBottomIn(close, content, 150, 10)
        close.OnClick = function() popup:Destroy() end
        popup.OnEscapePressed = close.OnClick
        popup.OnShadowClicked = close.OnClick
    end
end

function CreateUI(maxPlayers)
    buttonAnchor, optionsAnchor = nil, nil
    if not rebuildingLobbyForScale then colourAttempt = nil end
    originalCreateUI(maxPlayers)
    if buttonAnchor and optionsAnchor then
        local panel = buttonAnchor:GetParent()
        local offset = panel.Top() - panel:GetParent().Top()
        -- Reserve a row above the observer box while keeping the existing buttons in place.
        panel.Top:Set(function() return panel:GetParent().Top() + offset + LayoutHelpers.ScaleNumber(40) end)
        optionsAnchor.Top:Set(function() return panel.Top() - LayoutHelpers.ScaleNumber(134) end)
        -- The lowered observer panel would overlap Launch Game; keep the button below it.
        local launch = GUI.launchGameButton
        if launch then
            -- FAF anchors the bottom edge (Top derives from Height), so move Bottom to keep full height.
            launch.Bottom:Set(function() return panel.Bottom() + LayoutHelpers.ScaleNumber(4) + launch.Height() end)
        end
    end
    if connection then ConnectionTest.Show(parent, buttonAnchor) end
    if singlePlayer then return end
    ShowColourPreferences()
    if rebuildingLobbyForScale then return end
    ApplyPreferredColour()

    -- The lobby can load before selected UI mods are active as script hooks.
    for _, mod in ipairs(Mods.GetUiMods()) do
        if mod.uid == 'a16bec45-d3ab-4be7-9915-0a43194c83fe' then
            local screen = GUI
            local alert = import(mod.location .. '/readyalert.lua')
            ForkThread(alert.WatchLobby, function()
                if GUI == screen and lobbyComm then
                    return gameInfo.PlayerOptions
                end
            end)
            break
        end
    end
end

end

-- Its own do/end block: locals of the block above (lines from `do` after the WP2.14 hook, such as
-- WaitScores and UIUtil) are not in scope here, so this block imports what it needs.
do
-- Not in retail: typing "/" in lobby chat lists the chat commands; click one to fill it in.
-- "/lag report" prints every human's lag score (waitscores.lua) to your own chat;
-- "/lag report all" sends it to the lobby.
local function LagReportLines()
    local WaitScores = import('/fafengine/lua/ui/lobby/waitscores.lua')
    local lines, rows = {}, {}
    WaitScores.Reset() -- pick up games recorded since the lobby opened
    -- PlayerOptions is a watched array, so pairs() sees nothing; index every slot.
    for slot = 1, LobbyComm.maxPlayerSlots do
        local player = gameInfo and gameInfo.PlayerOptions[slot]
        if player and player.Human and player.PlayerName then
            local ok, score = pcall(WaitScores.Get, player.PlayerName, player.OwnerID)
            score = ok and score or nil
            table.insert(rows, {name = player.PlayerName, score = score})
        end
    end
    table.sort(rows, function(a, b)
        local av, bv = a.score and a.score.average or -1, b.score and b.score.average or -1
        if av ~= bv then return av > bv end
        return a.name < b.name
    end)
    for _, row in ipairs(rows) do
        if row.score then
            table.insert(lines, string.format('%s: %.1fs (worst in %d of %d games)',
                row.name, row.score.average, row.score.worstGames, row.score.games))
        else
            table.insert(lines, row.name .. ': no lag recorded')
        end
    end
    return lines
end

commands.lag = function(params)
    local words = {}
    for word in string.gfind(string.lower(params or ''), '%S+') do table.insert(words, word) end
    if words[1] ~= 'report' then
        AddChatText('Usage: /lag report  (add "all" to send it to the lobby)')
        return
    end
    local lines = LagReportLines()
    if table.getn(lines) == 0 then lines = {'No players in the lobby.'} end
    if words[2] == 'all' then
        PublicChat('Lag report (avg wait in games where the player was worst):')
        for _, line in ipairs(lines) do PublicChat(line) end
    else
        AddChatText('Lag report (avg wait in games where the player was worst):')
        for _, line in ipairs(lines) do AddChatText(line) end
    end
end

local chatCommandList = {
    {text = '/lag report', help = 'show each player\'s lag score'},
    {text = '/lag report all', help = 'send the lag report to the lobby'},
    {text = '/whisper ', help = 'name message - private message (also /w, /pm)'},
}

local function CreateCommandMenu()
    local edit = GUI and GUI.chatEdit
    if not edit then return end
    local Group = import('/lua/maui/group.lua').Group
    local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
    local menu = Group(edit:GetParent())
    menu:Hide()
    menu.Depth:Set(function() return edit.Depth() + 50 end)
    LayoutHelpers.Above(menu, edit, 4)
    LayoutHelpers.AtLeftIn(menu, edit)
    menu.Width:Set(LayoutHelpers.ScaleNumber(440))
    local rowHeight = LayoutHelpers.ScaleNumber(20)
    menu.Height:Set(rowHeight * table.getn(chatCommandList) + LayoutHelpers.ScaleNumber(6))
    local bg = Bitmap(menu)
    bg:SetSolidColor('E0101418')
    LayoutHelpers.FillParent(bg, menu)
    menu.rows = {}
    for i, entry in ipairs(chatCommandList) do
        local command = entry
        local row = Bitmap(menu)
        row:SetSolidColor('00000000')
        row.Left:Set(menu.Left)
        row.Right:Set(menu.Right)
        row.Height:Set(rowHeight)
        row.Top:Set(function() return menu.Top() + LayoutHelpers.ScaleNumber(3) + rowHeight * (row.index - 1) end)
        row.index = i
        local label = UIUtil.CreateText(row, command.text, 13, 'Arial')
        label:DisableHitTest()
        LayoutHelpers.AtLeftIn(label, row, 6)
        LayoutHelpers.AtVerticalCenterIn(label, row)
        local help = UIUtil.CreateText(row, command.help, 13, 'Arial')
        help:SetColor('FF9AA3AA')
        help:DisableHitTest()
        LayoutHelpers.AtLeftIn(help, row, 130)
        LayoutHelpers.AtVerticalCenterIn(help, row)
        row.command = command
        row.HandleEvent = function(self, event)
            if event.Type == 'MouseEnter' then self:SetSolidColor('60406080')
            elseif event.Type == 'MouseExit' then self:SetSolidColor('00000000')
            elseif event.Type == 'ButtonPress' then
                edit:SetText(self.command.text)
                edit:AcquireFocus()
                return true
            end
        end
        menu.rows[i] = row
    end
    local function Refresh(text)
        text = text or ''
        if string.sub(text, 1, 1) ~= '/' then menu:Hide(); return end
        local typed = string.lower(text)
        local matches = {}
        for _, row in ipairs(menu.rows) do
            local command = string.lower(row.command.text)
            if string.sub(command, 1, string.len(typed)) == typed and typed ~= command then
                table.insert(matches, row)
            end
        end
        if table.getn(matches) == 0 then menu:Hide(); return end
        menu.Height:Set(rowHeight * table.getn(matches) + LayoutHelpers.ScaleNumber(6))
        -- Show() re-shows every child, so hide the non-matching rows afterwards.
        menu:Show()
        for _, row in ipairs(menu.rows) do row:Hide() end
        for i, row in ipairs(matches) do
            row.index = i
            row:Show()
        end
    end
    local originalChanged = edit.OnTextChanged
    edit.OnTextChanged = function(self, newText, oldText)
        Refresh(newText)
        if originalChanged then return originalChanged(self, newText, oldText) end
    end
    local originalEnter = edit.OnEnterPressed
    edit.OnEnterPressed = function(self, text)
        menu:Hide()
        return originalEnter(self, text)
    end
    GUI.microchipCommandMenu = menu
end

local originalCommandMenuCreateUI = CreateUI
CreateUI = function(maxPlayers)
    local result = originalCommandMenuCreateUI(maxPlayers)
    local ok, err = pcall(CreateCommandMenu)
    if not ok then LOG('Microchip chat command menu: ' .. tostring(err)) end
    return result
end
end
