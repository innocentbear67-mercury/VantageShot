-- armour customisation retired 2026-11-17 (real module: ServerStorage._ArmourArchive_20261117). Inert stub so Armory loads.
local Bay = {}
Bay.__index = Bay
function Bay.new() return setmetatable({ Preview = nil }, Bay) end
function Bay:SetVisible() end
function Bay:SelectSlot() end
function Bay:Refresh() end
function Bay:Equip() end
function Bay:FirstButton() return nil end
return Bay
