lib.locale()

Config = {
    framework = 'auto', -- auto | esx | qb | qbx
    currency = { code = 'USD', symbol = '$', precision = 0 },

    v3 = {
        enabled = true,
        autoMigrateSchema = true,
        autoImportV2 = false,
        requireExplicitLegacyImport = true,
        migrationFiles = { 'migrations/001_v3_schema.sql' },
        statementPageSize = 30,
        maximumStatementPageSize = 100,
        idempotencyTtlSeconds = 86400,
        processingTimeoutSeconds = 30,
        lockTimeoutMs = 5000,
        settlementRetryLimit = 5
    },

    permissions = {
        adminAce = 'renewedbanking.admin',
        esx = {
            mode = 'gradeName',
            bossGradeNames = { boss = true },
            minimumGrades = {},
            allowedGrades = {}
        },
        qb = {
            mode = 'isboss',
            minimumGrades = {},
            allowedGrades = {}
        },
        qbx = {
            mode = 'nativeBoss',
            minimumGrades = {},
            allowedGrades = {}
        },
        sharedRoles = {
            owner = { view = true, deposit = true, withdraw = true, transfer = true, members = true, rename = true, close = true },
            admin = { view = true, deposit = true, withdraw = true, transfer = true, members = true, rename = true, close = false },
            operator = { view = true, deposit = true, withdraw = true, transfer = true, members = false, rename = false, close = false },
            viewer = { view = true, deposit = false, withdraw = false, transfer = false, members = false, rename = false, close = false }
        }
    },

    security = {
        auditEnabled = true,
        redactIdentifiers = true,
        minimumTransactionAmount = 1,
        maximumTransactionAmount = 100000000,
        requireWholeAmounts = true,
        maximumCommentLength = 160,
        minimumAccountIdLength = 3,
        maximumAccountIdLength = 50,
        accountIdPattern = '^[a-z0-9][a-z0-9_-]*$',
        maximumSharedAccountsPerPlayer = 5,
        actionCooldowns = {
            session = 350,
            statement = 350,
            deposit = 750,
            withdraw = 750,
            transfer = 1000,
            createAccount = 2500,
            listMembers = 500,
            addMember = 1000,
            removeMember = 1000,
            renameAccount = 1000,
            closeAccount = 1500
        },
        reservedAccountIds = {
            personal = true, system = true, admin = true, bank = true,
            cash = true, migration = true
        }
    },

    compatibility = {
        renewedV2Exports = true,
        allowAnyInvokingResource = false,
        allowedResources = {
            ['qb-core'] = true,
            ['qbx_core'] = true,
            ['es_extended'] = true,
            ['esx_society'] = true,
            ['qb-management'] = true
        },
        qbManagementProvider = false,
        esxSocietyProvider = false
    },

    logging = {
        level = 'info',
        discordWebhook = '',
        queueLimit = 200,
        retryDelayMs = 5000
    },

    interaction = {
        useOxTarget = true,
        fallbackTextUi = true,
        targetDistance = 2.5,
        pedSpawnDistance = 120.0,
        progress = { style = 'circle', durationMin = 1200, durationMax = 2200 },
        atmCapabilities = { deposit = false, withdraw = true, transfer = true, createSharedAccount = false },
        bankCapabilities = { deposit = true, withdraw = true, transfer = true, createSharedAccount = true }
    },

    atms = { joaat('prop_atm_01'), joaat('prop_atm_02'), joaat('prop_atm_03'), joaat('prop_fleeca_atm') },

    locations = {
        { id = 'pacific', model = 'u_m_m_bankman', coords = vector4(241.44, 227.19, 106.29, 170.43), createAccounts = true, blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } },
        { id = 'hawick', model = 'ig_barry', coords = vector4(313.84, -280.58, 54.16, 338.31), blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } },
        { id = 'legion', model = 'ig_barry', coords = vector4(149.46, -1042.09, 29.37, 335.43), blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } },
        { id = 'rockford', model = 'ig_barry', coords = vector4(-351.23, -51.28, 49.04, 341.73), blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } },
        { id = 'vespucci', model = 'ig_barry', coords = vector4(-1211.9, -331.9, 37.78, 20.07), blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } },
        { id = 'great_ocean', model = 'ig_barry', coords = vector4(-2961.14, 483.09, 15.7, 83.84), blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } },
        { id = 'harmony', model = 'ig_barry', coords = vector4(1174.8, 2708.2, 38.09, 178.52), blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } },
        { id = 'paleto', model = 'u_m_m_bankman', coords = vector4(-112.22, 6471.01, 31.63, 134.18), createAccounts = true, blip = { enabled = true, sprite = 108, colour = 2, scale = 0.8 } }
    }
}
