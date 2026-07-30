local Framework = GetResourceState('es_extended') == 'started' and 'esx'
    or GetResourceState('qbx_core') == 'started' and 'qbx'
    or GetResourceState('qb-core') == 'started' and 'qb'
    or 'Unknown'

local QBCore, ESX, Jobs, Gangs = nil, nil, nil, nil
local deadPlayers = {}

function GetFrameworkName()
    return Framework
end

CreateThread(function()
    if Framework == 'Unknown' then
        print('^1[Renewed-Banking]^0 Unsupported framework detected. Stopping resource.')
        return StopResource(GetCurrentResourceName())
    end

    if Framework == 'qb' then
        QBCore = exports['qb-core']:GetCoreObject()
        Jobs = QBCore.Shared.Jobs or {}
        Gangs = QBCore.Shared.Gangs or {}

        ExportHandler('qb-management', 'GetAccount', GetAccountMoney)
        ExportHandler('qb-management', 'GetGangAccount', GetAccountMoney)
        ExportHandler('qb-management', 'AddMoney', AddAccountMoney)
        ExportHandler('qb-management', 'AddGangMoney', AddAccountMoney)
        ExportHandler('qb-management', 'RemoveMoney', RemoveAccountMoney)
        ExportHandler('qb-management', 'RemoveGangMoney', RemoveAccountMoney)
    elseif Framework == 'qbx' then
        Jobs = exports.qbx_core:GetJobs() or {}
        Gangs = exports.qbx_core:GetGangs() or {}

        ExportHandler('qb-management', 'GetAccount', GetAccountMoney)
        ExportHandler('qb-management', 'GetGangAccount', GetAccountMoney)
        ExportHandler('qb-management', 'AddMoney', AddAccountMoney)
        ExportHandler('qb-management', 'AddGangMoney', AddAccountMoney)
        ExportHandler('qb-management', 'RemoveMoney', RemoveAccountMoney)
        ExportHandler('qb-management', 'RemoveGangMoney', RemoveAccountMoney)
    elseif Framework == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
        ESX.RefreshJobs()
        Jobs = ESX.GetJobs() or {}
        Gangs = {}

        ExportHandler('esx_society', 'GetSociety', GetAccountMoney)

        -- Keep society compatibility server-local. Registering these as network
        -- events would let an untrusted client request direct balance changes.
        AddEventHandler('esx_society:getSociety', GetAccountMoney)
        AddEventHandler('esx_society:depositMoney', AddAccountMoney)
        AddEventHandler('esx_society:withdrawMoney', RemoveAccountMoney)
    end
end)

function GetSocietyLabel(society)
    if Framework == 'qb' then
        return Jobs[society] and Jobs[society].label
            or Gangs[society] and Gangs[society].label
            or society
    elseif Framework == 'qbx' then
        return Jobs[society] and Jobs[society].label
            or Gangs[society] and Gangs[society].label
            or society
    elseif Framework == 'esx' then
        return Jobs[society] and Jobs[society].label or society
    end

    return society
end

function GetPlayerObject(source)
    source = tonumber(source)
    if not source then return nil end

    if Framework == 'qb' then
        return QBCore.Functions.GetPlayer(source)
    elseif Framework == 'qbx' then
        return exports.qbx_core:GetPlayer(source)
    elseif Framework == 'esx' then
        return ESX.GetPlayerFromId(source)
    end
end

