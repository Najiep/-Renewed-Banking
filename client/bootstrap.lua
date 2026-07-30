RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

CreateThread(function()
    Wait(250)
    RB.Client.close()
    RB.Client.interactions.initialize()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    RB.Client.close()
    RB.Client.interactions.cleanup()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    RB.Client.close()
    RB.Client.interactions.cleanup()
end)

AddEventHandler('esx:onPlayerLogout', function()
    RB.Client.close()
    RB.Client.interactions.cleanup()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    RB.Client.interactions.initialize()
end)

RegisterNetEvent('esx:playerLoaded', function()
    RB.Client.interactions.initialize()
end)

AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, value)
    if value then RB.Client.interactions.initialize() else RB.Client.close(); RB.Client.interactions.cleanup() end
end)
