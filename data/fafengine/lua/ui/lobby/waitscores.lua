-- Lag scores for the lobby from %LOCALAPPDATA%\Microchip\faf-lag\game-waits.csv
-- (written by this engine). A player's score is the total game wait they caused in the games
-- where they were the worst, averaged over every recorded game they played in.
-- Engine/UI addition, not in retail; nothing here reaches the sim.

local function SplitCsvLine(line)
    local fields, field, quoted, i, n = {}, '', false, 1, string.len(line)
    while i <= n do
        local c = string.sub(line, i, i)
        if quoted then
            if c == '"' and string.sub(line, i + 1, i + 1) == '"' then field = field .. '"'; i = i + 1
            elseif c == '"' then quoted = false
            else field = field .. c end
        elseif c == '"' then quoted = true
        elseif c == ',' then table.insert(fields, field); field = ''
        else field = field .. c end
        i = i + 1
    end
    table.insert(fields, field)
    return fields
end

-- "name 1.23%; other 0.5%" or "name 12.3; other 4" -> {name = number}
local function ParseList(text)
    local out = {}
    local start = 1
    while text and start <= string.len(text) do
        local stop = string.find(text, ';', start, true) or (string.len(text) + 1)
        local item = string.sub(text, start, stop - 1)
        local _, _, name, value = string.find(item, '^%s*(.-)%s+([%d%.]+)%%?%s*$')
        if name and name ~= '' then out[name] = tonumber(value) or 0 end
        start = stop + 1
    end
    return out
end

-- Returns {[name] = {average = seconds, worstGames = n, games = n}}.
function Parse(text)
    local scores = {}
    if type(text) ~= 'string' then return scores end
    local columns
    for line in string.gfind(text .. '\n', '([^\n]*)\n') do
        line = string.gsub(line, '\r$', '')
        if line ~= '' then
            local fields = SplitCsvLine(line)
            if not columns then
                columns = {}
                for i, name in ipairs(fields) do columns[name] = i end
            else
                local minutes = tonumber(fields[columns.minutes_played or 0]) or 0
                local players = ParseList(fields[columns.all_players_wait_percent or 0])
                local seconds = ParseList(fields[columns.all_players_total_wait_seconds or 0])
                local worst = fields[columns.worst_player or 0]
                for name in pairs(players) do
                    local entry = scores[name] or {total = 0, worstGames = 0, games = 0}
                    scores[name] = entry
                    entry.games = entry.games + 1
                end
                if worst and worst ~= '' and scores[worst] then
                    local wait = seconds[worst]
                    if not wait then
                        wait = minutes * 60 * (tonumber(fields[columns.worst_wait_percent or 0]) or 0) / 100
                    end
                    scores[worst].total = scores[worst].total + wait
                    scores[worst].worstGames = scores[worst].worstGames + 1
                end
            end
        end
    end
    for _, entry in pairs(scores) do
        entry.average = entry.games > 0 and entry.total / entry.games or 0
    end
    return scores
end

function Format(entry)
    if not entry then return nil end
    return string.format('lag %.1fs', entry.average)
end

local cache
function Get(name)
    if not cache then
        -- Only engines with the wait log have this function.
        local read = rawget(_G, 'MicrochipReadWaitHistory')
        cache = Parse(read and read() or nil)
    end
    return cache[name]
end

function Reset() cache = nil end
