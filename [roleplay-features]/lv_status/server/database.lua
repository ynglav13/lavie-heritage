CreateThread(function()
    local legacyTable = 'lv_' .. 'fooddrink'
    local legacyExists = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
        {
            legacyTable
        }
    )
    local statusExists = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
        {
            'lv_status'
        }
    )

    if tonumber(legacyExists) > 0 and tonumber(statusExists) == 0 then
        MySQL.query.await(('RENAME TABLE `%s` TO `lv_status`'):format(legacyTable))
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lv_status` (
            `identifier` VARCHAR(60) NOT NULL,
            `hunger`     FLOAT       NOT NULL DEFAULT 100,
            `thirst`     FLOAT       NOT NULL DEFAULT 100,
            `stress`     FLOAT       NOT NULL DEFAULT 0,
            `last_stress_at` BIGINT NOT NULL DEFAULT 0,
            `addiction`  FLOAT       NOT NULL DEFAULT 0,
            `last_addiction_at` BIGINT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        ALTER TABLE `lv_status`
            ADD COLUMN IF NOT EXISTS `stress` FLOAT NOT NULL DEFAULT 0 AFTER `thirst`,
            ADD COLUMN IF NOT EXISTS `last_stress_at` BIGINT NOT NULL DEFAULT 0 AFTER `stress`,
            ADD COLUMN IF NOT EXISTS `addiction` FLOAT NOT NULL DEFAULT 0 AFTER `last_stress_at`,
            ADD COLUMN IF NOT EXISTS `last_addiction_at` BIGINT NOT NULL DEFAULT 0 AFTER `addiction`
    ]])
end)

function DB_LoadStatus(identifier, cb)
    MySQL.single(
        'SELECT hunger, thirst, stress, last_stress_at, addiction, last_addiction_at FROM lv_status WHERE identifier = ?',
        {
            identifier
        },
        function(row)
            if row then
                cb(row.hunger, row.thirst, row.stress, row.last_stress_at, row.addiction, row.last_addiction_at)
            else
                MySQL.insert(
                    'INSERT INTO lv_status (identifier, hunger, thirst, stress, last_stress_at, addiction, last_addiction_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    {
                        identifier,
                        Config.DefaultHunger,
                        Config.DefaultThirst,
                        Config.DefaultStress,
                        os.time(),
                        Config.DefaultAddiction,
                        os.time()
                    },
                    function()
                        cb(
                            Config.DefaultHunger,
                            Config.DefaultThirst,
                            Config.DefaultStress,
                            os.time(),
                            Config.DefaultAddiction,
                            os.time()
                        )
                    end
                )
            end
        end
    )
end

function DB_SaveStatus(identifier, hunger, thirst, stress, lastStressAt, addiction, lastAddictionAt)
    return MySQL.update.await(
        [[
            INSERT INTO lv_status (identifier, hunger, thirst, stress, last_stress_at, addiction, last_addiction_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                hunger = VALUES(hunger),
                thirst = VALUES(thirst),
                stress = VALUES(stress),
                last_stress_at = VALUES(last_stress_at),
                addiction = VALUES(addiction),
                last_addiction_at = VALUES(last_addiction_at)
        ]],
        {
            identifier,
            hunger,
            thirst,
            stress,
            lastStressAt,
            addiction,
            lastAddictionAt
        }
    )
end

function DB_SaveStatuses(rows)
    if #rows == 0 then
        return 0
    end

    local values = {}
    local parameters = {}

    for i = 1, #rows do
        local row = rows[i]

        values[i] = '(?, ?, ?, ?, ?, ?, ?)'

        parameters[#parameters + 1] = row.identifier
        parameters[#parameters + 1] = row.hunger
        parameters[#parameters + 1] = row.thirst
        parameters[#parameters + 1] = row.stress
        parameters[#parameters + 1] = row.lastStressAt
        parameters[#parameters + 1] = row.addiction
        parameters[#parameters + 1] = row.lastAddictionAt
    end

    local query = ([[
        INSERT INTO lv_status (identifier, hunger, thirst, stress, last_stress_at, addiction, last_addiction_at)
        VALUES %s
        ON DUPLICATE KEY UPDATE
            hunger = VALUES(hunger),
            thirst = VALUES(thirst),
            stress = VALUES(stress),
            last_stress_at = VALUES(last_stress_at),
            addiction = VALUES(addiction),
            last_addiction_at = VALUES(last_addiction_at)
    ]]):format(table.concat(values, ','))
    return MySQL.update.await(query, parameters)
end
