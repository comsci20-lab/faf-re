-- Lag scores for the lobby from %LOCALAPPDATA%\Microchip\faf-lag\game-waits.csv
-- (written by this engine). A player's score is the wait they caused in the games where they
-- were the worst, as a percentage of all game time recorded with them.
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

-- Games shorter than this are skipped: their wait is mostly the stalls of the first minute.
MIN_GAME_MINUTES = 5
-- Everyone starts with this much lag-free time, so one game cannot give an extreme score.
PRIOR_MINUTES = 30

local function Percent(total, seconds)
    return total * 100 / (seconds + PRIOR_MINUTES * 60)
end

-- Returns {[key] = {percent = n, total = s, seconds = s, worstGames = n, games = n}}, keyed by
-- 'id:<FAF id>' when the row recorded the player's ID, otherwise by 'name:<name>' (rows before IDs).
-- percent = wait caused in games where the player was the worst / all game time played with them,
-- so a long game weighs as much as its length and a short one as little, instead of one game each.
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
                if minutes < MIN_GAME_MINUTES then fields = {} end
                local players = ParseList(fields[columns.all_players_wait_percent or 0])
                local seconds = ParseList(fields[columns.all_players_total_wait_seconds or 0])
                local ids = ParseList(fields[columns.player_ids or 0])
                local worst = fields[columns.worst_player or 0]
                local function Key(name)
                    local id = ids[name]
                    if id and id > 0 then return 'id:' .. string.format('%d', id) end
                    return 'name:' .. name
                end
                for name in pairs(players) do
                    local key = Key(name)
                    local entry = scores[key] or {total = 0, seconds = 0, worstGames = 0, games = 0}
                    scores[key] = entry
                    entry.games = entry.games + 1
                    entry.seconds = entry.seconds + minutes * 60
                end
                if worst and worst ~= '' and scores[Key(worst)] then
                    local wait = seconds[worst]
                    if not wait then
                        wait = minutes * 60 * (tonumber(fields[columns.worst_wait_percent or 0]) or 0) / 100
                    end
                    local entry = scores[Key(worst)]
                    entry.total = entry.total + wait
                    entry.worstGames = entry.worstGames + 1
                end
            end
        end
    end
    for _, entry in pairs(scores) do
        entry.percent = Percent(entry.total, entry.seconds)
        entry.per10 = entry.percent * 6 -- seconds of wait per 10 minutes of game time
    end
    return scores
end

local cache
-- Combines games recorded under the player's FAF ID with older games recorded only by name.
function Get(name, id)
    if not cache then
        -- Only engines with the wait log have this function.
        local read = rawget(_G, 'MicrochipReadWaitHistory')
        cache = Parse(read and read() or nil)
    end
    local byId = id and cache['id:' .. tostring(id)]
    local byName = name and cache['name:' .. name]
    if not byId then return byName end
    if not byName then return byId end
    local seconds = byId.seconds + byName.seconds
    local total = byId.total + byName.total
    return {total = total, seconds = seconds, games = byId.games + byName.games,
            worstGames = byId.worstGames + byName.worstGames,
            percent = Percent(total, seconds), per10 = Percent(total, seconds) * 6}
end

function Reset() cache = nil end
