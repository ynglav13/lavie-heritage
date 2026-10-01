-- Quyền tích lũy: level cao kế thừa tất cả quyền của level thấp hơn
Permissions = {}

local levelPerms = {
    [1] = {
        'getinfo', 'goto', 'gethere', 'spectate', 'admins', 'players', 'ahelp', 'nametags',
    },
    [2] = {
        'kick', 'warn', 'freeze', 'logout', 'agetcar', 'givekeys', 'revive', 'checkinv', 'apanel', 'fixveh',
    },
    [3] = {
        'jail', 'unjail', 'revive', 'setinjury', 'setjob',
        'checkinv', 'setmoney', 'spawnveh', 'deleteveh', 'fixveh',
        'noclip', 'god', 'invisible', 'setped',
    },
    [4] = {
        'ban', 'kick', 'unban', 'clearwarns', 'setlevel', 'manageban', 'announce', 'managegiftcodes', 'turf', 'giveitem',
    },
    [5] = {
        'setrankname', 'setconfig', '*',
    },
}

local cumulativePerms = {}
do
    local accumulated = {}
    for lvl = 1, Config.MaxAdminLevel do
        if levelPerms[lvl] then
            for _, perm in ipairs(levelPerms[lvl]) do
                accumulated[perm] = true
            end
        end
        cumulativePerms[lvl] = {}
        for p, _ in pairs(accumulated) do
            cumulativePerms[lvl][p] = true
        end
    end
end

---@param level number
---@param action string
---@return boolean
function Permissions.Has(level, action)
    if level <= 0 then return false end
    if level == 2 or level == 3 then
        local allowedActions = {
            ['goto'] = true,
            ['agoto'] = true,
            ['gethere'] = true,
            ['agethere'] = true,
            ['spectate'] = true,
            ['spec'] = true,
            ['aspectate'] = true,
            ['agetcar'] = true,
            ['givekeys'] = true,
            ['nametags'] = true,
            ['revive'] = true,
            ['checkinv'] = true,
            ['apanel'] = true,
            ['admins'] = true,
            ['players'] = true,
            ['kick'] = true,
            ['jail'] = true,
            ['unjail'] = true,
            ['unjailic'] = true,
            ['fixtime'] = true,
            ['noclip'] = true,
            ['ahelp'] = true,
            ['getinfo'] = true,
            ['freeze'] = true,
            ['warn'] = true,
            ['afix'] = true,
            ['fixveh'] = true,
        }
        return allowedActions[action] == true
    end
    if level >= Config.MaxAdminLevel then return true end
    local perms = cumulativePerms[level]
    if not perms then return false end
    return perms[action] == true or perms['*'] == true
end

---@param level number
---@return table
function Permissions.GetAll(level)
    if level == 2 or level == 3 then
        return {
            'goto', 'gethere', 'spectate', 'agetcar', 'givekeys',
            'nametags', 'revive', 'checkinv', 'apanel', 'admins',
            'players', 'noclip', 'kick', 'jail', 'unjail',
            'ahelp', 'getinfo', 'freeze', 'warn', 'fixveh',
        }
    end
    if level >= Config.MaxAdminLevel then return { '*' } end
    local result = {}
    if cumulativePerms[level] then
        for p, _ in pairs(cumulativePerms[level]) do
            result[#result + 1] = p
        end
    end
    return result
end

---@param level number
---@return string
function Permissions.GetLevelName(level)
    -- RankNameCache được load từ DB ở server/main.lua
    if IsDuplicityVersion then
        return (RankNameCache and RankNameCache[level]) or Config.DefaultLevelNames[level] or ('Level ' .. level)
    end
    return Config.DefaultLevelNames[level] or ('Level ' .. level)
end
