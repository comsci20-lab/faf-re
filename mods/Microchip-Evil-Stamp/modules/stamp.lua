local Drawing = import('/mods/Microchip-Evil-Stamp/modules/drawing.lua')
local WorldViews = import('/lua/ui/game/worldview.lua')
local L = import('/lua/maui/layouthelpers.lua')
local CreateStroke = import('/lua/ui/game/painting/BrushStroke.lua').CreateBrushStroke
local lastStamp = -100

local function Feedback(text)
    print('Microchip Evil Stamp: '..text)
    return false
end

function Stamp()
    local now=CurrentTime()
    if now<lastStamp then lastStamp=-100 end
    if now-lastStamp<5 then return false end
    local mouse=GetMouseScreenPos()
    local view,depth
    for _,candidate in pairs(WorldViews.GetWorldViews()) do
        if not IsDestroyed(candidate) and not candidate:IsHidden() and candidate:HitTest(mouse[1],mouse[2]) then
            if not view or candidate.Depth()>depth then view=candidate; depth=candidate.Depth() end
        end
    end
    if not view then return Feedback('Move the cursor over the battlefield.') end
    local canvas=view.PaintingCanvas
    if not canvas or IsDestroyed(canvas) or not canvas.Adapter then return Feedback('Painting is not available in this view.') end
    if not canvas:IsEnabledByGameOptions() then return Feedback('Enable painting in Options > Interface first.') end
    if import('/lua/ui/game/gamemain.lua').gameUIHidden then return false end
    if import('/lua/ui/game/commandmode.lua').InCommandMode() then return Feedback('Finish the active placement command first.') end

    local info=SessionGetScenarioInfo()
    local size=info and info.size
    local samples,reason=Drawing.Project(function(x,y) return view:UnProject({x,y}) end,
        mouse,L.ScaleNumber(2),{view.Left(),view.Top(),view.Right(),view.Bottom()},size)
    if not samples then return Feedback(reason) end
    local armies=GetArmiesTable().armiesTable or {}
    local army=armies[GetFocusArmy()]
    local colour=army and army.color or 'ffffffff'
    lastStamp=now
    for _,points in ipairs(samples) do
        local stroke=CreateStroke(points,colour)
        canvas.Adapter:SharePaintingBrushStroke(stroke)
        stroke:Destroy()
    end
    return true
end
