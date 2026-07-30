RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.BridgeFactories.qbx = function()
    local bridge = {}

    local function exportCall(name, ...)
        local args = { ... }
        local ok, value = pcall(function() return exports.qbx_core[name](exports.qbx_core, table.unpack(args)) end)
        if ok then return value end
        ok, value = pcall(function() return exports.qbx_core[name](table.unpack(args)) end)
        if ok then return value end
        return nil
    end

    function bridge.getName() return 'qbx' end
    function bridge.isReady() return GetResourceState('qbx_core') == 'started' end
    function bridge.getPlayerBySource(source) return exportCall('GetPlayer', tonumber(source)) end
    function bridge.getOnlinePlayerByIdentifier(identifier) return exportCall('GetPlayerByCitizenId', identifier:upper()) end
    function bridge.getIdentifier(player) return player and player.PlayerData and player.PlayerData.citizenid end
    function bridge.getCharacterName(player)
        local info = player and player.PlayerData and player.PlayerData.charinfo or {}
        return (('%s %s'):format(info.firstname or 'Unknown', info.lastname or '')):gsub('%s+$', '')
    end
    function bridge.getMoney(player, moneyType)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        local identifier = bridge.getIdentifier(player)
        local value = exportCall('GetMoney', identifier, moneyType)
        if value == nil and player.Functions and player.Functions.GetMoney then value = player.Functions.GetMoney(moneyType) end
        return RB.Result.ok(tonumber(value) or 0)
    end
    function bridge.addMoney(player, moneyType, amount, reason)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        local identifier = bridge.getIdentifier(player)
        local value = exportCall('AddMoney', identifier, moneyType, amount, reason)
        if value == nil and player.Functions and player.Functions.AddMoney then value = player.Functions.AddMoney(moneyType, amount, reason) end
        return value == false and RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED) or RB.Result.ok(true)
    end
    function bridge.removeMoney(player, moneyType, amount, reason)
        if not player then return RB.Result.fail(RB.Errors.PLAYER_NOT_LOADED) end
        local current = bridge.getMoney(player, moneyType)
        if not current.ok or current.data < amount then return RB.Result.fail(RB.Errors.INSUFFICIENT_FUNDS) end
        local identifier = bridge.getIdentifier(player)
        local value = exportCall('RemoveMoney', identifier, moneyType, amount, reason)
        if value == nil and player.Functions and player.Functions.RemoveMoney then value = player.Functions.RemoveMoney(moneyType, amount, reason) end
        return value == false and RB.Result.fail(RB.Errors.FRAMEWORK_OPERATION_FAILED) or RB.Result.ok(true)
    end
    function bridge.getGroups(source)
        local groups = exportCall('GetGroups', tonumber(source)) or {}
        local result = {}
        for name, grade in pairs(groups) do
            local groupType = (exportCall('GetGangs') or {})[name] and RB.AccountTypes.GANG or RB.AccountTypes.JOB
            if type(grade) == 'table' then grade = grade.grade or grade.level or 0 end
            result[#result + 1] = { type = groupType, name = name, grade = tonumber(grade) or 0 }
        end
        if #result == 0 then
            local player = bridge.getPlayerBySource(source)
            if player and player.PlayerData then
                local job = player.PlayerData.job
                local gang = player.PlayerData.gang
                if job and job.name and job.name ~= 'unemployed' then result[#result + 1] = { type = RB.AccountTypes.JOB, name = job.name, grade = job.grade and job.grade.level or 0 } end
                if gang and gang.name and gang.name ~= 'none' then result[#result + 1] = { type = RB.AccountTypes.GANG, name = gang.name, grade = gang.grade and gang.grade.level or 0 } end
            end
        end
        return result
    end
    function bridge.hasGroupAccountPermission(source, groupType, groupName)
        local groups = bridge.getGroups(source)
        local grade
        for _, group in ipairs(groups) do
            if group.type == groupType and group.name == groupName then grade = group.grade break end
        end
        if grade == nil then return false end
        local cfg = Config.permissions.qbx
        if cfg.mode == 'minimumGrade' then return grade >= (cfg.minimumGrades[groupName] or math.huge) end
        if cfg.mode == 'allowlist' then
            local allowed = cfg.allowedGrades[groupName] or {}
            return allowed[grade] == true or allowed[tostring(grade)] == true
        end
        local value = exportCall('IsGradeBoss', groupName, grade)
        return value == true
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
        for name, data in pairs(exportCall('GetJobs') or {}) do result[#result + 1] = { type = RB.AccountTypes.JOB, name = name, label = data.label or name } end
        for name, data in pairs(exportCall('GetGangs') or {}) do result[#result + 1] = { type = RB.AccountTypes.GANG, name = name, label = data.label or name } end
        return result
    end
    return bridge
end
