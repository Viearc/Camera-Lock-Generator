--[[
	CameraLockRuntime

	Lock-on camera for PC. Press the lock key to lock the camera onto the
	nearest Humanoid in range, press it again to release.

	The CameraLock LocalScript (this module's parent) reads settings from its
	own attributes and calls CameraLock.start(). Attributes can be edited from
	the Camera Lock Generator plugin or directly in the Properties window; changes made
	while the game is running are picked up live.

	This module has no side effects when required, so the plugin can require
	it to read DEFAULTS.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CameraLock = {}

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
CameraLock.DEFAULTS = {
	LockKey = Enum.KeyCode.LeftShift,
	LockRadius = 100,          -- studs (horizontal distance)
	SwitchDeadzone = 10,       -- a new target must be this much closer to replace the current one
	SwitchCooldown = 1.0,      -- minimum seconds between target switches
	SearchInterval = 0.1,      -- how often to look for a better target while one is locked
	OnTopEnter = 3,            -- closer than this: stop rotating toward the target
	OnTopExit = 6,             -- farther than this: resume rotating toward the target
	CameraOffset = Vector3.new(6, 3, 11),
	-- Icon that snaps onto the target's head while locked ("" shows none).
	-- The real cursor is hidden and held at the screen centre meanwhile.
	LockedCursorIcon = "rbxasset://textures/MouseLockedCursor.png", -- Roblox's shift-lock cursor
	ReticleSize = 32,          -- icon size (pixels)

	-- Animation
	LockInTime = 0.5,          -- lock-on pan length (seconds)
	LockInEasing = "Smoothstep",
	UnlockTime = 0.5,          -- unlock pan length (seconds)
	UnlockEasing = "Smoothstep",
	ReticleSnapTime = 0.15,    -- icon's snap onto a (new) target's head, using LockInEasing
	CameraSmoothing = 12,      -- higher = snappier camera (frame-rate independent)
	TrackFadeTime = 0.4,       -- fade time for on-top transitions
	RotationResponsiveness = 40,
	MaxTorque = 50000,

	-- Wall collision
	CollisionPivotOffset = Vector3.new(0, 2, 0), -- camera is pulled toward this point (around head height)
	CollisionPadding = 0.6,     -- studs kept between the camera and a wall
	CollisionMinDistance = 1.5, -- the camera never gets closer to the pivot than this
	CollisionRecovery = 6,      -- how quickly the camera eases back out after a wall clears
}

-- Allowed { min, max } for numeric settings. Values typed straight into the
-- Properties window are clamped to these, since e.g. a negative smoothing
-- sends the camera flying and a zero duration divides by zero. The plugin
-- validates against the same table.
CameraLock.RANGES = {
	LockRadius = { 1, 2000 },
	SwitchDeadzone = { 0, 500 },
	SwitchCooldown = { 0, 10 },
	SearchInterval = { 0, 5 },
	OnTopEnter = { 0, 100 },
	OnTopExit = { 0, 100 },
	ReticleSize = { 4, 256 },
	LockInTime = { 0.01, 5 },
	UnlockTime = { 0.01, 5 },
	ReticleSnapTime = { 0.01, 2 },
	CameraSmoothing = { 0.1, 100 },
	TrackFadeTime = { 0.01, 5 },
	RotationResponsiveness = { 5, 200 },
	MaxTorque = { 0, 10000000 },
	CollisionPadding = { 0, 5 },
	CollisionMinDistance = { 0, 20 },
	CollisionRecovery = { 0.1, 100 },
}

local BIND_NAME = "UpdateCCam"

----------------------------------------------------------------------
-- Easing. Names are "Smoothstep", "Linear", or "<EasingStyle> <EasingDirection>"
-- such as "Quad Out" or "Sine InOut" (any Enum.EasingStyle / EasingDirection).
----------------------------------------------------------------------
local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local easingCache = {} -- [name] = { style, direction } or false when invalid

local function parseEasing(name)
	local cached = easingCache[name]
	if cached == nil then
		cached = false
		if name == "Linear" then
			cached = { Enum.EasingStyle.Linear, Enum.EasingDirection.InOut }
		elseif type(name) == "string" then
			local styleName, directionName = string.match(name, "^(%a+) (%a+)$")
			local ok, style, direction = pcall(function()
				return Enum.EasingStyle[styleName], Enum.EasingDirection[directionName]
			end)
			if ok and style and direction then
				cached = { style, direction }
			end
		end
		easingCache[name] = cached
	end
	return cached
end

function CameraLock.isEasing(name)
	return name == "Smoothstep" or parseEasing(name) ~= false
end

-- Eased 0..1 progress. Back / Elastic styles intentionally overshoot.
function CameraLock.ease(name, t)
	t = math.clamp(t, 0, 1)
	local easing = parseEasing(name)
	if not easing then
		return smoothstep(t)
	end
	return TweenService:GetValue(t, easing[1], easing[2])
end

-- Converts an attribute value to a setting. Enum settings are stored by name
-- (e.g. "LeftShift"); anything missing or of the wrong type uses the default.
function CameraLock.decode(key, value)
	local default = CameraLock.DEFAULTS[key]
	if value == nil then
		return default
	end
	if typeof(default) == "EnumItem" then
		if type(value) == "string" then
			local ok, item = pcall(function()
				return default.EnumType[value]
			end)
			if ok and item then
				return item
			end
		end
	elseif typeof(value) == typeof(default) and value == value then -- value == value rejects NaN
		local range = CameraLock.RANGES[key]
		if range then
			local clamped = math.clamp(value, range[1], range[2])
			if clamped ~= value then
				warn(`[CameraLock] {key} = {value} is outside {range[1]}..{range[2]}; using {clamped}`)
			end
			return clamped
		end
		if not (string.find(key, "Easing$") and not CameraLock.isEasing(value)) then
			return value
		end
	end
	warn(`[CameraLock] Ignoring invalid {key} attribute ({tostring(value)}); using the default`)
	return default
end

function CameraLock.readConfig(source)
	local config = {}
	for key in CameraLock.DEFAULTS do
		config[key] = CameraLock.decode(key, source:GetAttribute(key))
	end
	-- Early builds used one TransitionTime for both directions
	local legacy = source:GetAttribute("TransitionTime")
	if type(legacy) == "number" and legacy > 0 then
		if source:GetAttribute("LockInTime") == nil then config.LockInTime = legacy end
		if source:GetAttribute("UnlockTime") == nil then config.UnlockTime = legacy end
	end
	return config
end

-- Starts the camera lock for `Character`. CONFIG is read live, so callers may
-- change its fields while running. Returns a function that stops everything.
function CameraLock.start(Character, CONFIG)
	local Camera = workspace.CurrentCamera
	local Humanoid = Character:WaitForChild("Humanoid")
	local RootPart = Character:WaitForChild("HumanoidRootPart")

	----------------------------------------------------------------------
	-- State
	----------------------------------------------------------------------
	local isLocked = false
	local isUnlocking = false
	local isBound = false
	local cameraOwned = false

	local targetHumanoid = nil
	local targetRoot = nil
	local lastSwitchTime = 0
	local lastSearchTime = 0

	local lastDir = Vector3.new(0, 0, -1) -- last flat direction toward a target
	local isOnTop = false
	local trackStrength = 1               -- 1 = tracking target, 0 = free movement

	local smoothedCFrame = nil
	local lockFrom = nil
	local lockElapsed = 0
	local unlockFrom = nil
	local unlockElapsed = 0

	-- Restored on unlock; captured when locking so runtime changes the game
	-- makes in between are respected
	local originalAutoRotate = Humanoid.AutoRotate
	local savedCameraType = Enum.CameraType.Custom
	local connections = {}

	-- Cursor: hidden and held at the screen centre while locked
	local cursorOwned = false
	local savedMouseBehavior = nil
	local savedMouseIconEnabled = nil

	-- The engine can stop a previous character's copy mid-lock (e.g. a
	-- respawn via LoadCharacter) before it cleans up. Undo what it left.
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, leftover in playerGui:GetChildren() do
		if leftover.Name == "CameraLockReticle" then
			local locked = leftover:GetAttribute("Locked") -- the CameraType it replaced
			if locked then
				local ok, cameraType = pcall(function()
					return Enum.CameraType[locked]
				end)
				Camera.CameraType = if ok and cameraType then cameraType else Enum.CameraType.Custom
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end
			leftover:Destroy()
		end
	end

	-- Reticle: the lock icon drawn over the target's head. Its Locked
	-- attribute marks that this copy currently owns the camera and mouse,
	-- and holds the name of the CameraType to restore.
	local reticleGui = Instance.new("ScreenGui")
	reticleGui.Name = "CameraLockReticle"
	reticleGui.IgnoreGuiInset = true -- so GUI pixels match Camera:WorldToViewportPoint
	reticleGui.DisplayOrder = 10
	reticleGui.ResetOnSpawn = false -- this script cleans it up itself
	local reticle = Instance.new("ImageLabel")
	reticle.Name = "Reticle"
	reticle.AnchorPoint = Vector2.new(0.5, 0.5)
	reticle.BackgroundTransparency = 1
	reticle.Visible = false
	reticle.Parent = reticleGui
	reticleGui.Parent = playerGui

	local reticleTarget = nil  -- the root part the reticle is snapping/snapped to
	local reticleFrom = nil    -- screen position the current snap started from
	local reticlePos = nil     -- screen position drawn last frame
	local reticleElapsed = 0

	-- Wall collision
	local collisionRatio = 1 -- 1 = camera at full distance, <1 = pulled in by a wall
	local filterDirty = true -- rebuild the camera's ignore list when a character appears or disappears
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true -- ignore parts you can walk through
	rayParams.IgnoreWater = true
	rayParams.FilterDescendantsInstances = { Character }

	----------------------------------------------------------------------
	-- Target registry: humanoids are tracked as they appear/disappear,
	-- so we never scan the whole workspace during gameplay.
	----------------------------------------------------------------------
	local targets = {} -- [Humanoid] = true

	local function register(inst)
		if inst:IsA("Humanoid") then
			targets[inst] = true
			filterDirty = true
		end
	end

	table.insert(connections, workspace.DescendantAdded:Connect(register))
	table.insert(connections, workspace.DescendantRemoving:Connect(function(inst)
		if targets[inst] then
			targets[inst] = nil
			filterDirty = true
		end
	end))
	for _, inst in workspace:GetDescendants() do
		register(inst)
	end

	----------------------------------------------------------------------
	-- Rotation control
	----------------------------------------------------------------------
	local attachment = Instance.new("Attachment")
	attachment.Name = "CameraLockAttachment"
	attachment.Parent = RootPart

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = attachment
	alignOri.MaxTorque = 0
	alignOri.Responsiveness = CONFIG.RotationResponsiveness
	alignOri.Enabled = false
	alignOri.Parent = RootPart

	-- factor: 0..1, how strongly we rotate the character toward the target.
	-- The humanoid's own auto-rotation only runs when we aren't steering.
	local function setRotationControl(factor)
		alignOri.MaxTorque = factor * CONFIG.MaxTorque
		local wantAutoRotate = factor < 0.05
		if Humanoid.AutoRotate ~= wantAutoRotate then
			Humanoid.AutoRotate = wantAutoRotate
		end
	end

	----------------------------------------------------------------------
	-- Helpers
	----------------------------------------------------------------------
	local function flatDistance(a, b)
		local d = a - b
		return math.sqrt(d.X * d.X + d.Z * d.Z)
	end

	-- Health alone isn't enough: a humanoid can be Dead with health left
	-- (e.g. ChangeState(Dead) from a script).
	local function isAlive(humanoid)
		return humanoid.Parent ~= nil
			and humanoid.Health > 0
			and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
	end

	local function computeFreeCamCFrame()
		local forward = RootPart.CFrame.LookVector
		local camPos = RootPart.Position - forward * 12 + Vector3.new(0, 3, 0)
		local lookAt = RootPart.Position + forward * 20 + Vector3.new(0, 1, 0)
		return CFrame.lookAt(camPos, lookAt)
	end

	-- Pulls the camera in front of walls. It moves in instantly (so it never
	-- clips through geometry) and eases back out once the wall is gone.
	local function applyCollision(cf, dt)
		-- Characters (players and NPCs) shouldn't push the camera around.
		-- The ignore list is only rebuilt when a character appears or disappears.
		if filterDirty then
			filterDirty = false
			local ignore = { Character }
			for humanoid in targets do
				local model = humanoid.Parent
				if model and model ~= Character then
					table.insert(ignore, model)
				end
			end
			rayParams.FilterDescendantsInstances = ignore
		end

		local pivot = RootPart.Position + CONFIG.CollisionPivotOffset
		local offset = cf.Position - pivot
		local dist = offset.Magnitude
		if dist < 0.001 then
			return cf
		end

		local allowed = dist
		local hit = workspace:Raycast(pivot, offset, rayParams)
		if hit then
			allowed = math.max(hit.Distance - CONFIG.CollisionPadding, CONFIG.CollisionMinDistance)
		end
		local ratio = math.min(allowed / dist, 1)

		if ratio < collisionRatio then
			collisionRatio = ratio
		else
			local alpha = 1 - math.exp(-CONFIG.CollisionRecovery * dt)
			collisionRatio += (ratio - collisionRatio) * alpha
		end

		return CFrame.new(pivot + offset * collisionRatio) * cf.Rotation
	end

	----------------------------------------------------------------------
	-- Target selection
	----------------------------------------------------------------------
	local function updateTarget(now)
		local origin = RootPart.Position

		-- Validate the current target (cheap, runs every frame)
		local currentDist
		if targetRoot then
			if not isAlive(targetHumanoid) or targetRoot.Parent == nil then
				-- Target died or was removed: drop the lock instead of
				-- jumping to whoever else is in range.
				targetHumanoid, targetRoot = nil, nil
				return
			end
			currentDist = flatDistance(targetRoot.Position, origin)
			if currentDist > CONFIG.LockRadius then
				targetHumanoid, targetRoot, currentDist = nil, nil, nil
			end
		end

		-- With a valid target, only search occasionally and respect the switch cooldown
		if targetRoot then
			if now - lastSearchTime < CONFIG.SearchInterval then return end
			if now - lastSwitchTime < CONFIG.SwitchCooldown then return end
		end
		lastSearchTime = now

		-- A challenger must beat the current target by the deadzone,
		-- or simply be in range when we have no target.
		local bestHumanoid, bestRoot = targetHumanoid, targetRoot
		local bestDist = currentDist and (currentDist - CONFIG.SwitchDeadzone) or CONFIG.LockRadius

		for humanoid in targets do
			local model = humanoid.Parent
			if model and model ~= Character and isAlive(humanoid) then
				local root = humanoid.RootPart
				if root then
					local d = flatDistance(root.Position, origin)
					if d < bestDist then
						bestHumanoid, bestRoot, bestDist = humanoid, root, d
					end
				end
			end
		end

		if bestRoot ~= targetRoot then
			lastSwitchTime = now
			targetHumanoid, targetRoot = bestHumanoid, bestRoot
		end
	end

	----------------------------------------------------------------------
	-- Cursor
	----------------------------------------------------------------------
	-- Re-applied every locked frame: the default camera scripts (right-click
	-- drag, shift lock) also write MouseBehavior and would otherwise free it.
	local function holdCursor()
		if not cursorOwned then
			cursorOwned = true
			savedMouseBehavior = UserInputService.MouseBehavior
			savedMouseIconEnabled = UserInputService.MouseIconEnabled
		end
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		-- The reticle stands in for the cursor, so the real one stays hidden
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	end

	local function freeCursor()
		if not cursorOwned then return end
		cursorOwned = false
		-- Don't restore LockCenter: that would leave the cursor stuck after unlocking
		UserInputService.MouseBehavior = if savedMouseBehavior == Enum.MouseBehavior.LockCenter
			then Enum.MouseBehavior.Default
			else savedMouseBehavior
		UserInputService.MouseIconEnabled = savedMouseIconEnabled
	end

	----------------------------------------------------------------------
	-- Reticle
	----------------------------------------------------------------------
	local function headPosition(humanoid, root)
		local head = humanoid.Parent and humanoid.Parent:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head.Position
		end
		return root.Position + Vector3.new(0, 1.5, 0) -- headless rigs: roughly head height
	end

	local function hideReticle()
		reticle.Visible = false
		reticleTarget, reticleFrom, reticlePos = nil, nil, nil
	end

	-- Call after the camera has moved this frame so the projection is current.
	-- Each new target restarts the snap from wherever the icon is (the screen
	-- centre, where the cursor sat, on the first lock).
	local function updateReticle(dt)
		local icon = CONFIG.LockedCursorIcon
		if icon == "" then
			hideReticle()
			return
		end

		if targetRoot ~= reticleTarget then
			reticleTarget = targetRoot
			reticleFrom = reticlePos or Camera.ViewportSize / 2
			reticleElapsed = 0
		end
		reticleElapsed += dt

		local screen, onScreen = Camera:WorldToViewportPoint(headPosition(targetHumanoid, targetRoot))
		if not onScreen then
			reticle.Visible = false -- head behind the camera or off screen
			return
		end
		local goal = Vector2.new(screen.X, screen.Y)
		local a = CameraLock.ease(CONFIG.LockInEasing, reticleElapsed / CONFIG.ReticleSnapTime)
		reticlePos = reticleFrom:Lerp(goal, a)

		reticle.Image = icon
		reticle.Size = UDim2.fromOffset(CONFIG.ReticleSize, CONFIG.ReticleSize)
		reticle.Position = UDim2.fromOffset(reticlePos.X, reticlePos.Y)
		reticle.Visible = true
	end

	----------------------------------------------------------------------
	-- Release / unlock
	----------------------------------------------------------------------
	local function release()
		isLocked = false
		isUnlocking = false
		targetHumanoid, targetRoot = nil, nil
		lockFrom, unlockFrom, smoothedCFrame = nil, nil, nil
		isOnTop = false
		trackStrength = 1
		collisionRatio = 1

		if isBound then
			RunService:UnbindFromRenderStep(BIND_NAME)
			isBound = false
		end

		alignOri.Enabled = false
		alignOri.MaxTorque = 0
		Humanoid.AutoRotate = originalAutoRotate
		freeCursor()
		hideReticle()

		if cameraOwned then
			cameraOwned = false
			Camera.CameraType = savedCameraType
		end
		reticleGui:SetAttribute("Locked", nil)
	end

	local function startUnlock()
		if not isLocked then return end
		isLocked = false
		isUnlocking = true
		unlockElapsed = 0
		unlockFrom = Camera.CFrame
		freeCursor()
		hideReticle()
	end

	----------------------------------------------------------------------
	-- Per-frame update
	----------------------------------------------------------------------
	local function update(dt)
		if not isAlive(Humanoid) then
			release()
			return
		end

		-- Unlock animation: pan from the locked camera back to a free camera
		if isUnlocking then
			unlockElapsed += dt
			local a = CameraLock.ease(CONFIG.UnlockEasing, unlockElapsed / CONFIG.UnlockTime)
			Camera.CFrame = applyCollision(unlockFrom:Lerp(computeFreeCamCFrame(), a), dt)
			setRotationControl(trackStrength * (1 - math.clamp(a, 0, 1)))
			if unlockElapsed >= CONFIG.UnlockTime then
				release()
			end
			return
		end

		updateTarget(os.clock())
		if not targetRoot then
			startUnlock() -- auto-release: nothing left in range
			return
		end

		local origin = RootPart.Position
		local toTarget = targetRoot.Position - origin
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local dist = flat.Magnitude

		-- Hysteresis so "on top of target" doesn't flicker
		if not isOnTop and dist < CONFIG.OnTopEnter then
			isOnTop = true
		elseif isOnTop and dist > CONFIG.OnTopExit then
			isOnTop = false
		end

		local goal = isOnTop and 0 or 1
		local step = dt / CONFIG.TrackFadeTime
		trackStrength += math.clamp(goal - trackStrength, -step, step)
		local strength = smoothstep(trackStrength)

		-- Blend between the cached direction and the live direction to the target
		if dist >= 2 then
			lastDir = flat.Unit
		end
		local dir = lastDir
		if dist > 0.001 then
			dir = lastDir:Lerp(flat.Unit, strength)
		end
		if dir.Magnitude < 0.001 then
			dir = lastDir
		end

		local lookCF = CFrame.lookAt(origin, origin + dir)
		local desired = lookCF * CFrame.new(CONFIG.CameraOffset)

		-- Camera: eased lock-on pan first, then frame-rate independent smoothing
		local cf
		if lockElapsed < CONFIG.LockInTime then
			lockElapsed += dt
			local a = CameraLock.ease(CONFIG.LockInEasing, lockElapsed / CONFIG.LockInTime)
			cf = lockFrom:Lerp(desired, a)
		else
			local alpha = 1 - math.exp(-CONFIG.CameraSmoothing * dt)
			cf = (smoothedCFrame or desired):Lerp(desired, alpha)
		end
		-- Smooth the uncollided camera so wall pushback doesn't feed back into the smoothing
		smoothedCFrame = cf
		Camera.CFrame = applyCollision(cf, dt)

		-- Character rotation
		-- (clamped: an overshooting easing must not push torque past MaxTorque)
		local lockIn = math.clamp(CameraLock.ease(CONFIG.LockInEasing, lockElapsed / CONFIG.LockInTime), 0, 1)
		setRotationControl(strength * lockIn)
		holdCursor()
		updateReticle(dt)
		if strength > 0.01 then
			alignOri.CFrame = lookCF.Rotation
		end
	end

	----------------------------------------------------------------------
	-- Lock
	----------------------------------------------------------------------
	local function lock()
		if not isAlive(Humanoid) then return end

		-- Only lock if there is actually something to lock onto
		updateTarget(os.clock())
		if not targetRoot then return end

		-- Works both from idle and while an unlock animation is playing:
		-- the lock pan simply starts from wherever the camera currently is.
		isLocked = true
		isUnlocking = false
		unlockFrom = nil
		lockFrom = Camera.CFrame
		lockElapsed = 0
		smoothedCFrame = nil
		isOnTop = false
		trackStrength = 1
		collisionRatio = 1

		local look = RootPart.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude > 0.001 then
			lastDir = flatLook.Unit
		end

		-- Re-locking mid-unlock keeps the values saved by the first lock
		if not cameraOwned then
			savedCameraType = Camera.CameraType
			originalAutoRotate = Humanoid.AutoRotate
		end
		cameraOwned = true
		reticleGui:SetAttribute("Locked", savedCameraType.Name)
		Camera.CameraType = Enum.CameraType.Scriptable
		alignOri.Responsiveness = CONFIG.RotationResponsiveness -- may have been tuned live
		alignOri.Enabled = true
		holdCursor()

		if not isBound then
			isBound = true
			RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value, update)
		end
	end

	----------------------------------------------------------------------
	-- Input & cleanup
	----------------------------------------------------------------------
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.KeyCode ~= CONFIG.LockKey then return end
		if isLocked then
			startUnlock()
		else
			lock()
		end
	end))

	-- Dying resets to the free camera straight away
	table.insert(connections, Humanoid.Died:Connect(release))

	local stopped = false
	local function stop()
		if stopped then return end
		stopped = true
		release()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
		table.clear(targets)
		reticleGui:Destroy()
	end

	-- A respawn removes the old character without always destroying it (so
	-- its script never gets Destroying); stop as soon as it leaves the game.
	-- If the same character is put back later, Roblox runs this script again.
	table.insert(connections, Character.AncestryChanged:Connect(function()
		if not Character:IsDescendantOf(game) then
			stop()
		end
	end))

	return stop
end

return CameraLock
