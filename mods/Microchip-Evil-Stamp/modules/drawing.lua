-- Exact four-stroke geometry approved in the mock-up.
Paths = {
    {{-40,-26}, {-34,-32}, {-38,-54}, {-17,-32}, {-10,-32}, {-10,-43}, {-4,-43}, {-4,-32}, {4,-32}, {4,-43}, {10,-43}, {10,-32}, {17,-32}, {38,-54}, {34,-32}, {40,-26}, {40,-20}, {54,-20}, {54,-14}, {40,-14}, {40,-4}, {54,-4}, {54,2}, {40,2}, {40,12}, {54,12}, {54,18}, {40,18}, {40,26}, {34,32}, {26,32}, {26,46}, {38,46}, {38,53}, {17,53}, {17,32}, {4,32}, {4,43}, {-4,43}, {-4,32}, {-17,32}, {-17,53}, {-38,53}, {-38,46}, {-26,46}, {-26,32}, {-34,32}, {-40,26}, {-40,18}, {-54,18}, {-54,12}, {-40,12}, {-40,2}, {-54,2}, {-54,-4}, {-40,-4}, {-40,-14}, {-54,-14}, {-54,-20}, {-40,-20}, {-40,-26}},
    {{-26,-18}, {-7,-8}, {-24,-7}, {-26,-18}},
    {{26,-18}, {7,-8}, {24,-7}, {26,-18}},
    {{-24,6}, {-12,12}, {-9,20}, {-4,14}, {4,14}, {9,20}, {12,12}, {24,6}, {19,27}, {0,31}, {-19,27}, {-24,6}},
}

local function Finite(n)
    return type(n)=='number' and n==n and n>-math.huge and n<math.huge
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
