# Camera Lock Generator (v0.0.1)

A Roblox Studio plugin that configures the camera lock system and installs it
into `StarterPlayer.StarterCharacterScripts`.

## Layout

```
src/
  Main.server.lua          plugin entry: toolbar button + dock widget
  Widget.lua               settings panel UI
  Config.lua               field list, parsing, validation (defaults come from the runtime)
  Installer.lua            install / apply settings / reinstall / remove
  Templates/CameraLock/
    init.client.lua        the LocalScript that gets installed (reads its attributes)
    CameraLockRuntime.lua  the camera behaviour (ModuleScript)
build/CameraLockGenerator.rbxm  prebuilt plugin
```

The layout is Rojo-compatible: `rojo build -o build/CameraLockGenerator.rbxm`
rebuilds the plugin from `src/`.

## Installing the plugin

Copy `build/CameraLockGenerator.rbxm` into Studio's local plugins folder
(Plugins tab > Plugins Folder; on macOS `~/Documents/Roblox/Plugins`).
Alternatively, right-click the `CameraLockGenerator` folder in Studio and choose
**Save as Local Plugin**.

The first time you click Install, Studio may ask you to allow script injection.
That's needed to add the LocalScript to your place.

## Using it

Plugins tab > **Camera Lock Generator** opens the panel.

- **Install**: adds `CameraLock` to StarterCharacterScripts with the settings shown.
- **Apply Settings**: writes changed settings to the installed script (as attributes).
- **Reinstall**: replaces the installed code with the plugin's version, which is how
  upgrades happen. It asks for a second click first if the installed code was edited by hand.
- **Remove**: deletes the plugin's install. Other scripts are never touched.

The **Animation** section controls how lock-on feels:

- Lock-On Time / Unlock Time and their easing curves. Pick a curve from the dropdown:
  Smoothstep, Linear, or any Roblox EasingStyle + direction. Back and Elastic overshoot.
- Camera Smoothing, Track Fade Time, Turn Responsiveness, Wall Recovery.
- Presets (Snappy / Default / Smooth / Cinematic) fill in every animation field at once.
  The button for the preset you're on is highlighted.

While locked, the real cursor is hidden and held at the centre of the screen, and
Roblox's shift-lock icon (`rbxasset://textures/MouseLockedCursor.png`) snaps onto the
target's head and follows it. It snaps again whenever the target changes; **Icon Snap
Time** and the Lock-On easing control how. Set **Lock-On Icon** to an asset id to use
your own image, or leave it blank for none. **Icon Size** sets its size. The cursor is
restored when you unlock.

The plugin's toolbar button uses the same shift-lock icon.

Every action is a single undo step. The plugin refuses to run during a playtest,
and it warns if it finds other camera lock scripts that would fight over the camera.

Settings are attributes on the installed `CameraLock` script, so you can also
edit them in the Properties window. Editing the copy inside your character
during a playtest retunes it live.
