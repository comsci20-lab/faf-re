local Sharing = import('/mods/Microchip-Eco-Sharing/modules/sharing.lua')
local Allocate = import('/mods/Microchip-Eco-Sharing/modules/allocation.lua')
local UI = import('/lua/ui/uiutil.lua')
local L = import('/lua/maui/layouthelpers.lua')
local Group = import('/lua/maui/group.lua').Group
local Bitmap = import('/lua/maui/bitmap.lua').Bitmap
local Slider = import('/lua/maui/slider.lua').IntegerSlider
local Combo = import('/lua/ui/controls/combo.lua').Combo
local Popup = import('/lua/ui/controls/popups/popup.lua').Popup
local window = false
local lime, white, grey = 'ffd9ed73','ffe4e5dc','ff9aab9e'

local function Copy(t)
    if type(t) ~= 'table' then return t end
    local n={}; for k,v in pairs(t) do n[k]=Copy(v) end; return n
end
local function Box(parent,x,y,w,h,colour)
    local b=Bitmap(parent); b:SetSolidColor(colour)
    b.Width:Set(L.ScaleNumber(w)); b.Height:Set(L.ScaleNumber(h)); L.AtLeftTopIn(b,parent,x,y)
    return b
end
local function Text(parent,text,size,x,y,colour)
    local t=UI.CreateText(parent,text,size,UI.bodyFont)
    t:SetColor(colour or white); L.AtLeftTopIn(t,parent,x,y); t:DisableHitTest(); return t
end
local function Button(parent,text,x,y,w,click,height)
    height=height or 27
    local b=Box(parent,x,y,w,height,'ff434a32')
    Box(b,1,1,w-2,height-2,'ff171d19'):DisableHitTest()
    local label=Text(b,text,13,0,0,lime); L.AtCenterIn(label,b)
    b.HandleEvent=function(self,event)
        if event.Type=='MouseEnter' then self:SetSolidColor('ffc5d963')
        elseif event.Type=='MouseExit' then self:SetSolidColor('ff434a32')
        elseif event.Type=='ButtonPress' then click(); return true end
        return false
    end
    return b
end
local function Tick(parent,x,y,checked,change)
    local b=Box(parent,x,y,23,23,'ff667148')
    local inside=Box(b,2,2,19,19,'ff141b14'); inside:DisableHitTest()
    local label=Text(b,checked and 'X' or '',16,5,0,lime)
    b.HandleEvent=function(self,event)
        if event.Type=='ButtonPress' then
            checked=not checked; label:SetText(checked and 'X' or ''); change(checked); return true
        end
        return false
    end
    return b
end

