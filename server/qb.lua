if GetResourceState('jd-core') ~= 'started' then
    error('[jd-low-carthief] jd-core не е стартиран.')
end

local QBCore = exports['jd-core']:GetCoreObject()
local oxInventory = GetResourceState('ox_inventory') == 'started'

function GetPlayer(source)
    return QBCore.Functions.GetPlayer(source)
end

function GetPlyIdentifier(player)
    return player and player.PlayerData.citizenid
end

function GetItemData(player, itemName)
    if not player or not itemName then return nil, nil end

    if oxInventory then
        local item = exports.ox_inventory:GetSlotWithItem(player.PlayerData.source, itemName)
        return item, item and item.metadata or nil
    end

    local item = player.Functions.GetItemByName(itemName)
    return item, item and item.info or nil
end

function HasRequiredItem(player, itemName)
    if not itemName or itemName == '' then return true end
    if not player then return false end

    if oxInventory then
        return exports.ox_inventory:Search(player.PlayerData.source, 'count', itemName) > 0
    end

    return player.Functions.GetItemByName(itemName) ~= nil
end

function AddHeistPapers(player, metadata)
    if not player then return false end
    if oxInventory then
        return exports.ox_inventory:AddItem(player.PlayerData.source, 'heist_papers', 1, metadata) == true
    end
    return player.Functions.AddItem('heist_papers', 1, false, metadata) == true
end

function RemoveHeistPapers(player, itemName, slot)
    if not player then return false end
    if oxInventory then
        return exports.ox_inventory:RemoveItem(player.PlayerData.source, itemName, 1, nil, slot) == true
    end
    return player.Functions.RemoveItem(itemName, 1, slot) == true
end

function CanCarryReward(player, dirtyAmount)
    if not player then return false end
    if not oxInventory then return true end
    return exports.ox_inventory:CanCarryItem(player.PlayerData.source, 'markedmoney', dirtyAmount)
end

function AddRewardMoney(player, amount)
    if not player or type(amount) ~= 'number' or amount <= 0 then return false end

    local source = player.PlayerData.source
    local cleanAmount = math.floor(amount * 0.6)
    local dirtyAmount = amount - cleanAmount

    if oxInventory then
        if not exports.ox_inventory:AddItem(source, 'markedmoney', dirtyAmount) then return false end
    elseif not player.Functions.AddItem('markedmoney', dirtyAmount) then
        return false
    end

    if player.Functions.AddMoney('cash', cleanAmount, 'low-carthief-reward') == false then
        if oxInventory then
            exports.ox_inventory:RemoveItem(source, 'markedmoney', dirtyAmount)
        else
            player.Functions.RemoveItem('markedmoney', dirtyAmount)
        end
        return false
    end

    if math.random(100) <= 20 then
        if oxInventory then
            exports.ox_inventory:AddItem(source, 'sdcard_boosting', 1)
        else
            player.Functions.AddItem('sdcard_boosting', 1)
        end
    end

    return true
end

function PoliceTracker(coords)
    for _, player in pairs(QBCore.Functions.GetQBPlayers()) do
        local job = player.PlayerData.job
        if job and job.type == 'leo' and job.onduty then
            TriggerClientEvent('randol_carheist:client:trackerUpdate', player.PlayerData.source, coords)
        end
    end
end

function ClearPoliceTracker()
    for _, player in pairs(QBCore.Functions.GetQBPlayers()) do
        local job = player.PlayerData.job
        if job and job.type == 'leo' and job.onduty then
            TriggerClientEvent('randol_carheist:client:trackerClear', player.PlayerData.source)
        end
    end
end
