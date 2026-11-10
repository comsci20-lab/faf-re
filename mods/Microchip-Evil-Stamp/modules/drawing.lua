-- MC chip: continuous square-and-pins outline, then M and C.
Paths = {
    {{-40,-40}, {-20,-40}, {-20,-58}, {-20,-40}, {0,-40}, {0,-58}, {0,-40}, {20,-40}, {20,-58}, {20,-40}, {40,-40}, {40,-20}, {58,-20}, {40,-20}, {40,0}, {58,0}, {40,0}, {40,20}, {58,20}, {40,20}, {40,40}, {20,40}, {20,58}, {20,40}, {0,40}, {0,58}, {0,40}, {-20,40}, {-20,58}, {-20,40}, {-40,40}, {-40,20}, {-58,20}, {-40,20}, {-40,0}, {-58,0}, {-40,0}, {-40,-20}, {-58,-20}, {-40,-20}, {-40,-40}},
    {{-27,17}, {-27,-17}, {-13,-2}, {1,-17}, {1,17}},
    {{27,-17}, {10,-17}, {10,17}, {27,17}},
}

-- Simplified husky ears, face mask, sleepy eyes, crooked smile and beer mug.
HuskyPaths = {
    {{-37,-9},{-43,-49},{-21,-33},{0,-38},{22,-33},{43,-49},{38,-7},{32,20},{17,35},{-15,35},{-32,20},{-37,-9}},
    {{-37,-9},{-23,-19},{-10,-7},{-17,10},{0,23},{17,10},{11,-7},{25,-19},{38,-7}},
    {{-28,-7},{-11,-2},{-18,3},{-28,-7}},
    {{12,-3},{29,-10},{25,1},{12,-3}},
    {{-7,12},{7,12},{0,19},{-7,12}},
    {{-15,23},{-5,28},{6,27},{16,20}},
    {{-26,29},{-32,42},{0,53},{28,42},{24,30}},
    {{34,15},{58,15},{58,49},{34,49},{34,15},{37,9},{43,12},{48,8},{54,12},{58,15}},
    {{58,21},{68,21},{68,40},{58,40}},
}
Designs = {mc = Paths, husky = HuskyPaths}

local function Finite(n)
    return type(n)=='number' and n==n and n-n==0
end

-- Validate the whole stamp before publishing anything. No partial drawings or limit bypass.
function Project(unproject,mouse,scale,viewBounds,mapSize,design)
    local result,total={},0
    if not Finite(scale) or scale<=0 then return nil,'Invalid drawing size.' end
    local paths=Designs[design or 'mc']
    if not paths then return nil,'Unknown logo.' end
    for _,path in ipairs(paths) do
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
