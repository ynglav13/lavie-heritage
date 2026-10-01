InjurySharedClient = {}
InjurySharedClient.Function = {}
MedicalClient = MedicalClient or {}
MedicalClient.Injury = InjurySharedClient

InjuryUtil = {}
InjuryUtil.Function = {}
MedicalShared = MedicalShared or {}
MedicalShared.Injury = InjuryUtil

---@param name string resource name
---@return boolean
InjuryUtil.Function.HasResource = function(name)
    return GetResourceState(name):find("start") ~= nil
end

GetSelf = function()
    local self = {}

    self.id = GetPlayerServerId(PlayerId())
    self.ped = PlayerPedId() or GetPlayerPed(-1)
    self.name = LocalPlayer.state.playerName
    return self
end

---@param value any
---@return string
InjuryUtil.Function.FirstToUpper = function(value)
    if type(value) ~= 'string' then
        value = tostring(value) or ""
    end
    if value == "" then return "" end
    return (value:gsub("^%l", string.upper))
end

---@param value string
---@return string
Trim = function(value)
    return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end
