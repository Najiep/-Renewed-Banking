RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

local detected = {}
if GetResourceState('es_extended') == 'started' then detected[#detected + 1] = 'esx' end
if GetResourceState('qb-core') == 'started' then detected[#detected + 1] = 'qb' end
if GetResourceState('qbx_core') == 'started' then detected[#detected + 1] = 'qbx' end

local selected = Config.framework
if selected == 'auto' then
    if #detected ~= 1 then
        error(('[Renewed-Banking] Expected exactly one supported framework, detected: %s. Set Config.framework explicitly.'):format(table.concat(detected, ', ')))
    end
    selected = detected[1]
end

if not RB.BridgeFactories[selected] then error(('[Renewed-Banking] Unsupported framework: %s'):format(tostring(selected))) end
RB.Bridge = RB.BridgeFactories[selected]()
local valid, reason = RB.ValidateBridge(RB.Bridge)
if not valid then error(('[Renewed-Banking] Invalid bridge: %s'):format(reason)) end
if not RB.Bridge.isReady() then error(('[Renewed-Banking] Framework bridge %s is not ready'):format(selected)) end
RB.Logger.info('framework_ready', { framework = selected })
