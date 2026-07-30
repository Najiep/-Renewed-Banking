lib.locale()

Config = {
    -- Framework automatically detected.
    -- QB, QBX, and ESX are preconfigured. Edit server/framework.lua to add another framework.
    renewedMultiJob = false, -- QBCore only: https://github.com/Renewed-Scripts/qb-phone
    progressbar = 'circle', -- circle or rectangle
    currency = 'USD',

    security = {
        auditEnabled = true,
        minimumTransactionAmount = 1,
        maximumTransactionAmount = 100000000,
        requireWholeAmounts = true,
        maximumCommentLength = 160,
        minimumAccountIdLength = 3,
        maximumAccountIdLength = 50,
        accountIdPattern = '^[a-z0-9][a-z0-9_-]*$',
        maximumSharedAccountsPerPlayer = 5,
        defaultActionCooldown = 750,
        duplicateRequestWindow = 1500,
        actionCooldowns = {
            initialize = 500,
            deposit = 750,
            withdraw = 750,
            transfer = 1000,
            createAccount = 2000,
            listAccounts = 500,
            viewMembers = 500,
            addMember = 1000,
            removeMember = 1000,
            deleteAccount = 1500,
            renameAccount = 1000,
            giveCash = 750
        },
        reservedAccountIds = {
            personal = true,
            system = true,
            admin = true,
            bank = true,
            cash = true
        }
    },

    atms = {
        `prop_atm_01`,
        `prop_atm_02`,
        `prop_atm_03`,
        `prop_fleeca_atm`
    },

    peds = {
        [1] = {
            model = 'u_m_m_bankman',
            coords = vector4(241.44, 227.19, 106.29, 170.43),
            createAccounts = true
        },
        [2] = {
            model = 'ig_barry',
            coords = vector4(313.84, -280.58, 54.16, 338.31)
        },
        [3] = {
            model = 'ig_barry',
            coords = vector4(149.46, -1042.09, 29.37, 335.43)
        },
        [4] = {
            model = 'ig_barry',
            coords = vector4(-351.23, -51.28, 49.04, 341.73)
        },
        [5] = {
            model = 'ig_barry',
            coords = vector4(-1211.9, -331.9, 37.78, 20.07)
        },
        [6] = {
            model = 'ig_barry',
            coords = vector4(-2961.14, 483.09, 15.7, 83.84)
        },
        [7] = {
            model = 'ig_barry',
            coords = vector4(1174.8, 2708.2, 38.09, 178.52)
        },
        [8] = {
            model = 'u_m_m_bankman',
            coords = vector4(-112.22, 6471.01, 31.63, 134.18),
            createAccounts = true
        }
    }
}
