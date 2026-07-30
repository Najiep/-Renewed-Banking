RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Client.interactions = RB.Client.interactions or {}
local spawnPoints, interactionPoints, peds, blips = {}, {}, {}, {}
local targetAvailable = false
local textOwner = nil

local function capabilities(kind, location)
    if kind == 'atm' then return Config.interaction.atmCapabilities end
    local data = {}
    for key, value in pairs(Config.interaction.bankCapabilities) do data[key] = value end
    if location and location.createAccounts ~= nil then data.createSharedAccount = location.createAccounts == true end
    return data
end

local function open(kind, locationId, location)
    TriggerEvent('Renewed-Banking:client:v3:open', {
        type = kind,
        locationId = locationId,
        capabilities = capabilities(kind, location)
    })
end

local function createBlip(location)
    if not location.blip or location.blip.enabled == false then return end
    local coords = location.coords
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, location.blip.sprite or 108)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, location.blip.scale or 0.8)
    SetBlipColour(blip, location.blip.colour or 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(locale('bank_name'))
    EndTextCommandSetBlipName(blip)
    blips[#blips + 1] = blip
end

local function addPedTarget(ped, location)
    if not targetAvailable then return end
    exports.ox_target:addLocalEntity(ped, {{
        name = 'renewed_banking_v3_bank_' .. location.id,
        icon = 'fa-solid fa-building-columns',
        label = locale('view_bank'),
        distance = Config.interaction.targetDistance,
        onSelect = function() open('bank', location.id, location) end
    }})
end

local function removePedTarget(ped, location)
    if targetAvailable and DoesEntityExist(ped) then
        exports.ox_target:removeLocalEntity(ped, { 'renewed_banking_v3_bank_' .. location.id })
    end
end

local function createSpawnPoint(location)
    local c = location.coords
    local point = lib.points.new({
        coords = vec3(c.x, c.y, c.z),
        distance = Config.interaction.pedSpawnDistance,
        location = location,
        ped = nil
    })

    function point:onEnter()
        lib.requestModel(self.location.model, 10000)
        local coords = self.location.coords
        self.ped = CreatePed(0, joaat(self.location.model), coords.x, coords.y, coords.z - 1.0, coords.w, false, false)
        SetEntityHeading(self.ped, coords.w)
        FreezeEntityPosition(self.ped, true)
        SetEntityInvincible(self.ped, true)
        SetBlockingOfNonTemporaryEvents(self.ped, true)
        TaskStartScenarioInPlace(self.ped, 'PROP_HUMAN_STAND_IMPATIENT', 0, true)
        SetModelAsNoLongerNeeded(joaat(self.location.model))
        peds[self.location.id] = self.ped
        addPedTarget(self.ped, self.location)
    end

    function point:onExit()
        if self.ped then
            removePedTarget(self.ped, self.location)
            if DoesEntityExist(self.ped) then DeletePed(self.ped) end
            peds[self.location.id] = nil
            self.ped = nil
        end
    end

    spawnPoints[#spawnPoints + 1] = point
end

local function createFallbackPoint(location)
    if targetAvailable or not Config.interaction.fallbackTextUi then return end
    local c = location.coords
    local point = lib.points.new({ coords = vec3(c.x, c.y, c.z), distance = 2.5, location = location })

    function point:nearby()
        if textOwner ~= self.location.id then
            if textOwner then lib.hideTextUI() end
            lib.showTextUI(('[E] %s'):format(locale('view_bank')))
            textOwner = self.location.id
        end
        if IsControlJustReleased(0, 38) then open('bank', self.location.id, self.location) end
    end

    function point:onExit()
        if textOwner == self.location.id then lib.hideTextUI(); textOwner = nil end
    end

    interactionPoints[#interactionPoints + 1] = point
end

function RB.Client.interactions.initialize()
    if RB.Client.state.initialized then return end
    targetAvailable = Config.interaction.useOxTarget and GetResourceState('ox_target') == 'started'
    if targetAvailable then
        exports.ox_target:addModel(Config.atms, {{
            name = 'renewed_banking_v3_atm',
            icon = 'fa-solid fa-money-check-dollar',
            label = locale('view_bank'),
            distance = Config.interaction.targetDistance,
            onSelect = function() open('atm', 'atm') end
        }})
    end
    for _, location in ipairs(Config.locations) do
        createSpawnPoint(location)
        createFallbackPoint(location)
        createBlip(location)
    end
    RB.Client.state.initialized = true
end

function RB.Client.interactions.cleanup()
    if textOwner then lib.hideTextUI(); textOwner = nil end
    if targetAvailable then exports.ox_target:removeModel(Config.atms, { 'renewed_banking_v3_atm' }) end
    for _, point in ipairs(spawnPoints) do
        if point.ped then removePedTarget(point.ped, point.location); if DoesEntityExist(point.ped) then DeletePed(point.ped) end end
        point:remove()
    end
    for _, point in ipairs(interactionPoints) do point:remove() end
    for _, blip in ipairs(blips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    spawnPoints, interactionPoints, peds, blips = {}, {}, {}, {}
    RB.Client.state.initialized = false
end
