--[[
	Camera Lock Generator plugin - entry point

	Adds a "Camera Lock Generator" toolbar button that opens a dock widget for tuning
	settings and installing the CameraLock LocalScript into
	StarterPlayer.StarterCharacterScripts.
--]]

local RunService = game:GetService("RunService")

-- `plugin` only exists when this runs as a plugin, so a copy of this folder
-- sitting in a place does nothing. Skip playtest DataModels too: edits there
-- are discarded and every widget would appear twice.
if not plugin or RunService:IsRunning() then
	return
end

local Widget = require(script.Parent.Widget)

local toolbar = plugin:CreateToolbar("Camera Lock Generator")
local toggleButton = toolbar:CreateButton(
	"CameraLockSettings",
	"Configure and install the camera lock system",
	"rbxasset://textures/MouseLockedCursor.png", -- Roblox's shift-lock icon
	"Camera Lock Generator"
)
toggleButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"CameraLockSettings",
	DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Right,
		false, -- initially enabled
		false, -- override saved enabled state
		320, 560, -- default size
		260, 300 -- minimum size
	)
)
widget.Name = "CameraLockSettings"
widget.Title = "Camera Lock Generator"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local unmount = Widget.mount(plugin, widget)

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

local function syncButton()
	toggleButton:SetActive(widget.Enabled)
end
widget:GetPropertyChangedSignal("Enabled"):Connect(syncButton)
syncButton()

plugin.Unloading:Connect(unmount)
