-- Append-only engine hook; do not modify FAF's downloaded lobby files.
local ConnectionTest = import('/fafengine/lua/ui/lobby/connectiontest.lua')
local Communication = import('/lua/ui/lobby/lobbyComm.lua')
local UIUtil = import('/lua/ui/uiutil.lua')
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
    parent = nil
    originalReallyCreateLobby(protocol, localPort, name, uid, traversal, over, exitBehavior, hasGame)
    if connection then ConnectionTest.Attach(connection) end
end

local originalCreateUI = CreateUI
function CreateUI(maxPlayers)
    originalCreateUI(maxPlayers)
    if buttonAnchor and optionsAnchor then
        local panel = buttonAnchor:GetParent()
        local offset = panel.Top() - panel:GetParent().Top()
        -- Reserve a row above the observer box while keeping the existing buttons in place.
        panel.Top:Set(function() return panel:GetParent().Top() + offset + 40 end)
        optionsAnchor.Top:Set(function() return panel.Top() - 134 end)
    end
    if connection then ConnectionTest.Show(parent, buttonAnchor) end
end
