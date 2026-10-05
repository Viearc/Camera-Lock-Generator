--[[
	Config

	Describes every camera lock setting for the plugin UI: how it is shown,
	parsed, validated and stored, plus the animation presets. Default values
	come from the runtime module itself so the two can never drift apart.

	Settings are stored as attributes on the installed CameraLock script.
	Enum settings are stored by name (e.g. "LeftShift").
--]]

local Runtime = require(script.Parent.Templates.CameraLock.CameraLockRuntime)

local Config = {}

Config.DEFAULTS = Runtime.DEFAULTS

-- Easing curves offered in the dropdowns. The runtime accepts any
-- "<EasingStyle> <EasingDirection>" pair; this is just the menu.
Config.EASINGS = { "Smoothstep", "Linear" }
for _, style in { "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic", "Bounce" } do
	for _, direction in { "Out", "InOut", "In" } do
		table.insert(Config.EASINGS, `{style} {direction}`)
	end
end

-- kind: "KeyCode" | "number" | "Vector3" | "easing" | "image".
-- section: "basic" and "animation" are always visible; "advanced" is collapsible.
Config.FIELDS = {
	{ key = "LockKey", label = "Lock Key", kind = "KeyCode", section = "basic",
		hint = "Key that toggles lock-on, e.g. LeftShift, Q, ButtonL3" },
	{ key = "LockRadius", label = "Lock Radius", kind = "number", section = "basic",
		hint = "Max horizontal distance to a target (studs)" },
	{ key = "CameraOffset", label = "Camera Offset", kind = "Vector3", section = "basic",
		hint = "Camera position relative to the character (x, y, z)" },
	{ key = "LockedCursorIcon", label = "Lock-On Icon", kind = "image", section = "basic",
		hint = "Snaps onto the target's head while locked (default: shift-lock icon). Blank = no icon" },
	{ key = "ReticleSize", label = "Icon Size", kind = "number", section = "basic",
		hint = "Size of the lock-on icon (pixels)" },

	{ key = "LockInTime", label = "Lock-On Time", kind = "number", section = "animation",
		hint = "Length of the pan onto a target (seconds)" },
	{ key = "LockInEasing", label = "Lock-On Easing", kind = "easing", section = "animation",
		hint = "Curve of the lock-on pan and the icon snap. Back / Elastic overshoot" },
	{ key = "ReticleSnapTime", label = "Icon Snap Time", kind = "number", section = "animation",
		hint = "How long the icon takes to snap onto a target's head (seconds)" },
	{ key = "UnlockTime", label = "Unlock Time", kind = "number", section = "animation",
		hint = "Length of the pan back to the free camera (seconds)" },
	{ key = "UnlockEasing", label = "Unlock Easing", kind = "easing", section = "animation",
		hint = "Curve of the unlock pan" },
	{ key = "CameraSmoothing", label = "Camera Smoothing", kind = "number", section = "animation",
		hint = "How tightly the camera follows while locked. Lower = smoother" },
	{ key = "TrackFadeTime", label = "Track Fade Time", kind = "number", section = "animation",
		hint = "Fade when walking on top of / away from the target (seconds)" },
	{ key = "RotationResponsiveness", label = "Turn Responsiveness", kind = "number", section = "animation",
		hint = "How quickly the character turns to face the target" },
	{ key = "CollisionRecovery", label = "Wall Recovery", kind = "number", section = "animation",
		hint = "How quickly the camera eases back out after a wall clears" },

	{ key = "SwitchDeadzone", label = "Switch Deadzone", kind = "number", section = "advanced",
		hint = "A new target must be this much closer to take over (studs)" },
	{ key = "SwitchCooldown", label = "Switch Cooldown", kind = "number", section = "advanced",
		hint = "Minimum seconds between target switches" },
	{ key = "SearchInterval", label = "Search Interval", kind = "number", section = "advanced",
		hint = "Seconds between searches for a better target" },
	{ key = "OnTopEnter", label = "On-Top Enter", kind = "number", section = "advanced",
		hint = "Stop turning toward the target when closer than this" },
	{ key = "OnTopExit", label = "On-Top Exit", kind = "number", section = "advanced",
		hint = "Resume turning when farther than this (must exceed Enter)" },
	{ key = "MaxTorque", label = "Max Torque", kind = "number", section = "advanced",
		hint = "Turning strength while locked" },
	{ key = "CollisionPivotOffset", label = "Collision Pivot", kind = "Vector3", section = "advanced",
		hint = "Point the camera is pulled toward near walls (x, y, z)" },
	{ key = "CollisionPadding", label = "Collision Padding", kind = "number", section = "advanced",
		hint = "Studs kept between the camera and a wall" },
	{ key = "CollisionMinDistance", label = "Collision Min Distance", kind = "number", section = "advanced",
		hint = "Closest the camera gets to the pivot (studs)" },
}

