-- MC chip: continuous square-and-pins outline, then M and C.
Paths = {
    {{-40,-40}, {-20,-40}, {-20,-58}, {-20,-40}, {0,-40}, {0,-58}, {0,-40}, {20,-40}, {20,-58}, {20,-40}, {40,-40}, {40,-20}, {58,-20}, {40,-20}, {40,0}, {58,0}, {40,0}, {40,20}, {58,20}, {40,20}, {40,40}, {20,40}, {20,58}, {20,40}, {0,40}, {0,58}, {0,40}, {-20,40}, {-20,58}, {-20,40}, {-40,40}, {-40,20}, {-58,20}, {-40,20}, {-40,0}, {-58,0}, {-40,0}, {-40,-20}, {-58,-20}, {-40,-20}, {-40,-40}},
    {{-27,17}, {-27,-17}, {-13,-2}, {1,-17}, {1,17}},
    {{27,-17}, {10,-17}, {10,17}, {27,17}},
}

local function Finite(n)
    return type(n)=='number' and n==n and n-n==0
end

-- Validate the whole stamp before publishing anything. No partial drawings or limit bypass.
function Project(unproject,mouse,scale,viewBounds,mapSize)
    local result,total={},0
    if not Finite(scale) or scale<=0 then return nil,'Invalid drawing size.' end
    for _,path in ipairs(Paths) do
        local count=table.getn(path)
        total=total+count
        if count<2 or count>128 or total>128 then return nil,'Drawing exceeds the normal point budget.' end
        local samples={CoordinatesX={},CoordinatesY={},CoordinatesZ={}}
        for _,point in ipairs(path) do
            local sx,sy=mouse[1]+point[1]*scale,mouse[2]+point[2]*scale
            if sx<viewBounds[1]+2 or sx>viewBounds[3]-2 or sy<viewBounds[2]+2 or sy>viewBounds[4]-2 then
                return nil,'Move the cursor farther from the edge of the view.'
            end
            local world=unproject(sx,sy)
            if not world or not Finite(world[1]) or not Finite(world[2]) or not Finite(world[3]) then
                return nil,'Move the cursor onto the map.'
            end
            if mapSize and mapSize[1] and mapSize[2] and
                (world[1]<0 or world[3]<0 or world[1]>mapSize[1] or world[3]>mapSize[2]) then
                return nil,'Move the cursor farther inside the map.'
            end
            table.insert(samples.CoordinatesX,world[1])
            table.insert(samples.CoordinatesY,world[2])
            table.insert(samples.CoordinatesZ,world[3])
        end
        table.insert(result,samples)
    end
    return result
end
