--[[
	Installer

	Puts the CameraLock LocalScript into StarterPlayer.StarterCharacterScripts
	and keeps it up to date. Safety rules:

	* Never runs during a playtest (those edits would be thrown away).
	* Only touches scripts it installed (tagged with the TAG attribute). Other
	  camera lock scripts it finds are reported as conflicts, never changed.
	* Won't overwrite hand edits to an installed runtime unless asked to.
	* Every change is a single undo step (Ctrl+Z).
--]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(script.Parent.Config)

local TEMPLATE = script.Parent.Templates.CameraLock

local Installer = {}

Installer.VERSION = "0.0.1"
Installer.TAG = "CameraLockPluginVersion" -- attribute on scripts this plugin installed
Installer.FINGERPRINT = "CameraLockFingerprint"
Installer.SCRIPT_NAME = "CameraLock"

-- Marker unique to the camera lock code; used to spot copies we didn't install.
local SIGNATURE = "UpdateCCam"

function Installer.getContainer()
	return StarterPlayer:FindFirstChildOfClass("StarterCharacterScripts")
end

local function isOurs(inst)
	return inst:IsA("LocalScript") and inst:GetAttribute(Installer.TAG) ~= nil
end

local function sourceOf(scriptInstance)
	local ok, source = pcall(function()
		return scriptInstance.Source
	end)
	return ok and source or ""
end

-- Hash of the install's code (bootstrap + runtime), stored at install time so
-- hand edits can be spotted later even after the plugin's template changes.
local function fingerprint(bootstrap)
	local runtime = bootstrap:FindFirstChild("CameraLockRuntime")
	local code = sourceOf(bootstrap) .. "\0" .. (runtime and sourceOf(runtime) or "")
	local hash = 5381
	for i = 1, #code do
		hash = (hash * 33 + string.byte(code, i)) % 4294967296
	end
	return string.format("%08x:%d", hash, #code)
end

-- true: code was edited since install. "unknown": installed by an early build, which
-- stored no fingerprint and can't be checked. false: untouched.
local function isModified(installed)
	local stored = installed:GetAttribute(Installer.FINGERPRINT)
	if type(stored) == "string" then
		return fingerprint(installed) ~= stored
	end
	return if fingerprint(installed) == fingerprint(TEMPLATE) then false else "unknown"
end

-- Other scripts that would also bind the lock key. Running two at once makes
-- the camera fight itself, so the UI warns about these.
local function findConflicts(installed)
	local conflicts = {}
	for _, root in { StarterPlayer, game:GetService("StarterGui"), game:GetService("ReplicatedFirst") } do
		for _, inst in root:GetDescendants() do
			-- (IsDescendantOf(nil) is true for every parented instance, hence the guard)
			local insideInstall = installed ~= nil and (inst == installed or inst:IsDescendantOf(installed))
			if inst:IsA("LocalScript") and not insideInstall then
				local looksLikeCameraLock = inst.Name == Installer.SCRIPT_NAME
					or string.find(sourceOf(inst), SIGNATURE, 1, true) ~= nil
				if looksLikeCameraLock or isOurs(inst) then
					table.insert(conflicts, inst)
				end
			end
		end
	end
	return conflicts
end

-- Describes the current install state of this place.
function Installer.inspect()
	local container = Installer.getContainer()
	local installed = nil
	if container then
		for _, child in container:GetChildren() do
			if isOurs(child) then
				installed = child
				break
			end
		end
	end
	local version = installed and installed:GetAttribute(Installer.TAG)
	local stored = installed and installed:GetAttribute(Installer.FINGERPRINT)
	return {
		container = container,
		installed = installed,
		version = version,
		modified = installed ~= nil and isModified(installed),
		-- Older code than this plugin ships, even under the same version label
		outdated = installed ~= nil
			and (version ~= Installer.VERSION or (type(stored) == "string" and stored ~= fingerprint(TEMPLATE))),
		conflicts = findConflicts(installed),
	}
end

-- Runs fn as one undoable change. Returns ok, errorMessage.
local function withUndo(name, fn)
	if RunService:IsRunning() then
		return false, "Stop the playtest first - changes made while playing are discarded."
	end
	local recording = ChangeHistoryService:TryBeginRecording(name)
	if not recording then
		return false, "Studio is busy with another change. Try again in a moment."
	end
	local ok, err = pcall(fn)
	ChangeHistoryService:FinishRecording(
		recording,
		if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

--[[
	Installs a fresh copy of the runtime with the given settings, replacing a
	previous install. options.overwriteModified must be true to replace an
	install whose code was edited by hand.
	Returns ok, message, installedScript.
--]]
function Installer.install(settings, options)
	options = options or {}

	local invalid = Config.validate(settings)
	if invalid then
		return false, invalid
	end

	local state = Installer.inspect()
	if not state.container then
		return false, "StarterPlayer has no StarterCharacterScripts folder."
	end
	if state.installed and state.modified and not options.overwriteModified then
		return false, if state.modified == "unknown"
			then "The installed CameraLock is from an older plugin, so hand edits can't be checked. Confirm to overwrite it."
			else "The installed CameraLock has been edited by hand. Confirm to overwrite it."
	end

	local newScript
	local ok, err = withUndo("Install Camera Lock", function()
		newScript = TEMPLATE:Clone()
		newScript.Name = Installer.SCRIPT_NAME
		newScript.Enabled = true
		Config.writeAttributes(newScript, settings)
		newScript:SetAttribute(Installer.TAG, Installer.VERSION)
		newScript:SetAttribute(Installer.FINGERPRINT, fingerprint(newScript))
		newScript.Parent = state.container
		if state.installed then
			state.installed.Parent = nil -- not Destroy(), so Ctrl+Z can restore it
		end
	end)
	if not ok then
		return false, err
	end

	local verb = state.installed and "Reinstalled" or "Installed"
	return true, `{verb} CameraLock v{Installer.VERSION} in StarterCharacterScripts.`, newScript
end

-- Writes settings to the existing install without touching its code.
function Installer.applySettings(settings)
	local invalid = Config.validate(settings)
	if invalid then
		return false, invalid
	end
	local state = Installer.inspect()
	if not state.installed then
		return false, "CameraLock is not installed yet."
	end
	local ok, err = withUndo("Update Camera Lock settings", function()
		Config.writeAttributes(state.installed, settings)
	end)
	if not ok then
		return false, err
	end
	return true, "Settings saved to StarterCharacterScripts.CameraLock."
end

function Installer.uninstall()
	local state = Installer.inspect()
	if not state.installed then
		return false, "CameraLock is not installed."
	end
	local ok, err = withUndo("Remove Camera Lock", function()
		state.installed.Parent = nil -- not Destroy(), so Ctrl+Z can restore it
	end)
	if not ok then
		return false, err
	end
	return true, "Removed CameraLock. Press Ctrl+Z to undo."
end

return Installer
