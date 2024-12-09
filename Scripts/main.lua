LOG_LEVEL = "INFO" ---@type _LogLevel
MIN_LEVEL_OF_FATAL_ERROR = "ERROR" ---@type _LogLevel

---@type Mod_ModInfo
local modInfo = (function()
  local info = debug.getinfo(2, "S")
  local source = info.source
  return {
    name = source:match("@?.+\\Mods\\([^\\]+)"),
    file = source:sub(2),
    currentDirectory = source:match("@?(.+)\\"),
    currentModDirectory = source:match("@?(.+\\Mods\\[^\\]+)"),
    modsDirectory = source:match("@?(.+\\Mods)\\")
  }
end)()

---@param filename string
---@return boolean
local function isFileExists(filename)
  local file = io.open(filename, "r")
  if file ~= nil then
    io.close(file)
    return true
  else
    return false
  end
end

---@param filename string
---@return boolean
local function isSharedFileExists(filename)
  if isFileExists(modInfo.modsDirectory .. "\\shared\\" .. filename) then
    return true
  else
    print(string.format("Shared file not found: %s.\n", filename))
    return false
  end
end

local function loadOptions()
  local file = string.format([[%s\options.lua]], modInfo.currentModDirectory)

  if not isFileExists(file) then
    local cmd = string.format([[copy "%s\options.example.lua" "%s\options.lua"]],
      modInfo.currentModDirectory,
      modInfo.currentModDirectory)

    print("Copy example options to options.lua. Execute command: " .. cmd .. "\n")

    os.execute(cmd)
  end

  dofile(file)
end

-- defaults
RemoteStoragePrefix = "#"
RemoteStorageSize = nil
PlayerBackpackSize = nil
StorageKeyBindKey = nil
StorageKeyBindModifierKey = nil
SelectStorageKeyBindKey = nil
SelectStorageKeyBindModifierKey = nil
StorageClassesFilter = {}
MSG_SELECTED = "Selected {NAME}"
MSG_NO_STORAGES_FOUND = "No remote storages found"
DisplayIconWithMessage = true

loadOptions()

local ueHelpers = require("UEHelpers")
local logging = isSharedFileExists([[lua-mods-libs\logging.lua]]) and
    require("lua-mods-libs.logging") or
    require("lib.lua-mods-libs.logging")
local groundedHelpers = isSharedFileExists([[GroundedHelpers\GroundedHelpers.lua]]) and
    require("GroundedHelpers.GroundedHelpers") or
    require("lib.GroundedHelpers.GroundedHelpers")

local log = logging.new(LOG_LEVEL, MIN_LEVEL_OF_FATAL_ERROR)

local LocalPlayerCharacter = nil
local StorageList = {}
local StorageSizes = {}
local SelectedStorage = 0

Icon = nil
if DisplayIconWithMessage == true then
  Icon = groundedHelpers.textures.icon_Storage
end

---@param object UObject
---@param classes string[]?
---@return boolean
local function isOneOf(object, classes)
  if not classes or #classes == 0 then
    return true
  end

  for _, class in ipairs(classes) do
    if object:IsA(class) then
      log.debug(string.format("%q is a %q.", object:GetFullName(), class))
      return true
    end
  end

  return false
end

