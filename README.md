<!-- markdownlint-disable MD013 -->
<p align="center">
    <img alt="machine" width="200px" src="assets/icons/android/play_store_512.png">
</p>

<h1 align="center">
Machine, A Flutter-based code editor app.
</h1>

# Overview

Machine is first and foremost a code editor app. But, it offers an architecture to ease the process of building other editors.

Each editor is a plugin, that have access to the same building blocks (file opening/saving/caching, etc). It makes writing new pluginss easier, and less error-prone.

Machine uses a per-project type of file handling with explorer plugins to interact with the file system inside the project folder boundary (file hierarchy/search/git)

This app is currently Android-only, but every platform-specific code should already have a layer of abstraction.

## Features
- SAF folder project managemdnt
- Plugin architecture for Editors and Explorers
- Session Caching and rehydration
- Flexible command system: that allows for a personal layout
- Mobile-first: It was made on mobile, for mobile.
- Settings, with per-project override
- Asset cache for shared resources
- File-content provider to open custom URI schemes like any other file.

## Editors
### Code Editor
- Based on a personal fork of Re-Editor
- Syntax-Highlighting from Re-Highlight
- Extensive selection and code manipulation tools
- Unified API to communicate with other editors (like the LLM editor)
- Search and replace, with $ notation match group replacement
- Many themes
- Bracket match highlighting
- Color code highlighting and picker
- Navigate to local imports and one-tap add import
### Refactor Editor
- Search and edit file content in the whole project
- When this editor is opened, moving a file in the file explorer will trigger path mode, which search and replaces reference to the moved-file path.
### Glitch Image Editor
- Paint glitches on images
### Tiled Map Editor
- Orthogonal-only tiled .tmx editor
- Dependency gathering and tileset atlas packing and export
### Flow Graph Editor
- Flow graph editor that supports custom node definitions via a .json schema file.
- Export graph to .json to be used anywhere 
### Texture Packer
- Pack spritesheets into an atlas with an associated .json
### LLM Editor
- Speak to an AI with easy context gathering features
- Can replace text with a prompt in any TextEditable editor
### Termux Terminal
- Communicate to a termux instance via the RUN_COMMAND intent
## Explorers
### File Explorer
- A simple hierarchical file explorer
### Search
- A simple search
### Git
- A local git viewer. It only supports viewing the project files at previous git commits. Based on a fork of dartgit
