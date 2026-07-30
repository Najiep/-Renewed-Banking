RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.BridgeFactories.qb = function()
    local QBCore = exports['qb-core']:GetCoreObject()
    local bridge = {}

    local function gradeData(groupType, groupName, grade)
        local source = groupType == RB.AccountTypes.GANG and QBCore.Shared.Gangs or QBCore.Shared.Jobs
        local group = source and source[groupName]
        if not group or not group.grades then return nil end
        return group.grades[tostring(grade)] or group.grades[tonumber(grade)]
    end

    function bridge.getName() return 'qb' end
    function bridge.isReady() return QBCore ~= nil end
    function bridge.getPlayerBySource(source) return QBCore.Functions.GetPlayer(tonumber(source)) end
    function bridge.getOnlinePlayerByIdentifier(identifier)
        return QBCore.Functions.GetPlayerByCitizenId(identifier:upper())
    end
    function bridge.getIdentifier(player) return player and player.PlayerData and player.PlayerData.citizenid end
    function bridge.getCharacterName(player)
        local info = player and player.PlayerData and player.PlayerData.charinfo or {}
        return (('%s %s'):format(info.firstname or 'Unknown', info.lastname or '')):gsub('%s+$', '')
    end
    function bridge.getMoney(player, moneyType)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        return RB.Result.ok(tonumber(player.Functions.GetMoney(moneyType)) or 0)
    end
    function bridge.addMoney(player, moneyType, amount, reason)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        local ok = player.Functions.AddMoney(moneyType, amount, reason)
        return ok == false and RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED) or RB.Result.ok(true)
    end
    function bridge.removeMoney(player, moneyType, amount, reason)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        if (tonumber(player.Functions.GetMoney(moneyType)) or 0) < amount then
            return RB.Result.fail(RB.Errors.INSUFFICIENT_FUNDS)
        end
        local ok = player.Functions.RemoveMoney(moneyType, amount, reason)
        return ok == false and RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED) or RB.Result.ok(true)
    end
    function bridge.getGroups(source)
        local player = bridge.getPlayerBySource(source)
        if not player or not player.PlayerData then return {} end
        local result = {}
        local job = player.PlayerData.job
        local gang = player.PlayerData.gang
        if job and job.name and job.name ~= 'unemployed' then
            result[#result + 1] = { type = RB.AccountTypes.JOB, name = job.name, grade = job.grade and job.grade.level or 0 }
        end
        if gang and gang.name and gang.name ~= 'none' then
            result[#result + 1] = { type = RB.AccountTypes.GANG, name = gang.name, grade = gang.grade and gang.grade.level or 0 }
        end
        return result
    end
    function bridge.hasGroupAccountPermission(source, groupType, groupName)
        local player = bridge.getPlayerBySource(source)
        if not player or not player.PlayerData then return false end
        local group = groupType == RB.AccountTypes.GANG and player.PlayerData.gang or player.PlayerData.job
        if not group or group.name ~= groupName then return false end
        local cfg = Config.permissions.qb
        local grade = group.grade and group.grade.level or 0
        local data = gradeData(groupType, groupName, grade)
        if cfg.mode == 'minimumGrade' then return grade >= (cfg.minimumGrades[groupName] or math.huge) end
        if cfg.mode == 'allowlist' then
            local allowed = cfg.allowedGrades[groupName] or {}
            return allowed[grade] == true or allowed[tostring(grade)] == true
        end
        return data and data.isboss == true or group.isboss == true
    end
    function bridge.notify(source, payload) TriggerClientEvent('ox_lib:notify', source, payload) end
    function bridge.isPlayerLoaded(source) return bridge.getPlayerBySource(source) ~= nil end
    function bridge.isDead(source)
        local player = bridge.getPlayerBySource(source)
        return player and player.PlayerData and player.PlayerData.metadata and player.PlayerData.metadata.isdead == true or false
    end
    function bridge.supportsOfflineMoney() return false end
    function bridge.getDefinedGroups()
        local result = {}
        for name, data in pairs(QBCore.Shared.Jobs or {}) do
            result[#result + 1] = { type = RB.AccountTypes.JOB, name = name, label = data.label or name }
        end
        for name, data in pairs(QBCore.Shared.Gangs or {}) do
            result[#result + 1] = { type = RB.AccountTypes.GANG, name = name, label = data.label or name }
        end
        return result
    end
    return bridge
end
