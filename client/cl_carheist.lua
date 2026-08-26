local spawnBlip, deliveryBlip, dropoffZone, heistVehicle, policeBlip, contactNetId
local robberyActive, trackerActive, droppingOff = false, false, false
local mission = {}
local Config = { Debug = false, FuelScript = { enable = true, name = 'jd-fuel' } }

local function showTask(title, lines)
    if GetResourceState('jd-task') == 'started' then
        pcall(function() exports['jd-task']:Show(title, lines) end)
    end
end

local function hideTask()
    if GetResourceState('jd-task') == 'started' then
        pcall(function() exports['jd-task']:Hide() end)
    end
end

local function removeGarageZone()
    if GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeZone('garage_enter') end)
    end
end

local function removeBlips()
    if spawnBlip and DoesBlipExist(spawnBlip) then RemoveBlip(spawnBlip) end
    if deliveryBlip and DoesBlipExist(deliveryBlip) then RemoveBlip(deliveryBlip) end
    if policeBlip and DoesBlipExist(policeBlip) then RemoveBlip(policeBlip) end
    spawnBlip, deliveryBlip, policeBlip = nil, nil, nil
end

local function removeDropoffZone()
    if dropoffZone then
        pcall(function() dropoffZone:remove() end)
        dropoffZone = nil
    end
    lib.hideTextUI()
end

local function resetState()
    removeBlips()
    removeDropoffZone()
    removeGarageZone()
    hideTask()
    robberyActive, trackerActive, droppingOff = false, false, false
    heistVehicle = nil
    table.wipe(mission)
end

local function createSearchBlip(coords)
    local blip = AddBlipForRadius(coords.x + math.random(-150, 150), coords.y + math.random(-150, 150), 0.0, 200.0)
    SetBlipSprite(blip, 9)
    SetBlipColour(blip, 27)
    SetBlipAlpha(blip, 80)
    return blip
end

local function finishDelivery()
    local vehicle = cache.vehicle
    if droppingOff or not robberyActive or not vehicle or vehicle ~= heistVehicle then return end
    droppingOff = true
    FreezeEntityPosition(vehicle, true)

    local completed = lib.progressCircle({
        duration = 3000, position = 'bottom', label = 'Подготовка на документа...',
        useWhileDead = false, canCancel = false,
        disable = { move = true, car = true, combat = true }
    })
    if not completed then
        FreezeEntityPosition(vehicle, false)
        droppingOff = false
        return
    end

    local success = lib.callback.await('randol_carheist:server:finishHeist', false,
        mission.token, NetworkGetNetworkIdFromEntity(vehicle))
    if not success then
        FreezeEntityPosition(vehicle, false)
        droppingOff = false
        return DoNotification('Доставката не беше потвърдена от сървъра.', 'error')
    end

    resetState()
    Wait(1000)
    showTask('Нико Запалката', { 'Ела ми донеси документа и ще си получиш наградата!' })
end

