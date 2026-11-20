--[[
	VANTAGE — WeaponInput (client)
	All weapon bindings via ContextActionService. Keys avoid every movement binding
	(Space / LeftControl / C / ButtonA / ButtonB / ButtonR3). Rebindable from Settings.
		Fire       MouseButton1, ButtonR2, touch            (fixed)
		Alt        ADS (rifle) / heavy stab (knife): MouseButton2, ButtonL2
		Reload     R, ButtonX          Inspect  F, DPadUp
		Primary    1, DPadLeft         Knife    V, DPadRight     Swap  Q, ButtonY
		Slots      1-7 (fixed: loadout slot N, see WeaponConfig.LoadoutOrder)
		Settings   P, ButtonSelect     Mouse wheel cycles weapons
		Armory     B, ButtonR3
		Grenade    Fire + Alt pressed together (mouse: both buttons; gamepad: R2 + L2), 2026-11-11.
		           Both presses within GrenadeConfig.ChordWindow = one throw (ThrowPressedAt).
		           A Fire press with Alt NOT already held waits that window before it counts,
		           so hip-fire starts ~0.08 s late; holding Alt first and then firing is instant.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local P = Enum.ContextActionPriority.High.Value

local CHORD_WINDOW = 0.08
do
	local ok, G = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Vantage"):WaitForChild("Grenade"):WaitForChild("GrenadeConfig"))
	end)
	if ok and G and type(G.ChordWindow) == "number" then
		CHORD_WINDOW = G.ChordWindow
	end
end

local ACTIONS = {
	Alt = { Gamepad = Enum.KeyCode.ButtonL2, Title = "Aim" },
	Reload = { Gamepad = Enum.KeyCode.ButtonX, Title = "R" },
	Inspect = { Gamepad = Enum.KeyCode.DPadUp, Title = "F" },
	Primary = { Gamepad = Enum.KeyCode.DPadLeft },
	Knife = { Gamepad = Enum.KeyCode.DPadRight },
	Swap = { Gamepad = Enum.KeyCode.ButtonY, Title = "Swap" },
	Settings = { Gamepad = Enum.KeyCode.ButtonSelect, Title = "Menu" },
	Inventory = { Gamepad = Enum.KeyCode.ButtonR3 },
}

local function toInput(name: string?)
	if type(name) ~= "string" then
		return nil
	end
	local okK, kc = pcall(function()
		return Enum.KeyCode[name]
	end)
	if okK and kc then
		return kc
	end
	local okT, ut = pcall(function()
		return Enum.UserInputType[name]
	end)
	if okT and ut then
		return ut
	end
	return nil
end
local WeaponInput = {}
WeaponInput.__index = WeaponInput
WeaponInput.ToInput = toInput

function WeaponInput.new()
	local self = setmetatable({}, WeaponInput)
	self.FireHeld = false
	self.FirePressedAt = -math.huge
	self.AltHeld = false
	self.AltPressedAt = -math.huge
	self.ReloadPressedAt = -math.huge
	self.InspectPressedAt = -math.huge
	-- admin skin checker (/skin, VantageAdminSkins): the server pokes this right after a swap
	self._autoInspect = game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("VantageAutoInspect"):Connect(function()
		self.InspectPressedAt = os.clock()
	end)
	self.SlotRequest = nil -- slot number | "knife" | "swap" | "next" | "prev"
	self.SlotRequestAt = -math.huge
	self.MenuPressedAt = -math.huge
	self.InventoryPressedAt = -math.huge
	self.Blocked = false -- true while the settings menu is open (fire / aim suppressed)
	self.Touch = UserInputService.TouchEnabled
	-- grenade chord (Fire + Alt together)
	self.ThrowPressedAt = -math.huge
	self._fireDown = false
	self._altDown = false
	self._altDownAt = -math.huge
	self._pendingFire = nil -- token of a Fire press still inside the chord window
	self._chord = false -- a throw happened: Fire and Alt stay dead until both are released

	ContextActionService:BindActionAtPriority("VantageFire", function(_, state)
		if state == Enum.UserInputState.Begin then
			if self.Blocked then
				return Enum.ContextActionResult.Pass
			end
			local now = os.clock()
			self._fireDown = true
			if self._chord then
				return Enum.ContextActionResult.Pass
			end
			if self._altDown and now - self._altDownAt <= CHORD_WINDOW then
				self:_throw(now) -- Alt went down a moment ago: both together
			elseif self._altDown then
				-- already aiming: an aimed shot, instantly
				self.FireHeld = true
				self.FirePressedAt = now
			else
				-- hip fire: wait the chord window in case Alt follows
				local token = {}
				self._pendingFire = token
				task.delay(CHORD_WINDOW, function()
					if self._pendingFire ~= token then
						return
					end
					self._pendingFire = nil
					if self._chord or self.Blocked then
						return
					end
					-- a tap released inside the window still fires once (semi-auto / single shot)
					self.FireHeld = self._fireDown
					self.FirePressedAt = os.clock()
				end)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self._fireDown = false
			self.FireHeld = false
			if self._chord and not self._altDown then
				self._chord = false
			end
		end
		return Enum.ContextActionResult.Pass
	end, self.Touch, P, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	if self.Touch then
		ContextActionService:SetTitle("VantageFire", "Fire")
		ContextActionService:SetPosition("VantageFire", UDim2.new(1, -170, 1, -170))
	end

	-- number keys pick a loadout slot directly (below the rebindable actions' priority)
	local SLOT_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven }
	ContextActionService:BindActionAtPriority("VantageSlots", function(_, state, io)
		if state ~= Enum.UserInputState.Begin or self.Blocked then
			return Enum.ContextActionResult.Pass
		end
		local n = table.find(SLOT_KEYS, io.KeyCode)
		if n then
			self.SlotRequest, self.SlotRequestAt = n, os.clock()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, P - 1, table.unpack(SLOT_KEYS))

	self._wheel = UserInputService.InputChanged:Connect(function(io, processed)
		if io.UserInputType == Enum.UserInputType.MouseWheel and not processed and not self.Blocked then
			self.SlotRequest = if io.Position.Z < 0 then "next" else "prev"
			self.SlotRequestAt = os.clock()
		end
	end)
	self._focus = UserInputService.WindowFocusReleased:Connect(function()
		self.FireHeld = false
		self.AltHeld = false
		self._fireDown, self._altDown, self._chord, self._pendingFire = false, false, false, nil
	end)
	self.Binds = {}
	return self
end

-- both buttons together: one grenade throw. Cancels the pending hip shot and the aim.
function WeaponInput:_throw(now: number)
	self._pendingFire = nil
	self._chord = true
	self.FireHeld = false
	self.AltHeld = false
	self.ThrowPressedAt = now
end

function WeaponInput:_handler(action: string)
	return function(_, state)
		local now = os.clock()
		if action == "Settings" then
			if state == Enum.UserInputState.Begin then
				self.MenuPressedAt = now
			end
			return Enum.ContextActionResult.Sink
		end
		if action == "Inventory" then
			-- works while menus block combat input (it also closes the armory)
			if state == Enum.UserInputState.Begin then
				self.InventoryPressedAt = now
			end
			return Enum.ContextActionResult.Sink
		end
		if self.Blocked then
			if state ~= Enum.UserInputState.Begin then
				self.AltHeld = false
				if action == "Alt" then
					self._altDown = false
				end
			end
			return Enum.ContextActionResult.Pass
		end
		if action == "Alt" then
			if state == Enum.UserInputState.Begin then
				self._altDown = true
				self._altDownAt = now
				if self._chord then
					return Enum.ContextActionResult.Pass
				end
				if self._pendingFire then
					self:_throw(now) -- Fire went down a moment ago: both together
					return Enum.ContextActionResult.Pass
				end
				self.AltHeld = true
				self.AltPressedAt = now
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				self._altDown = false
				self.AltHeld = false
				if self._chord and not self._fireDown then
					self._chord = false
				end
			end
			return Enum.ContextActionResult.Pass
		end
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if action == "Reload" then
			self.ReloadPressedAt = now
		elseif action == "Inspect" then
			self.InspectPressedAt = now
		elseif action == "Primary" then
			self.SlotRequest, self.SlotRequestAt = 1, now
		elseif action == "Knife" then
			self.SlotRequest, self.SlotRequestAt = "knife", now
		elseif action == "Swap" then
			-- Q cycles through the slots in order (1 -> 2 -> ... -> 7 -> 1), user 2026-11-08
			self.SlotRequest, self.SlotRequestAt = "next", now
		end
		return Enum.ContextActionResult.Sink
	end
end

-- binds: { Alt = "MouseButton2", Reload = "R", ... } (names of KeyCode / UserInputType)
function WeaponInput:ApplyBinds(binds)
	for action, spec in ACTIONS do
		ContextActionService:UnbindAction("Vantage" .. action)
		local key = toInput(binds[action])
		local inputs = { spec.Gamepad }
		if key then
			table.insert(inputs, 1, key)
		end
		local touchButton = self.Touch and spec.Title ~= nil
		ContextActionService:BindActionAtPriority("Vantage" .. action, self:_handler(action), touchButton, P, table.unpack(inputs))
		if touchButton then
			ContextActionService:SetTitle("Vantage" .. action, spec.Title)
		end
	end
	self.Binds = binds
end

function WeaponInput:ConsumeSlotRequest()
	local r = self.SlotRequest
	self.SlotRequest = nil
	return r
end

function WeaponInput:SetBlocked(blocked: boolean)
	self.Blocked = blocked
	if blocked then
		self.FireHeld = false
		self.AltHeld = false
		self._pendingFire = nil
		self._chord = false
	end
end

function WeaponInput:Destroy()
	ContextActionService:UnbindAction("VantageFire")
	ContextActionService:UnbindAction("VantageSlots")
	for action in ACTIONS do
		ContextActionService:UnbindAction("Vantage" .. action)
	end
	self._focus:Disconnect()
	self._wheel:Disconnect()
	if self._autoInspect then
		self._autoInspect:Disconnect()
	end
end

return WeaponInput
