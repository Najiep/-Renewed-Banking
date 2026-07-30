RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

local callbacks = {
    getSession = 'Renewed-Banking:server:v3:getSession',
    deposit = 'Renewed-Banking:server:v3:deposit',
    withdraw = 'Renewed-Banking:server:v3:withdraw',
    transfer = 'Renewed-Banking:server:v3:transfer',
    transactions = 'Renewed-Banking:server:v3:transactions',
    createAccount = 'Renewed-Banking:server:v3:createAccount',
    listMembers = 'Renewed-Banking:server:v3:listMembers',
    addMember = 'Renewed-Banking:server:v3:addMember',
    removeMember = 'Renewed-Banking:server:v3:removeMember',
    renameAccount = 'Renewed-Banking:server:v3:renameAccount',
    closeAccount = 'Renewed-Banking:server:v3:closeAccount'
}

local function respond(cb, result)
    cb(result or RB.Result.fail(RB.Errors.SERVICE_UNAVAILABLE))
end

RegisterNUICallback('closeInterface', function(_, cb)
    RB.Client.close()
    cb({ ok = true })
end)

for nuiName, serverName in pairs(callbacks) do
    RegisterNUICallback(nuiName, function(data, cb)
        local ok, result = pcall(function()
            return lib.callback.await(serverName, false, data or {})
        end)
        if not ok then
            respond(cb, RB.Result.fail(RB.Errors.SERVICE_UNAVAILABLE))
            return
        end
        respond(cb, result)
    end)
end

function RB.Client.open(context)
    if RB.Client.state.open then return end
    RB.Client.state.context = context or { type = 'bank' }
    local session = lib.callback.await('Renewed-Banking:server:v3:getSession', false, {})
    if not session or not session.ok then
        lib.notify({ title = locale('bank_name'), description = locale('loading_failed'), type = 'error' })
        return
    end
    RB.Client.setFocus(true)
    SendNUIMessage({
        type = 'renewedBanking:open',
        payload = {
            session = session.data,
            context = RB.Client.state.context,
            locale = lib.getLocales(),
            version = RB.VERSION
        }
    })
end

RegisterNetEvent('Renewed-Banking:client:v3:open', function(context)
    local ped = cache.ped
    local label = context and context.type == 'atm' and locale('open_atm') or locale('open_bank')
    if context and context.type == 'atm' then TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true) end
    local progress = Config.interaction.progress
    local fn = progress.style == 'circle' and lib.progressCircle or lib.progressBar
    local completed = fn({
        label = label,
        duration = math.random(progress.durationMin, progress.durationMax),
        position = 'bottom',
        canCancel = true,
        useWhileDead = false,
        allowCuffed = false,
        disable = { car = true, move = true, combat = true }
    })
    ClearPedTasksImmediately(ped)
    if completed then RB.Client.open(context) end
end)

RegisterCommand('closeBankUI', RB.Client.close, false)