local function createDropoff(coords)
    removeDropoffZone()
    dropoffZone = lib.zones.box({
        coords = vec3(coords.x, coords.y, coords.z),
        size = vec3(6.0, 6.0, 6.0), rotation = coords.w or 0.0, debug = Config.Debug,
        inside = function()
            if IsControlJustReleased(0, 38) then finishDelivery() end
        end,
        onEnter = function()
            lib.showTextUI('[E] - Завърши доставката', { icon = 'fa-solid fa-car', position = 'left-center' })
        end,
        onExit = function() lib.hideTextUI() end
    })

    deliveryBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(deliveryBlip, 315)
    SetBlipColour(deliveryBlip, 3)
    SetBlipAlpha(deliveryBlip, 220)
    SetBlipDisplay(deliveryBlip, 4)
    SetBlipRoute(deliveryBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Място за доставка')
    EndTextCommandSetBlipName(deliveryBlip)
    SetNewWaypoint(coords.x, coords.y)
end

RegisterNetEvent('randol_carheist:client:resetHeist', function()
    if GetInvokingResource() then return end
    local wasActive = robberyActive
    resetState()
    if wasActive then
        DoNotification('Времето изтече. Автомобилът вече не се приема.', 'error', 10000)
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
end)

RegisterNetEvent('randol_carheist:client:trackerOff', function(delivery)
    if GetInvokingResource() or not robberyActive or type(delivery) ~= 'table' then return end
    if not delivery.x or not delivery.y or not delivery.z then return end
    trackerActive = false
    if policeBlip and DoesBlipExist(policeBlip) then RemoveBlip(policeBlip) end
    policeBlip = nil
    createDropoff(delivery)
    hideTask()
    showTask('Нико Запалката', { 'Тракерът е изключен. Закарай автомобила до отбелязаното място.' })
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
end)

RegisterNetEvent('randol_carheist:client:trackerUpdate', function(coords)
    if GetInvokingResource() or not coords then return end
    if policeBlip and DoesBlipExist(policeBlip) then RemoveBlip(policeBlip) end
    policeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(policeBlip, 161)
    SetBlipDisplay(policeBlip, 4)
    SetBlipScale(policeBlip, 1.0)
    SetBlipColour(policeBlip, 1)
    PulseBlip(policeBlip)
    SetBlipAsShortRange(policeBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('КРАЖБА НА АВТОМОБИЛ')
    EndTextCommandSetBlipName(policeBlip)
end)

RegisterNetEvent('randol_carheist:client:trackerClear', function()
    if GetInvokingResource() then return end
    if policeBlip and DoesBlipExist(policeBlip) then RemoveBlip(policeBlip) end
    policeBlip = nil
end)

RegisterNetEvent('randol_carheist:client:endRobbery', function()
    if GetInvokingResource() then return end
    resetState()
end)

local function setVehicleFuel(vehicle)
    if Config.FuelScript.enable and GetResourceState(Config.FuelScript.name) == 'started' then
        local ok = pcall(function() exports[Config.FuelScript.name]:SetFuel(vehicle, 100.0) end)
        if ok then return end
    end
    Entity(vehicle).state:set('fuel', 100, true)
end

local function initVehicle(netId)
    heistVehicle = lib.waitFor(function()
        if NetworkDoesEntityExistWithNetworkId(netId) then return NetToVeh(netId) end
    end, 'Автомобилът не можа да бъде зареден навреме.', 10000)
    if not heistVehicle or heistVehicle == 0 then
        return DoNotification('Автомобилът не можа да бъде зареден.', 'error')
    end
    SetEntityAsMissionEntity(heistVehicle, true, true)
    SetVehicleColours(heistVehicle, math.random(0, 159), math.random(0, 159))
    SetVehicleDoorsLocked(heistVehicle, 1)
    setVehicleFuel(heistVehicle)
    robberyActive, trackerActive = true, true
    if spawnBlip and DoesBlipExist(spawnBlip) then RemoveBlip(spawnBlip) end
    spawnBlip = nil
    showTask('Нико Запалката', { 'Вземи автомобила и остани в движение, докато изключа тракера.' })
end

local function createStealPoint()
    local coords = mission.location.enter
    local displayName = GetDisplayNameFromVehicleModel(joaat(mission.model))
    local translated = GetLabelText(displayName)
    local label = translated ~= 'NULL' and translated or displayName
    if spawnBlip and DoesBlipExist(spawnBlip) then RemoveBlip(spawnBlip) end
    spawnBlip = createSearchBlip(coords)
    if Config.Debug then SetNewWaypoint(coords.x, coords.y) end
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    showTask('Нико Запалката', { ('Намери %s. Автомобилът е в гараж в маркираната GPS зона.'):format(label) })

    exports.ox_target:addSphereZone({
        coords = coords.xyz, radius = 10.0, name = 'garage_enter',
        options = {{
            icon = 'fas fa-warehouse', label = 'Провери гаража', distance = 2.5,
            onSelect = function()
                removeGarageZone()
                hideTask()
                SetEntityHeading(cache.ped, coords.w)
                SetEntityCoords(cache.ped, coords.x, coords.y, coords.z - 1.0)
                Wait(100)
                local offset = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, -1.1, -0.95)
                SetEntityCoords(cache.ped, offset)
                lib.requestAnimDict('anim@apt_trans@garage', 2000)
                TaskPlayAnim(cache.ped, 'anim@apt_trans@garage', 'gar_open_1_left', 8.0, -8.0, -1, 2, 0, false, false, false)
                Wait(2000)
                DoScreenFadeOut(500)
                local soundId = GetSoundId()
                PlaySoundFrontend(soundId, 'GARAGE_DOOR_SCRIPTED_OPEN', 0, true)
                ReleaseSoundId(soundId)
                Wait(1000)
                ClearPedTasksImmediately(cache.ped)
                local ok, result = lib.callback.await('randol_carheist:server:createVehicle', false, mission.token)
                if not ok then
                    DoScreenFadeIn(500)
                    DoNotification(result or 'Автомобилът не можа да бъде създаден.', 'error')
                    return createStealPoint()
                end
                initVehicle(result)
                Wait(500)
                DoScreenFadeIn(1000)
            end
        }}
    })
end

function OnPlayerLogout()
    resetState()
end

local function setupContact()
    local netId, deposit = lib.callback.await('randol_carheist:server:getContact', false)
    if not netId or netId == 0 then return false end
    if contactNetId and contactNetId ~= netId then
        pcall(function() exports.ox_target:removeEntity(contactNetId) end)
    elseif contactNetId == netId then
        return true
    end
    contactNetId = netId
    exports.ox_target:addEntity(netId, {
        {
            name = 'low_carthief_start', icon = 'fa-solid fa-square-check', label = 'Нико Запалката', distance = 2.5,
            onSelect = function()
                local alert = lib.alertDialog({
                    header = 'Започване на работа',
                    content = ('При приемане ще платите депозит от $%s.'):format(deposit),
                    centered = true, cancel = true,
                    labels = { cancel = 'Откажи', confirm = 'Потвърди' }
                })
                if alert ~= 'confirm' then return end
                local ok, data = lib.callback.await('randol_carheist:attemptjob', false)
                if not ok then return DoNotification(data or 'Задачата не може да започне.', 'error') end
                mission = data
                createStealPoint()
            end
        },
        {
            name = 'low_carthief_papers', icon = 'fa-solid fa-file-invoice-dollar', label = 'Върни документа',
            item = 'heist_papers', distance = 2.5,
            onSelect = function()
                local ok, message = lib.callback.await('randol_carheist:server:returnPapers', false)
                DoNotification(message or (ok and 'Документът е предаден.' or 'Документът е невалиден.'), ok and 'success' or 'error')
                if ok then hideTask() end
            end
        }
    })
    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    resetState()
    if contactNetId and GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeEntity(contactNetId) end)
    end
end)

CreateThread(function()
    Wait(1500)
    while not setupContact() do Wait(5000) end
end)
