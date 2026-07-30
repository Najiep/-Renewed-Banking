local root = (... and ... ~= '') and ... or '.'

Config = {
    currency = { code = 'USD', symbol = '$', precision = 0 },
    security = {
        minimumTransactionAmount = 1,
        maximumTransactionAmount = 100000000,
        minimumAccountIdLength = 3,
        maximumAccountIdLength = 50,
        accountIdPattern = '^[a-z0-9][a-z0-9_-]*$',
        reservedAccountIds = { personal = true }
    }
}

dofile(root .. '/shared/constants.lua')
dofile(root .. '/shared/result.lua')
dofile(root .. '/shared/money.lua')
dofile(root .. '/shared/validation.lua')

local RB = RenewedBanking
local count = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then io.stderr:write(('FAIL %s: %s\n'):format(name, err)); os.exit(1) end
    count = count + 1
    print('PASS ' .. name)
end

local function equal(actual, expected)
    assert(actual == expected, ('expected %s, got %s'):format(tostring(expected), tostring(actual)))
end

test('whole amount parses', function() local value = RB.Money.parse('1250'); equal(value, 1250) end)
test('zero rejected', function() local value, code = RB.Money.parse('0'); equal(value, nil); equal(code, RB.Errors.INVALID_AMOUNT) end)
test('negative rejected', function() local value = RB.Money.parse('-1'); equal(value, nil) end)
test('fraction rejected at zero precision', function() local value = RB.Money.parse('1.50'); equal(value, nil) end)
test('maximum enforced', function() local value, code = RB.Money.parse('100000001'); equal(value, nil); equal(code, RB.Errors.AMOUNT_TOO_LARGE) end)
test('account key normalized', function() local value = RB.Validation.accountKey('Family_Savings'); equal(value, 'family_savings') end)
test('reserved account rejected', function() local value = RB.Validation.accountKey('personal'); equal(value, nil) end)
test('invalid account characters rejected', function() local value = RB.Validation.accountKey('bad account!'); equal(value, nil) end)
test('request id accepted', function() local value = RB.Validation.requestId('request-1234'); equal(value, 'request-1234') end)
test('control characters removed from text', function() local value = RB.Validation.text('hello\1world', 20, false); equal(value, 'helloworld') end)

print(('Completed %d shared unit tests.'):format(count))
