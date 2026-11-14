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

local function ShowColourPreferences()
    local Layout = import('/lua/maui/layouthelpers.lua')
    local button = UIUtil.CreateButtonStd(parent, '/BUTTON/medium/', 'Colour preferences', 12)
    Layout.SetDimensions(button, 170, 32)
    Layout.AtRightTopIn(button, parent, 301, 45)
    button.OnClick = function()
        local content = import('/lua/maui/group.lua').Group(parent)
        content.Width:Set(430); content.Height:Set(255)
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
    colourAttempt = nil
    originalCreateUI(maxPlayers)
    if buttonAnchor and optionsAnchor then
        local panel = buttonAnchor:GetParent()
        local offset = panel.Top() - panel:GetParent().Top()
        -- Reserve a row above the observer box while keeping the existing buttons in place.
        panel.Top:Set(function() return panel:GetParent().Top() + offset + 40 end)
        optionsAnchor.Top:Set(function() return panel.Top() - 134 end)
    end
    if connection then ConnectionTest.Show(parent, buttonAnchor) end
    if singlePlayer then return end
    ShowColourPreferences()
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
