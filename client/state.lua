RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Client = RB.Client or {}
RB.Client.state = {
    open = false,
    context = nil,
    initialized = false
}

function RB.Client.setFocus(value)
    RB.Client.state.open = value == true
    SetNuiFocus(RB.Client.state.open, RB.Client.state.open)
    SetNuiFocusKeepInput(false)
end

function RB.Client.close()
    RB.Client.setFocus(false)
    RB.Client.state.context = nil
    SendNUIMessage({ type = 'renewedBanking:close' })
end
