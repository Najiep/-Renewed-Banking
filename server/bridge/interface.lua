RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.BridgeFactories = RB.BridgeFactories or {}

local requiredMethods = {
    'getName', 'isReady', 'getPlayerBySource', 'getOnlinePlayerByIdentifier',
    'getIdentifier', 'getCharacterName', 'getMoney', 'addMoney', 'removeMoney',
    'getGroups', 'hasGroupAccountPermission', 'notify', 'isPlayerLoaded',
    'isDead', 'supportsOfflineMoney', 'getDefinedGroups'
}

function RB.ValidateBridge(bridge)
    if type(bridge) ~= 'table' then return false, 'bridge is not a table' end
    for _, method in ipairs(requiredMethods) do
        if type(bridge[method]) ~= 'function' then
            return false, ('bridge missing %s'):format(method)
        end
    end
    return true
end
