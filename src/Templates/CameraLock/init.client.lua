--[[
	CameraLock (installed by the Camera Lock Generator plugin)

	Lives in StarterPlayer.StarterCharacterScripts, so a copy runs inside each
	character. Settings are this script's attributes; edit them with the
	plugin or in the Properties window.

	CONTROLS: Left Shift (or the configured LockKey) toggles lock-on.
	This script is only meant for PC.
--]]

-- Only run inside a character (the plugin's own disabled template must stay idle)
if not script.Parent:IsA("Model") then
	return
end

local CameraLock = require(script:WaitForChild("CameraLockRuntime"))

local config = CameraLock.readConfig(script)
local stop = CameraLock.start(script.Parent, config)

-- Live tuning: attribute edits made during a playtest apply immediately.
script.AttributeChanged:Connect(function(name)
	if CameraLock.DEFAULTS[name] ~= nil then
		config[name] = CameraLock.decode(name, script:GetAttribute(name))
	end
end)

script.Destroying:Connect(stop)
