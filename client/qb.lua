if GetResourceState('jd-core') ~= 'started' then
    error('[jd-low-carthief] jd-core не е стартиран.')
end

local QBCore = exports['jd-core']:GetCoreObject()

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if OnPlayerLogout then OnPlayerLogout() end
end)

function DoNotification(text, notificationType, duration)
    QBCore.Functions.Notify(text, notificationType, duration)
end
