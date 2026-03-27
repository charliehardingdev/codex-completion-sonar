# Codex Completion Sonar

Codex Completion Sonar is a lightweight macOS menu bar utility that plays a custom sound when Codex finishes a reply.

It is designed for people who run Codex alongside music, multiple desktops, or long-running tasks and want a fast audible cue when the final answer lands.

All included presets are generated with code: AI-made sounds for an AI workflow.

## Features

- Menu bar utility with a compact Matrix-inspired icon
- Detects final Codex replies from the local Codex log database
- Built-in volume slider
- Built-in sound switcher with ten code-generated presets
- Open-at-login friendly
- Standalone macOS app bundle build with Swift and AppKit

## Requirements

- macOS
- Xcode command line tools or full Xcode
- `ffmpeg` if you want to regenerate the included sound presets

## Build

```bash
./build.sh
```

This builds:

```text
~/Applications/CodexCompletionSonar.app
```

## Install

If you just want the app, download `Codex Completion Sonar.app.zip` from the repository, unzip it, and open `Codex Completion Sonar.app`.

If you want to build and install from source:

```bash
./install.sh
```

The installer:

- builds the app
- writes a user LaunchAgent
- starts the app
- adds it to macOS login items

## Sound Presets

Preset sounds are generated into:

```text
~/.codex/completion_sound/presets
```

To regenerate them:

```bash
./generate_presets.sh
```

The included sounds are procedural presets generated in code rather than sourced from sample packs.

## Repository Layout

- `CompletionSonar.swift`: main menu bar app
- `AppIcon.svg`: app icon source
- `build.sh`: app bundle build script
- `install.sh`: local installer
- `generate_presets.sh`: preset sound generator

## License

MIT
