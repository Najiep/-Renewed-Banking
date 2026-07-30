RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.BridgeFactories.esx = function()
    local ESX = exports['es_extended']:getSharedObject()
    local bridge = {}

    function bridge.getName() return 'esx' end
    function bridge.isReady() return ESX ~= nil end
    function bridge.getPlayerBySource(source) return ESX.GetPlayerFromId(tonumber(source)) end
    function bridge.getOnlinePlayerByIdentifier(identifier)
        return ESX.GetPlayerFromIdentifier(identifier) or ESX.GetPlayerFromIdentifier(identifier:lower())
    end
    function bridge.getIdentifier(player) return player and player.identifier end
    function bridge.getCharacterName(player)
        if not player then return nil end
        return player.getName and player.getName() or player.name
    end
    function bridge.getMoney(player, moneyType)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        local accountName = moneyType == 'cash' and 'money' or moneyType
        local account = player.getAccount(accountName)
        return RB.Result.ok(account and tonumber(account.money) or 0)
    end
    function bridge.addMoney(player, moneyType, amount, reason)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        local accountName = moneyType == 'cash' and 'money' or moneyType
        player.addAccountMoney(accountName, amount, reason)
        return RB.Result.ok(true)
    end
    function bridge.removeMoney(player, moneyType, amount, reason)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        local accountName = moneyType == 'cash' and 'money' or moneyType
        local account = player.getAccount(accountName)
        if not account or tonumber(account.money) < amount then
            return RB.Result.fail(RB.Errors.INSUFFICIENT_FUNDS)
        end
        player.removeAccountMoney(accountName, amount, reason)
        return RB.Result.ok(true)
    end
    function bridge.getGroups(source)
        local player = bridge.getPlayerBySource(source)
        if not player or not player.job then return {} end
        return {{ type = RB.AccountTypes.JOB, name = player.job.name, grade = tonumber(player.job.grade) or 0 }}
    end
    function bridge.hasGroupAccountPermission(source, groupType, groupName)
        if groupType ~= RB.AccountTypes.JOB then return false end
        local player = bridge.getPlayerBySource(source)
        if not player or not player.job or player.job.name ~= groupName then return false end
        local cfg = Config.permissions.esx
        local grade = tonumber(player.job.grade) or 0
        local gradeName = tostring(player.job.grade_name or '')
        if cfg.mode == 'minimumGrade' then return grade >= (cfg.minimumGrades[groupName] or math.huge) end
        if cfg.mode == 'allowlist' then
            local allowed = cfg.allowedGrades[groupName] or {}
            return allowed[grade] == true or allowed[tostring(grade)] == true or allowed[gradeName] == true
        end
        return cfg.bossGradeNames[gradeName] == true
    end
    function bridge.notify(source, payload) TriggerClientEvent('ox_lib:notify', source, payload) end
    function bridge.isPlayerLoaded(source) return bridge.getPlayerBySource(source) ~= nil end
    function bridge.isDead(source)
        local player = bridge.getPlayerBySource(source)
        return player and player.getMeta and player.getMeta('dead') == true or false
    end
    function bridge.supportsOfflineMoney() return false end
    function bridge.getDefinedGroups()
        if ESX.RefreshJobs then ESX.RefreshJobs() end
        local jobs = ESX.GetJobs and ESX.GetJobs() or {}
        local result = {}
        for name, data in pairs(jobs) do
            result[#result + 1] = { type = RB.AccountTypes.JOB, name = name, label = data.label or name }
        end
        return result
    end
    return bridge
end
