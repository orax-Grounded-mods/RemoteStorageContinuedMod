--[[
    Documentation for "Key" and "ModifierKey":
      https://github.com/UE4SS/UE4SS/wiki/Table:-Key
      https://github.com/UE4SS/UE4SS/wiki/Table:-ModifierKey
]]
StorageKeyBindKey = Key.NUM_NINE
StorageKeyBindModifierKey = ModifierKey.ALT
SelectStorageKeyBindKey = Key.NUM_SEVEN
SelectStorageKeyBindModifierKey = ModifierKey.ALT

RemoteStoragePrefix = "#"
RemoteStorageSize = 100  -- default: 40
PlayerBackpackSize = 100 -- default: 30

StorageClassesFilter = {
  -- "/Game/Blueprints/Items/Buildings/Storage/BP_Storage.BP_Storage_C",             -- Storage Basket
  -- "/Game/Blueprints/Items/Buildings/Storage/BP_Storage_Big.BP_Storage_Big_C",     -- Storage Chest
  -- "/Game/Blueprints/Items/Buildings/Storage/BP_Storage_Tier3.BP_Storage_Tier3_C", -- Large Storage Chest
  -- "/Game/Blueprints/Items/Buildings/Storage/BP_StorageFridge.BP_StorageFridge_C", -- Fresh Storage
}

DisplayIconWithMessage = true

-- {NAME} will be replaced by the storage name
-- {TYPE} will be replaced by Storage, Storage Big, StorageTier3 or StorageFood.
MSG_SELECTED = [[Selected {NAME} ({TYPE})]]

MSG_NO_STORAGES_FOUND = [[No remote storages found]]

---@type _LogLevel
LOG_LEVEL = "INFO" -- "ALL" | "TRACE" | "DEBUG" | "INFO" | "WARN" | "ERROR" | "FATAL" | "OFF"
