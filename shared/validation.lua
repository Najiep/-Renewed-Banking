RenewedBanking = RenewedBanking or {}
local RB = RenewedBanking
RB.Validation = {}
function RB.Validation.text(value, maxLength, allowEmpty)
    if value == nil and allowEmpty then return '' end
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%z\1-\8\11\12\14-\31\127]', ''):match('^%s*(.-)%s*$')
    if not allowEmpty and value == '' then return nil end
    if #value > (maxLength or 160) then return nil end
    return value
end
function RB.Validation.accountKey(value)
    if type(value) ~= 'string' then return nil, RB.Errors.INVALID_ACCOUNT_KEY end
    value = value:lower():gsub('%s+', '')
    local security = Config.security or {}
    if #value < (security.minimumAccountIdLength or 3) or #value > (security.maximumAccountIdLength or 50) then return nil, RB.Errors.INVALID_ACCOUNT_KEY end
    if not value:match(security.accountIdPattern or '^[a-z0-9][a-z0-9_-]*$') then return nil, RB.Errors.INVALID_ACCOUNT_KEY end
    if security.reservedAccountIds and security.reservedAccountIds[value] then return nil, RB.Errors.INVALID_ACCOUNT_KEY end
    return value
end
function RB.Validation.requestId(value)
    if type(value) ~= 'string' or #value < 8 or #value > 80 or not value:match('^[%w%-%._:]+$') then return nil, RB.Errors.INVALID_REQUEST_ID end
    return value
end
function RB.Validation.identifier(value)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' or #value > 80 or value:find('[%z\1-\31\127]') then return nil end
    return value
end
function RB.Validation.role(value)
    if value == RB.Roles.OWNER or value == RB.Roles.ADMIN or value == RB.Roles.OPERATOR or value == RB.Roles.VIEWER then return value end
end
function RB.Validation.payload(value) return type(value) == 'table' end
