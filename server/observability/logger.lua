RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking

RB.Logger = {}
local queue = {}
local sending = false
local levels = { debug = 1, info = 2, warn = 3, error = 4 }

local function configuredLevel()
    return levels[(Config.logging and Config.logging.level) or 'info'] or 2
end

local function redact(value)
    if value == nil then return nil end
    value = tostring(value)
    if not Config.security.redactIdentifiers or #value <= 8 then return value end
    return value:sub(1, 4) .. '***' .. value:sub(-4)
end

local function normalize(data)
    if type(data) ~= 'table' then return data end
    local copy = {}
    for key, value in pairs(data) do
        if key == 'identifier' or key == 'actor' or key == 'memberIdentifier' then
            copy[key] = redact(value)
        elseif type(value) == 'table' then
            copy[key] = normalize(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function enqueue(level, event, data)
    local webhook = Config.logging and Config.logging.discordWebhook or ''
    if webhook == '' then return end
    local limit = Config.logging.queueLimit or 200
    if #queue >= limit then table.remove(queue, 1) end
    queue[#queue + 1] = {
        username = 'Renewed Banking',
        embeds = {{
            title = event,
            color = level == 'error' and 15158332 or level == 'warn' and 16776960 or 3447003,
            description = ('```json\n%s\n```'):format(json.encode(normalize(data or {}))),
            footer = { text = ('v%s'):format(RB.VERSION) },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }}
    }
end

local function write(level, event, data)
    if (levels[level] or 2) < configuredLevel() then return end
    local payload = normalize(data or {})
    print(('[Renewed-Banking][%s][%s] %s'):format(level:upper(), event, json.encode(payload)))
    enqueue(level, event, payload)
end

function RB.Logger.debug(event, data) write('debug', event, data) end
function RB.Logger.info(event, data) write('info', event, data) end
function RB.Logger.warn(event, data) write('warn', event, data) end
function RB.Logger.error(event, data) write('error', event, data) end
function RB.Logger.redact(value) return redact(value) end

CreateThread(function()
    while true do
        if #queue == 0 then
            Wait(1000)
        else
            local item = table.remove(queue, 1)
            local webhook = Config.logging and Config.logging.discordWebhook or ''
            if webhook ~= '' then
                sending = true
                PerformHttpRequest(webhook, function(status)
                    if status < 200 or status >= 300 then
                        print(('[Renewed-Banking][WARN] Discord webhook returned %s'):format(status))
                    end
                    sending = false
                end, 'POST', json.encode(item), { ['Content-Type'] = 'application/json' })
                while sending do Wait(50) end
            end
        end
    end
end)