function Toggle()
    if window then window:Close(); return end
    local content=Group(GetFrame(0))
    content.Width:Set(L.ScaleNumber(780)); content.Height:Set(L.ScaleNumber(540))
    local background=Box(content,0,0,780,540,'f0161c18'); background:DisableHitTest()
    local draft=Copy(Sharing.Settings())
    local popup=Popup(GetFrame(0),content); window=popup
    local closed=popup.OnClosed
    popup.OnClosed=function(self) window=false; closed(self) end
    Text(content,'Microchip Eco Sharing',24,12,3,lime)
    Text(content,'Share surplus with selected allies when their resource storage is empty.',13,12,37)
    Button(content,'X',735,4,30,function() popup:Close() end)
    Tick(content,14,66,draft.enabled,function(on) draft.enabled=on end)
    Text(content,'Enable automatic sharing',14,47,67,lime)
    Text(content,'Reserve thresholds',17,14,105,lime)

    local function Reserve(resource,y)
        local key=string.lower(resource)..'Reserve'
        Text(content,resource..' reserve',14,16,y+3)
        local value=Text(content,tostring(draft[key])..'%',16,675,y+2,lime)
        local slider=Slider(content,false,0,100,1,
            UI.UIFile('/game/slider-btn/slider-'..string.lower(resource)..'_btn_up.dds'),
            UI.UIFile('/game/slider-btn/slider-'..string.lower(resource)..'_btn_up.dds'),
            UI.UIFile('/game/slider-btn/slider-'..string.lower(resource)..'_btn_up.dds'))
        slider.Width:Set(L.ScaleNumber(450)); slider.Height:Set(L.ScaleNumber(28))
        L.AtLeftTopIn(slider,content,190,y)
        slider._background:SetSolidColor('ff47513b')
        slider._background.Width:Set(slider.Width)
        slider._background.Height:Set(L.ScaleNumber(7))
        L.AtVerticalCenterIn(slider._background,slider)
        slider:SetValue(draft[key])
        slider.OnValueChanged=function(self,n)
            draft[key]=math.max(0,math.min(100,math.floor(n+0.5))); value:SetText(tostring(draft[key])..'%')
        end
    end
    Reserve('Energy',134); Reserve('Mass',173)
    Text(content,'Share to allies',17,15,216,lime)
    Text(content,'When multiple allies are empty',17,416,216,lime)
    Box(content,12,244,378,231,'ff323d2b'):DisableHitTest()
    Box(content,13,245,376,229,'ff131a16'):DisableHitTest()
    Text(content,'Ally',13,23,251); Text(content,'Energy',12,258,251,lime); Text(content,'Mass',12,324,251)

    Text(content,'Sharing mode:',14,415,249)
    local combo=Combo(content,14,2,false)
    combo.Width:Set(L.ScaleNumber(180)); L.AtLeftTopIn(combo,content,568,244)
    combo:AddItems({'Equal','Rank'},draft.mode=='Rank' and 2 or 1)
    local explanation=Text(content,'',12,417,280,grey)
    local priorityHeading=Text(content,'',13,417,307,lime)
    local rowGroup, priorityGroup, page = false,false,1
    local pageText=Text(content,'',12,142,481,grey)
    local refresh
    local function Move(name,delta)
        local list=Allocate.Ordered(Sharing.Allies(),draft.order)
        for i,ally in ipairs(list) do
            if ally.name==name then
                local target=i+delta
                if target<1 or target>table.getn(list) then return end
                list[i],list[target]=list[target],list[i]
                break
            end
        end
        draft.order={}; for _,ally in ipairs(list) do table.insert(draft.order,ally.name) end
        refresh()
    end
    refresh=function()
        if rowGroup then rowGroup:Destroy() end
        if priorityGroup then priorityGroup:Destroy() end
        rowGroup=Group(content); L.FillParent(rowGroup,content)
        priorityGroup=Group(content); L.FillParent(priorityGroup,content)
        local allies=Sharing.Allies(); local count=table.getn(allies)
        page=math.max(1,math.min(page,math.max(1,math.ceil(count/7))))
        local first=(page-1)*7+1
        for row=1,7 do
            local ally=allies[first+row-1]
            if ally then
                local y=278+(row-1)*27
                local chip=Box(rowGroup,24,y+3,13,17,ally.colour); chip:DisableHitTest()
                local name=ally.name
                Text(rowGroup,string.sub(name,1,24),13,43,y+3)
                draft.targets[name]=draft.targets[name] or {}
                for column,key in ipairs({'ENERGY','MASS'}) do
                    Tick(rowGroup,268+(column-1)*62,y,draft.targets[name][key],function(on) draft.targets[name][key]=on end)
                end
            end
        end
        if count==0 then Text(rowGroup,'No active allies available.',13,23,292,grey) end
        explanation:SetText(draft.mode=='Rank' and 'Rank fills higher-priority allies first.' or 'Equal divides surplus equally, up to storage limits.')
        local overridden=table.getn(draft.order)>0
        priorityHeading:SetText(overridden and 'Priority: manual override' or 'Priority: highest FAF rating first')
        local ordered=Allocate.Ordered(allies,draft.order)
        for row=1,7 do
            local ally=ordered[first+row-1]
            if ally then
                local y=331+(row-1)*20
                local name=ally.name
                local rating=ally.rating and tostring(math.floor(ally.rating+0.5)) or 'unrated'
                Text(priorityGroup,tostring(first+row-1)..'. '..string.sub(name,1,19)..' ('..rating..')',12,417,y)
                Button(priorityGroup,'^',696,y-3,23,function() Move(name,-1) end,18)
                Button(priorityGroup,'v',723,y-3,23,function() Move(name,1) end,18)
            end
        end
        pageText:SetText(count>0 and ('Allies '..first..'-'..math.min(first+6,count)..' of '..count) or '')
    end
    combo.OnClick=function(self,index) draft.mode=index==2 and 'Rank' or 'Equal'; refresh() end
    Button(content,'<',20,477,34,function() page=page-1; refresh() end)
    Button(content,'>',338,477,34,function() page=page+1; refresh() end)
    Button(content,'Reset to rank',416,477,150,function() draft.order={}; refresh() end)
    Button(content,'Apply',578,503,82,function()
        Sharing.Save(Copy(draft)); popup:Close()
    end)
    Button(content,'Close',672,503,82,function() popup:Close() end)
    local status=Text(content,Sharing.Status(),12,14,508,grey)
    status:SetText(string.sub(Sharing.Status(),1,68))
    refresh()
end
