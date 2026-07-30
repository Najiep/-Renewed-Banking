RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Money = {}
local function pow10(value) local result = 1 for _ = 1, value do result = result * 10 end return result end
function RB.Money.parse(value)
    local precision = tonumber(Config.currency and Config.currency.precision) or 0
    local maxAmount = tonumber(Config.security and Config.security.maximumTransactionAmount) or 100000000
    local minAmount = tonumber(Config.security and Config.security.minimumTransactionAmount) or 1
    if type(value) == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return nil, RB.Errors.INVALID_AMOUNT end
        value = tostring(value)
    elseif type(value) ~= 'string' then return nil, RB.Errors.INVALID_AMOUNT end
    value = value:match('^%s*(.-)%s*$')
    if value == '' or not value:match('^%d+%.?%d*$') then return nil, RB.Errors.INVALID_AMOUNT end
    local whole, fraction = value:match('^(%d+)%.?(%d*)$')
    fraction = fraction or ''
    if #fraction > precision then return nil, RB.Errors.INVALID_AMOUNT end
    while #fraction < precision do fraction = fraction .. '0' end
    local factor = pow10(precision)
    local amount = tonumber(whole) * factor + (tonumber(fraction) or 0)
    if not amount or amount < minAmount then return nil, RB.Errors.INVALID_AMOUNT end
    if amount > maxAmount * factor then return nil, RB.Errors.AMOUNT_TOO_LARGE end
    if amount % 1 ~= 0 then return nil, RB.Errors.INVALID_AMOUNT end
    return amount
end
function RB.Money.toFramework(amount) return amount / pow10(tonumber(Config.currency and Config.currency.precision) or 0) end
function RB.Money.fromFramework(amount)
    local factor = pow10(tonumber(Config.currency and Config.currency.precision) or 0)
    local value = tonumber(amount)
    return value and math.floor(value * factor + 0.5) or nil
end
function RB.Money.format(amount)
    local precision = tonumber(Config.currency and Config.currency.precision) or 0
    local factor = pow10(precision)
    local whole = math.floor(amount / factor)
    if precision == 0 then return tostring(whole) end
    local fraction = tostring(amount % factor)
    return ('%d.%s'):format(whole, string.rep('0', precision - #fraction) .. fraction)
end