function GetPlayerObjectFromID(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return nil end

    if Framework == 'qb' then
        return QBCore.Functions.GetPlayerByCitizenId(identifier:upper())
    elseif Framework == 'qbx' then
        return exports.qbx_core:GetPlayerByCitizenId(identifier:upper())
    elseif Framework == 'esx' then
        return ESX.GetPlayerFromIdentifier(identifier)
            or ESX.GetPlayerFromIdentifier(identifier:lower())
    end
end

function GetCharacterName(Player)
    if not Player then return nil end

    if Framework == 'qb' or Framework == 'qbx' then
        local charinfo = Player.PlayerData and Player.PlayerData.charinfo or {}
        local name = ('%s %s'):format(charinfo.firstname or 'Unknown', charinfo.lastname or '')
        return (name:gsub('%s+$', ''))
    elseif Framework == 'esx' then
        return Player.getName and Player.getName() or Player.name
    end
end

function GetIdentifier(Player)
    if not Player then return nil end

    if Framework == 'qb' or Framework == 'qbx' then
        return Player.PlayerData and Player.PlayerData.citizenid
    elseif Framework == 'esx' then
        return Player.identifier
    end
end

function GetFunds(Player)
    if not Player then return nil end

    if Framework == 'qb' or Framework == 'qbx' then
        local money = Player.PlayerData and Player.PlayerData.money or {}
        return {
            cash = tonumber(money.cash) or 0,
            bank = tonumber(money.bank) or 0
        }
    elseif Framework == 'esx' then
        local cash = Player.getAccount('money')
        local bank = Player.getAccount('bank')
        return {
            cash = cash and cash.money or 0,
            bank = bank and bank.money or 0
        }
    end
end

function AddMoney(Player, Amount, Type, comment)
    if not Player or type(Amount) ~= 'number' or Amount <= 0 then return false end

    if Framework == 'qb' or Framework == 'qbx' then
        local result = Player.Functions.AddMoney(Type, Amount, comment)
        return result ~= false
    elseif Framework == 'esx' then
        if Type == 'cash' then
            Player.addAccountMoney('money', Amount, comment)
            return true
        elseif Type == 'bank' then
            Player.addAccountMoney('bank', Amount, comment)
            return true
        end
    end

    return false
end

function RemoveMoney(Player, Amount, Type, comment)
    if not Player or type(Amount) ~= 'number' or Amount <= 0 then return false end

    if Framework == 'qb' or Framework == 'qbx' then
        local currentAmount = Player.Functions.GetMoney(Type)
        if currentAmount and currentAmount >= Amount then
            local result = Player.Functions.RemoveMoney(Type, Amount, comment)
            return result ~= false
        end
    elseif Framework == 'esx' then
        local accountName = Type == 'cash' and 'money' or Type
        local account = Player.getAccount(accountName)
        local currentAmount = account and account.money or 0

        if currentAmount >= Amount then
            Player.removeAccountMoney(accountName, Amount, comment)
            return true
        end
    end

    return false
end

function GetJobs(Player)
    if not Player then return {} end

    if Framework == 'qb' or Framework == 'qbx' then
        if Config.renewedMultiJob and GetResourceState('qb-phone') == 'started' then
            local jobs = exports['qb-phone']:getJobs(Player.PlayerData.citizenid) or {}
            local result = {}

            for name, data in pairs(jobs) do
                result[#result + 1] = {
                    name = name,
                    grade = tostring(data.grade)
                }
            end

            return result
        end

        local job = Player.PlayerData and Player.PlayerData.job
        if not job then return {} end

        return {
            name = job.name,
            grade = tostring(job.grade and job.grade.level or 0)
        }
    elseif Framework == 'esx' then
        if not Player.job then return {} end

        return {
            name = Player.job.name,
            grade = tostring(Player.job.grade)
        }
    end

    return {}
end

function GetGang(Player)
    if not Player then return false end

    if Framework == 'qb' or Framework == 'qbx' then
        return Player.PlayerData and Player.PlayerData.gang and Player.PlayerData.gang.name or false
    end

    return false
end

function IsJobAuth(job, grade)
    if type(job) ~= 'string' or not Jobs or not Jobs[job] or not Jobs[job].grades then
        return false
    end

    local stringGrade = tostring(grade)
    local numberGrade = tonumber(grade)
    local gradeData = Jobs[job].grades[stringGrade] or (numberGrade and Jobs[job].grades[numberGrade])

    if not gradeData then return false end

    if Framework == 'qb' or Framework == 'qbx' then
        if gradeData.bankAuth ~= nil then
            return gradeData.bankAuth == true
        end

        return gradeData.isboss == true
    elseif Framework == 'esx' then
        return gradeData.name == 'boss'
    end

    return false
end

function IsGangAuth(Player, gang)
    if (Framework ~= 'qb' and Framework ~= 'qbx') or not Player or not Gangs or not Gangs[gang] then
        return false
    end

    local gangData = Player.PlayerData and Player.PlayerData.gang
    local grade = gangData and gangData.grade and gangData.grade.level
    if grade == nil or not Gangs[gang].grades then return false end

    local stringGrade = tostring(grade)
    local numberGrade = tonumber(grade)
    local gradeData = Gangs[gang].grades[stringGrade] or (numberGrade and Gangs[gang].grades[numberGrade])

    if not gradeData then return false end

    if gradeData.bankAuth ~= nil then
        return gradeData.bankAuth == true
    end

    return gradeData.isboss == true
end

function Notify(source, settings)
    TriggerClientEvent('ox_lib:notify', source, settings)
end

function IsDead(Player)
    if not Player then return false end

    if Framework == 'qb' or Framework == 'qbx' then
        return Player.PlayerData and Player.PlayerData.metadata and Player.PlayerData.metadata.isdead == true
    elseif Framework == 'esx' then
        return deadPlayers[Player.source] == true
    end

    return false
end

function GetFrameworkGroups()
    return Jobs or {}, Gangs or {}
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    if not Player or not Player.PlayerData then return end
    UpdatePlayerAccount(Player.PlayerData.citizenid)
end)

RegisterNetEvent('esx:onPlayerDeath', function()
    deadPlayers[source] = true
end)

RegisterNetEvent('esx:onPlayerSpawn', function()
    local Player = GetPlayerObject(source)
    if not Player then return end

    local cid = GetIdentifier(Player)
    deadPlayers[source] = nil

    if cid then
        UpdatePlayerAccount(cid)
    end
end)

AddEventHandler('playerDropped', function()
    deadPlayers[source] = nil
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    CreateThread(function()
        Wait(250)

        for _, playerId in ipairs(GetPlayers()) do
            local Player = GetPlayerObject(playerId)
            local cid = Player and GetIdentifier(Player)

            if cid then
                UpdatePlayerAccount(cid)
            end
        end
    end)
end)