-- One-click animation feels. Each sets every animation field.
Config.PRESETS = {
	{ name = "Snappy", values = {
		LockInTime = 0.2, LockInEasing = "Quad Out", UnlockTime = 0.2, UnlockEasing = "Quad Out", ReticleSnapTime = 0.08,
		CameraSmoothing = 30, TrackFadeTime = 0.2, RotationResponsiveness = 100, CollisionRecovery = 12 } },
	{ name = "Default", values = {
		LockInTime = Runtime.DEFAULTS.LockInTime, LockInEasing = Runtime.DEFAULTS.LockInEasing,
		UnlockTime = Runtime.DEFAULTS.UnlockTime, UnlockEasing = Runtime.DEFAULTS.UnlockEasing,
		ReticleSnapTime = Runtime.DEFAULTS.ReticleSnapTime,
		CameraSmoothing = Runtime.DEFAULTS.CameraSmoothing, TrackFadeTime = Runtime.DEFAULTS.TrackFadeTime,
		RotationResponsiveness = Runtime.DEFAULTS.RotationResponsiveness,
		CollisionRecovery = Runtime.DEFAULTS.CollisionRecovery } },
	{ name = "Smooth", values = {
		LockInTime = 0.8, LockInEasing = "Sine InOut", UnlockTime = 0.7, UnlockEasing = "Sine InOut", ReticleSnapTime = 0.25,
		CameraSmoothing = 6, TrackFadeTime = 0.6, RotationResponsiveness = 25, CollisionRecovery = 4 } },
	{ name = "Cinematic", values = {
		LockInTime = 1.2, LockInEasing = "Quint InOut", UnlockTime = 1, UnlockEasing = "Cubic InOut", ReticleSnapTime = 0.35,
		CameraSmoothing = 3, TrackFadeTime = 0.9, RotationResponsiveness = 12, CollisionRecovery = 3 } },
}

-- Name of the preset the settings match exactly, or nil.
function Config.matchingPreset(settings)
	for _, preset in Config.PRESETS do
		local matches = true
		for key, value in preset.values do
			if settings[key] ~= value then
				matches = false
				break
			end
		end
		if matches then
			return preset.name
		end
	end
	return nil
end

-- Numeric limits live in the runtime so typed-in attributes get the same clamp
Config.FIELDS_BY_KEY = {}
for _, field in Config.FIELDS do
	Config.FIELDS_BY_KEY[field.key] = field
	local range = Runtime.RANGES[field.key]
	if range then
		field.min, field.max = range[1], range[2]
	end
	assert(field.kind ~= "number" or range, `{field.key} has no range in CameraLockRuntime.RANGES`)
end

local function round(n)
	-- Keep text boxes readable: 0.6 instead of 0.60000002384186
	return tostring(math.round(n * 1000) / 1000)
end

function Config.defaults()
	return table.clone(Config.DEFAULTS)
end

-- Value -> text for a TextBox.
function Config.format(field, value)
	if field.kind == "KeyCode" then
		return value.Name
	elseif field.kind == "easing" or field.kind == "image" then
		return value
	elseif field.kind == "Vector3" then
		return `{round(value.X)}, {round(value.Y)}, {round(value.Z)}`
	end
	return round(value)
end