local function starts_with(str, start)
  return str:sub(1, #start) == start
end

local function UpdatePlayer(player)
  local inventoryComponent = player.InventoryComponent
  if PlayerBackpackSize then
    inventoryComponent.MaxSize = PlayerBackpackSize
  end
end

local function IsValidStorage(storage)
  local built = 1

  return storage and storage:IsValid() and storage.BuildingState == built
end

local function RemoveInvalidStorages()
  local newList = {}

  -- Do not use ipairs here because some values may be nil.
  -- ipairs might not iterate through the entire table if a value is null.
  for index = 1, #StorageList, 1 do
    local storage = StorageList[index]

    if not IsValidStorage(storage) then
      log.debug(string.format("Remove storage %i/%i.", index, #StorageList))
      if storage and storage:IsValid() then
        log.debug("BuildingState: " .. storage.BuildingState .. " " .. storage:GetFullName())
      end
    else
      table.insert(newList, storage)
    end
  end

  StorageList = newList
end

local function CheckStorage(storageIdx)
  if storageIdx == 0 or storageIdx > #StorageList then
    return false
  end

  local storage = StorageList[storageIdx]

  if not IsValidStorage(storage) then
    return false
  end

  log.debug(string.format("Check storage %i/%i: %q.", storageIdx, #StorageList, storage:GetFullName()))

  local storageAddr = storage:GetAddress()
  local storageOrigSize = StorageSizes[storageAddr]
  local inventoryComponent = storage.InventoryComponent
  local name = storage.CustomName:ToString()

  if name == "" then
    name = storage.CustomNameFiltered:ToString()
  end

  if starts_with(name, RemoteStoragePrefix) then
    if not storageOrigSize then
      StorageSizes[storageAddr] = inventoryComponent.MaxSize
      if RemoteStorageSize then
        inventoryComponent.MaxSize = RemoteStorageSize
      end
    end

    return true
  elseif storageOrigSize then
    StorageSizes[storageAddr] = nil
    inventoryComponent.MaxSize = storageOrigSize
  end

  return false
end

local function SelectStorage(hideMessage)
  if not LocalPlayerCharacter or not LocalPlayerCharacter:IsValid() or LocalPlayerCharacter.bPlayerBusyInMenu then
    return
  end

  RemoveInvalidStorages()

  if #StorageList == 0 then
    if not hideMessage then
      ---@diagnostic disable-next-line: param-type-mismatch
      groundedHelpers.ShowMessage(MSG_NO_STORAGES_FOUND, Icon)
    end

    return
  end

  local startedFrom = SelectedStorage
  while true do
    SelectedStorage = SelectedStorage + 1

    if CheckStorage(SelectedStorage) then
      break
    end

    if SelectedStorage > #StorageList then
      SelectedStorage = math.min(0, #StorageList)
    end

    if SelectedStorage == startedFrom then
      SelectedStorage = 0
      break
    end
  end

  local message = ""
  if SelectedStorage == 0 then
    message = MSG_NO_STORAGES_FOUND
  else
    local storage = StorageList[SelectedStorage]
    local name = storage.CustomName:ToString()

    if name == "" then
      name = storage.CustomNameFiltered:ToString()
    end

    message = string.gsub(MSG_SELECTED, "{NAME}", name)
    message = string.gsub(message, "{TYPE}", storage.BuildingData.RowName:ToString())
  end

  if not hideMessage then
    ---@diagnostic disable-next-line: param-type-mismatch
    groundedHelpers.ShowMessage(message, Icon)
  end
end

local function UpdateStorages()
  local newList = {}
  local newSizes = {}
  local storageInstances = FindAllOf("BP_BaseItemStorageBuilding_C") ---@type ABP_BaseItemStorageBuilding_C[]?

  if not storageInstances then
    log.info("No instances of 'BP_BaseItemStorageBuilding_C' were found.")
    return
  end

  for _, storage in pairs(storageInstances) do
    if storage:IsValid() and isOneOf(storage, StorageClassesFilter) then
      local storageAddr = storage:GetAddress()
      table.insert(newList, storage)
      newSizes[storageAddr] = StorageSizes[storageAddr]
    end
  end

  StorageList = newList
  StorageSizes = newSizes

  SelectStorage()
end

local function OpenStorage()
  if not CheckStorage(SelectedStorage) then
    SelectStorage(true)
  end

  if not CheckStorage(SelectedStorage) then
    ---@diagnostic disable-next-line: param-type-mismatch
    groundedHelpers.ShowMessage(MSG_NO_STORAGES_FOUND, Icon)
  else
    StorageList[SelectedStorage]:Use(0, LocalPlayerCharacter)
  end
end

local function OpenStorageEvent()
  if not LocalPlayerCharacter or not LocalPlayerCharacter:IsValid() or LocalPlayerCharacter.bPlayerBusyInMenu then
    return
  end

  OpenStorage()
end

local function Init()
  local gameStatics = groundedHelpers.GetSurvivalGameplayStatics()
  local engine = ueHelpers.GetEngine()
  if not engine or not gameStatics then
    log.error("UEngine or SurvivalGameplayStatics instance not found.")
    return
  end

  local player = groundedHelpers.GetLocalSurvivalPlayerCharacter()
  if LocalPlayerCharacter ~= nil and (not player:IsValid() or LocalPlayerCharacter:GetAddress() == player:GetAddress()) then
    return
  end

  LocalPlayerCharacter = nil
  if not player:IsValid() then
    return
  end

  LocalPlayerCharacter = player
  UpdateStorages()

  log.info(modInfo.name .. " init.")
end

---@param buildingParam RemoteUnrealParam
local function OnDestroy(buildingParam)
  local building = buildingParam:get() ---@type ABuilding
  local storageAddr = building:GetAddress()

  if StorageSizes[storageAddr] == nil then
    return
  end

  for idx, storage in pairs(StorageList) do
    if storage and storage:IsValid() and storage:GetAddress() == storageAddr then
      StorageList[idx] = nil
      break
    end
  end

  StorageSizes[storageAddr] = nil
end

if StorageKeyBindKey ~= nil then
  if StorageKeyBindModifierKey ~= nil then
    RegisterKeyBind(StorageKeyBindKey, { StorageKeyBindModifierKey }, OpenStorageEvent)
  else
    RegisterKeyBind(StorageKeyBindKey, OpenStorageEvent)
  end
end

if SelectStorageKeyBindKey ~= nil then
  if SelectStorageKeyBindModifierKey ~= nil then
    RegisterKeyBind(SelectStorageKeyBindKey, { SelectStorageKeyBindModifierKey }, SelectStorage)
  else
    RegisterKeyBind(SelectStorageKeyBindKey, SelectStorage)
  end
end

---@diagnostic disable-next-line: redundant-parameter
NotifyOnNewObject("/Script/Maine.SurvivalPlayerCharacter", function(player)
  UpdatePlayer(player)
end)

---@diagnostic disable-next-line: redundant-parameter
NotifyOnNewObject("/Script/Maine.Storage", function(storage)
  log.fatal("New object: " .. storage:GetFullName())
  if storage:IsValid() and isOneOf(storage, StorageClassesFilter) then
    table.insert(StorageList, storage)
  end
end)
---@diagnostic disable-next-line: redundant-parameter
NotifyOnNewObject("/Script/Maine.StorageBuilding", function(storage)
  if storage:IsValid() and isOneOf(storage, StorageClassesFilter) then
    log.debug("Add new StorageBuilding: " .. storage:GetFullName())
    table.insert(StorageList, storage)
  end
end)

RegisterHook("/Script/Maine.InventoryComponent:ServerTransferAllTo", function(self, param)
  local dest = param:get()
  if dest:GetOuter():IsA("/Game/Blueprints/Items/BP_Backpack_Player.BP_Backpack_Player_C") then
    dest.MaxSize = PlayerBackpackSize
  end
end)

RegisterHook("/Script/Maine.Building:MulticastHandleDestroyed", OnDestroy)
RegisterHook("/Script/Maine.Building:MulticastHandleDemolish", OnDestroy)

if FindFirstOf('SurvivalPlayerCharacter'):IsValid() then
  Init()
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", Init)
