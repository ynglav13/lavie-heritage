local stashes =
{
    {
        key = '140_gang',
        label = '140 GANG',
        coords = vec3(456.92, -1747.40, 28.69)
    },
    {
        key = 'wah_chong',
        label = 'Wah Chong',
        coords = vec3(465.19, -750.57, 27.36)
    },
    {
        key = 'rancho_13',
        label = 'Rancho 13',
        coords = vec3(287.85, -1775.10, 28.43)
    },
    {
        key = 'mechanic',
        label = 'Mechanic',
        coords = vec3(-224.29, -1320.06, 30.89)
    },
    {
        key = 'parkside_real_13',
        label = 'Parkside Real 13',
        coords = vec3(386.05, -2025.63, 22.98)
    },
    {
        key = 'southside_18',
        label = 'SouthSide 18',
        coords = vec3(-159.85, -1636.40, 37.25)
    },
    {
        key = 'lspd',
        label = 'LSPD',
        coords = vec3(63.98, -340.45, 45.07)
    },
    {
        key = 'rextune_1',
        label = 'Rex Tune 1',
        coords = vec3(-319.69, -136.63, 39.02)
    },
    {
        key = 'rextune_2',
        label = 'Rex Tune 2',
        coords = vec3(-311.25, -114.26, 39.02)
    },
    {
        key = 'rextune_3',
        label = 'Rex Tune 3',
        coords = vec3(-350.09, -86.56, 39.02)
    }
}

local function openPasswordStash(stash)
    local input = lib.inputDialog(stash.label,
    {
        {
            type = 'input',
            label = 'Mật Khẩu',
            password = true,
            required = true
        }
    })

    if not input then
        return
    end

    local stashId = lib.callback.await('gang_stashes:authorize', false, stash.key, input[1])

    if not stashId then
        return lib.notify(
        {
            title = stash.label,
            description = 'Mật khẩu không chính xác',
            type = 'error'
        })
    end

    exports.ox_inventory:openInventory('stash', stashId)
end

CreateThread(function()
    for index, stash in ipairs(stashes) do
        exports.ox_target:addSphereZone(
        {
            name = ('gang_stash_%s'):format(stash.key),
            coords = stash.coords,
            radius = 1.5,
            debug = false,
            options =
            {
                {
                    name = ('gang_stash_open_%s'):format(stash.key),
                    icon = 'fa-solid fa-box-open',
                    label = ('Mở Kho %s'):format(stash.label),
                    distance = 2.5,
                    onSelect = function()
                        openPasswordStash(stashes[index])
                    end
                }
            }
        })
    end
end)
