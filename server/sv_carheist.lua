local Server = lib.require('server/sv_config')
local QBCore = exports['jd-core']:GetCoreObject()

local contactPed
local contactCreating = false
local activeOwner
local cooldownEnds = 0
local carHeist = {}
local rateLimits = {}

assert(type(Server.VehicleList) == 'table' and #Server.VehicleList > 0, 'VehicleList не може да бъде празен.')
assert(type(Server.SpawnLocations) == 'table' and #Server.SpawnLocations > 0, 'SpawnLocations не може да бъде празен.')
assert(type(Server.DeliveryCoords) == 'table' and #Server.DeliveryCoords > 0, 'DeliveryCoords не може да бъде празен.')

local function isRateLimited(source, action)
    local limit = Server.RateLimits[action] or 2000
    local now = GetGameTimer()
    rateLimits[source] = rateLimits[source] or {}
    local last = rateLimits[source][action] or 0
    if now - last < limit then return true end
    rateLimits[source][action] = now
    return false
end

local function isNear(source, coords, distance)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= distance
end

local function deleteMission(source, notifyClient)
    local mission = carHeist[source]
    if mission and mission.entity and DoesEntityExist(mission.entity) then DeleteEntity(mission.entity) end
    carHeist[source] = nil
    if activeOwner == source then activeOwner = nil end
    ClearPoliceTracker()
    if notifyClient then TriggerClientEvent('randol_carheist:client:resetHeist', source) end
end

local function checkCopCount()
    local count = 0
    for _, playerId in ipairs(QBCore.Functions.GetPlayers()) do
        local player = QBCore.Functions.GetPlayer(playerId)
        local job = player and player.PlayerData.job
        if job and job.name == 'police' and job.onduty then count = count + 1 end
    end
    return count
end

local function createContact()
    if contactPed and DoesEntityExist(contactPed) then return true end
    if contactCreating then return false end
    contactCreating = true

    local coords = Server.PedCoords
    contactPed = CreatePed(4, Server.PedModel, coords.x, coords.y, coords.z, coords.w, true, true)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(contactPed) and GetGameTimer() < timeout do Wait(25) end
    if DoesEntityExist(contactPed) then
        SetEntityInvincible(contactPed, true)
        FreezeEntityPosition(contactPed, true)
        SetBlockingOfNonTemporaryEvents(contactPed, true)
        contactCreating = false
        return true
    end
    contactCreating = false
    return false
end

local function updateTracker(source, vehicle, token)
    CreateThread(function()
        local updates = math.max(1, math.floor(Server.TrackerDuration / Server.TrackerInterval))
        for _ = 1, updates do
            local mission = carHeist[source]
            if not mission or mission.token ~= token or not DoesEntityExist(vehicle) then break end
            PoliceTracker(GetEntityCoords(vehicle))
            Wait(Server.TrackerInterval * 1000)
        end
        if carHeist[source] and carHeist[source].token == token then
            carHeist[source].trackerFinished = true
            ClearPoliceTracker()
            TriggerClientEvent('randol_carheist:client:trackerOff', source, carHeist[source].delivery)
        end
    end)
end

local function createHeistVehicle(source, mission)
    local coords = mission.location.spawn
    local vehicle = CreateVehicleServerSetter(joaat(mission.model), 'automobile', coords.x, coords.y, coords.z, coords.w)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < timeout do Wait(25) end
    if not DoesEntityExist(vehicle) then return nil end
    local plate = GetVehicleNumberPlateText(vehicle)
    TriggerEvent('vehiclekeys:server:NewSetVehicleOwner', source, plate, true)
    return vehicle
end

lib.callback.register('randol_carheist:server:getContact', function(source)
    if isRateLimited(source, 'contact') then return 0, Server.DepositMoney end
    if not contactPed or not DoesEntityExist(contactPed) then createContact() end
    return contactPed and NetworkGetNetworkIdFromEntity(contactPed) or 0, Server.DepositMoney
end)

lib.callback.register('randol_carheist:attemptjob', function(source)
    if isRateLimited(source, 'start') then return false, 'Моля, изчакайте преди нов опит.' end
    local player = QBCore.Functions.GetPlayer(source)
    if not player or not isNear(source, Server.PedCoords, 4.0) then return false, 'Трябва да сте при Нико.' end
    if carHeist[source] then return false, 'Вече имате активна задача.' end
    if activeOwner then return false, 'Друг играч вече изпълнява задачата.' end
    if os.time() < cooldownEnds then
        return false, ('Изчакайте още %d минути.'):format(math.ceil((cooldownEnds - os.time()) / 60))
    end
    if checkCopCount() < Server.RequiredCops then return false, 'Няма достатъчно полицаи на смяна.' end
    if player.PlayerData.money.cash < Server.DepositMoney then
        return false, ('Нужни са ви $%s за депозит!'):format(Server.DepositMoney)
    end
    if not HasRequiredItem(player, Server.RequiredItem) then return false, 'Нямате необходимия предмет.' end
    if not player.Functions.RemoveMoney('cash', Server.DepositMoney, 'low-carthief-deposit') then
        return false, 'Депозитът не можа да бъде взет.'
    end

    local mission = {
        token = ('%s:%s:%s'):format(source, os.time(), math.random(100000, 999999)),
        model = Server.VehicleList[math.random(#Server.VehicleList)],
        location = Server.SpawnLocations[math.random(#Server.SpawnLocations)],
        delivery = Server.DeliveryCoords[math.random(#Server.DeliveryCoords)],
        entity = 0,
        vehicleCreated = false,
        trackerFinished = false,
        completed = false
    }
    carHeist[source], activeOwner = mission, source
    cooldownEnds = os.time() + (Server.Cooldown * 60)

    SetTimeout(Server.MissionDuration * 60000, function()
        if carHeist[source] and carHeist[source].token == mission.token then deleteMission(source, true) end
    end)

    return true, {
        token = mission.token,
        model = mission.model,
        location = { enter = mission.location.enter }
    }
end)

lib.callback.register('randol_carheist:server:createVehicle', function(source, token)
    if isRateLimited(source, 'vehicle') then return false, 'Моля, изчакайте.' end
    local mission = carHeist[source]
    if not mission or mission.token ~= token then return false, 'Невалидна задача.' end
    if mission.vehicleCreated or (mission.entity ~= 0 and DoesEntityExist(mission.entity)) then
        return false, 'Автомобилът вече е създаден.'
    end
    if not isNear(source, mission.location.enter, 12.0) then return false, 'Не сте при правилния гараж.' end
    mission.vehicleCreated = true
    local vehicle = createHeistVehicle(source, mission)
    if not vehicle then
        mission.vehicleCreated = false
        return false, 'Автомобилът не можа да бъде създаден.'
    end
    mission.entity = vehicle
    TriggerEvent('SendAlert:police', {
        coords = GetEntityCoords(vehicle),
        title = 'Кражба на автомобил',
        type = '215',
        job = 'police',
        metadata = { model = mission.model, plate = GetVehicleNumberPlateText(vehicle) }
    })
    updateTracker(source, vehicle, token)
    return true, NetworkGetNetworkIdFromEntity(vehicle)
end)

lib.callback.register('randol_carheist:server:finishHeist', function(source, token, vehicleNetId)
    if isRateLimited(source, 'finish') then return false end
    local player = QBCore.Functions.GetPlayer(source)
    local mission = carHeist[source]
    if not player or not mission or mission.token ~= token or mission.completed then return false end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(vehicleNetId) or 0)
    if vehicle == 0 or not DoesEntityExist(vehicle) or vehicle ~= mission.entity then return false end
    if GetEntityModel(vehicle) ~= joaat(mission.model) then return false end
    local ped = GetPlayerPed(source)
    if ped == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end
    if not mission.trackerFinished then return false end
    if not isNear(source, mission.delivery, 10.0) then return false end

    local amount = math.random(Server.Min, Server.Max)
    local cid = GetPlyIdentifier(player)
    local documentId = ('%s:%s:%s'):format(cid, os.time(), math.random(100000, 999999))
    local metadata = {
        amount = amount,
        cid = cid,
        documentId = documentId,
        description = ('Върнете документа, за да получите $%s'):format(amount)
    }
    mission.completed = true

    local inserted = MySQL.insert.await(
        'INSERT INTO jd_low_carthief_documents (token, citizenid, amount) VALUES (?, ?, ?)',
        { documentId, cid, amount }
    )
    if not inserted then
        mission.completed = false
        return false
    end

    if not AddHeistPapers(player, metadata) then
        MySQL.query.await('DELETE FROM jd_low_carthief_documents WHERE token = ?', { documentId })
        mission.completed = false
        return false
    end
    DeleteEntity(vehicle)
    lib.logger(QBCore.Functions.GetIdentifier(source, 'discord'), 'Low-carthief', ('Играч: %s | ID: %s върна автомобил и взе документ за $%s'):format(GetPlayerName(source), source, amount))
    carHeist[source], activeOwner = nil, nil
    TriggerClientEvent('randol_carheist:client:endRobbery', source)
    return true
end)

lib.callback.register('randol_carheist:server:returnPapers', function(source)
    if isRateLimited(source, 'papers') then return false, 'Моля, изчакайте.' end
    local player = GetPlayer(source)
    if not player or not isNear(source, Server.PedCoords, 4.0) then return false, 'Трябва да сте при Нико.' end
    local item, metadata = GetItemData(player, 'heist_papers')
    if not item or type(metadata) ~= 'table' then return false, 'Нямате валиден документ.' end
    local documentId = type(metadata.documentId) == 'string' and metadata.documentId
    if not documentId or #documentId > 128 then return false, 'Документът е невалиден.' end

    local cid = GetPlyIdentifier(player)
    local document = MySQL.single.await(
        'SELECT citizenid, amount, redeemed FROM jd_low_carthief_documents WHERE token = ? LIMIT 1',
        { documentId }
    )
    local redeemed = document and (tonumber(document.redeemed) == 1 or document.redeemed == true)
    if not document or redeemed then return false, 'Документът вече е използван или е невалиден.' end
    if cid ~= document.citizenid then return false, 'Този документ не ви принадлежи.' end

    local amount = tonumber(document.amount)
    if not amount or amount < Server.Min or amount > Server.Max then return false, 'Документът е невалиден.' end
    local dirtyAmount = amount - math.floor(amount * 0.6)
    if not CanCarryReward(player, dirtyAmount) then
        return false, 'Нямате достатъчно място за наградата.'
    end

    local claimed = MySQL.update.await(
        'UPDATE jd_low_carthief_documents SET redeemed = 1, redeemed_at = CURRENT_TIMESTAMP WHERE token = ? AND redeemed = 0',
        { documentId }
    )
    if claimed ~= 1 then return false, 'Документът вече е използван.' end

    if not RemoveHeistPapers(player, item.name, item.slot) then
        MySQL.update.await('UPDATE jd_low_carthief_documents SET redeemed = 0, redeemed_at = NULL WHERE token = ?', { documentId })
        return false, 'Документът не можа да бъде премахнат.'
    end

    if not AddRewardMoney(player, math.floor(amount)) then
        AddHeistPapers(player, metadata)
        MySQL.update.await('UPDATE jd_low_carthief_documents SET redeemed = 0, redeemed_at = NULL WHERE token = ?', { documentId })
        return false, 'Наградата не можа да бъде добавена.'
    end

    return true, ('Получихте $%s за успешната доставка.'):format(amount)
end)

AddEventHandler('playerDropped', function()
    rateLimits[source] = nil
    deleteMission(source, false)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        createContact()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `jd_low_carthief_documents` (
            `token` VARCHAR(128) NOT NULL,
            `citizenid` VARCHAR(64) NOT NULL,
            `amount` INT UNSIGNED NOT NULL,
            `redeemed` TINYINT(1) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `redeemed_at` TIMESTAMP NULL DEFAULT NULL,
            PRIMARY KEY (`token`),
            INDEX `idx_citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
        MySQL.update.await('DELETE FROM jd_low_carthief_documents WHERE created_at < (NOW() - INTERVAL 30 DAY)')
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for source in pairs(carHeist) do deleteMission(source, false) end
    if contactPed and DoesEntityExist(contactPed) then DeleteEntity(contactPed) end
end)