-- Text from a TextBox -> value, or nil plus an error message.
function Config.parse(field, text)
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")

	if field.kind == "KeyCode" then
		local ok, item = pcall(function()
			return Enum.KeyCode[text]
		end)
		if not ok or not item or item == Enum.KeyCode.Unknown then
			return nil, `"{text}" is not a KeyCode name (try LeftShift, Q, Tab)`
		end
		return item
	elseif field.kind == "easing" then
		if not Runtime.isEasing(text) then
			return nil, `"{text}" is not an easing (try Sine InOut, Quad Out, Linear)`
		end
		return text
	elseif field.kind == "image" then
		if text == "" then
			return ""
		elseif string.match(text, "^%d+$") then
			return "rbxassetid://" .. text -- a bare asset id
		elseif string.match(text, "^rbxasset://") or string.match(text, "^rbxassetid://%d+$")
			or string.match(text, "^https?://") then
			return text
		end
		return nil, `{field.label} must be an asset id, rbxassetid://..., rbxasset://... or blank`
	elseif field.kind == "Vector3" then
		local parts = {}
		for part in string.gmatch(text, "[^,%s]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts ~= 3 or not (parts[1] and parts[2] and parts[3]) then
			return nil, `{field.label} needs three numbers, e.g. 6, 3, 11`
		end
		return Vector3.new(parts[1], parts[2], parts[3])
	end

	local n = tonumber(text)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return nil, `{field.label} must be a number`
	end
	if n < field.min or n > field.max then
		return nil, `{field.label} must be between {field.min} and {field.max}`
	end
	return n
end

-- Checks a whole settings table, including rules that span fields.
-- Returns nil when valid, otherwise an error message.
function Config.validate(settings)
	for _, field in Config.FIELDS do
		local value = settings[field.key]
		local expected = typeof(Config.DEFAULTS[field.key])
		if typeof(value) ~= expected then
			return `{field.label} is missing or has the wrong type`
		end
		if field.kind == "number" and (value ~= value or value < field.min or value > field.max) then
			return `{field.label} must be between {field.min} and {field.max}`
		end
		if field.kind == "easing" and not Runtime.isEasing(value) then
			return `{field.label} is not a known easing`
		end
	end
	if settings.OnTopExit <= settings.OnTopEnter then
		return "On-Top Exit must be greater than On-Top Enter"
	end
	return nil
end

function Config.encode(key, value)
	if typeof(value) == "EnumItem" then
		return value.Name
	end
	return value
end

function Config.writeAttributes(instance, settings)
	for key in Config.DEFAULTS do
		instance:SetAttribute(key, Config.encode(key, settings[key]))
	end
end

function Config.readAttributes(instance)
	return Runtime.readConfig(instance)
end

-- plugin:SetSetting only stores JSON-friendly values. Vector3s are saved as
-- { x, y, z } maps: arrays come back from disk with string keys ("1", "2", ...).
function Config.serialize(settings)
	local out = {}
	for key, value in settings do
		if typeof(value) == "Vector3" then
			out[key] = { x = value.X, y = value.Y, z = value.Z }
		else
			out[key] = Config.encode(key, value)
		end
	end
	return out
end

function Config.deserialize(data)
	local settings = Config.defaults()
	if type(data) ~= "table" then
		return settings
	end
	for key, default in Config.DEFAULTS do
		local value = data[key]
		if typeof(default) == "Vector3" and type(value) == "table" then
			-- current { x, y, z } maps, plus arrays saved by earlier builds
			local x = tonumber(value.x or value[1] or value["1"])
			local y = tonumber(value.y or value[2] or value["2"])
			local z = tonumber(value.z or value[3] or value["3"])
			if x and y and z then
				settings[key] = Vector3.new(x, y, z)
			end
		elseif value ~= nil and typeof(default) ~= "Vector3" then
			settings[key] = Runtime.decode(key, value)
		end
	end
	return settings
end

function Config.equal(a, b)
	for key in Config.DEFAULTS do
		if a[key] ~= b[key] then
			return false
		end
	end
	return true
end

return Config
