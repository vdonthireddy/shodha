# Shodha (శోధ / शोध) 🌟

[![macOS](https://img.shields.io/badge/Platform-macOS%2013%2B-blue.svg?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg?logo=swift)](https://swift.org/)
[![Model-Context-Protocol](https://img.shields.io/badge/MCP-Protocol-purple.svg)](https://modelcontextprotocol.io/)
[![Ollama](https://img.shields.io/badge/LLM-Local%20Ollama-green.svg)](https://ollama.ai/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

> **Shodha** (*Sanskrit & Telugu: శోధ / शोध* — meaning *Search, Quest, Inquiry & Discovery*) is an intelligent, floating desktop companion for macOS. It pairs an always-on-screen animated avatar with local LLM intelligence (via Ollama or OpenAI-compatible backends) and tool orchestration using the Model Context Protocol (MCP) for autonomous actions like persistent reminders and notifications.

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [System Architecture](#-system-architecture)
- [How It Works (Layman's Guide)](#-how-it-works-laymans-guide)
- [Installation & Setup](#-installation--setup)
- [Usage Guide](#-usage-guide)
- [Configuration & Storage](#-configuration--storage)
- [Documentation Links](#-documentation-links)
- [Contributing & License](#-contributing--license)

---

## 🌟 Overview

Traditional AI assistants are buried in browser tabs or full-screen windows. **Shodha** is designed to feel like an ambient, omnipresent companion right on your Mac desktop:

- **Always Present, Never in the Way:** A floating, draggable avatar that floats above all applications and virtual spaces without stealing focus.
- **Privacy-First & Local:** Powered by your local Ollama models (such as LLaMA 3, Mistral, Qwen, DeepSeek). No data leaves your machine unless you configure an external endpoint.
- **Autonomous Tool Execution (MCP):** Connects to specialized tool servers via JSON-RPC over Model Context Protocol, enabling the assistant to schedule reminders and interact with system tools seamlessly.
- **Rich Notifications:** Native macOS user notifications with persistent alerts, custom sound, and your chosen avatar displayed right in the notification header.

---

## ✨ Key Features

### 1. 🪟 Ambient Floating Avatar & Window Management
- **Floating Panel:** Stays floating above full-screen windows and macOS virtual spaces (`NSWindow.Level.floating`, `.canJoinAllSpaces`).
- **Smooth Drag-and-Drop:** Drag anywhere on the avatar to reposition it on any display. Remembers screen coordinates across reboots.
- **Living Mascot Animation:** Custom procedural avatar with blinking eyes, glowing particle aura, and real-time mouth movement synchronized to speech.
- **Custom Avatars & Photo Library:** Easily switch between the default mascot or upload your own PNG/JPEG avatars. Shodha automatically packages your active avatar into the application bundle icon so notifications mirror your chosen avatar.

### 2. 🧠 Local LLM Integration & Smart Tool Calling
- **Local Ollama Auto-Discovery:** Automatically connects to `http://localhost:11434/v1` and queries `/v1/models` to populate available models.
- **Universal OpenAI Compatibility:** Can be pointed to LM Studio, vLLM, LocalAI, or cloud endpoints.
- **Model Context Protocol (MCP) Scheduler:** Ships with a background Python-based MCP server (`mcp_scheduler_server.py`) that handles dynamic tool discovery, structured argument validation, and natural language reminder creation.
- **Autonomous Function Dispatch:** When you say *"Remind me to drink water in 10 minutes"*, the LLM invokes the `schedule_reminder` tool, schedules the timer, and responds with a confirmation.

### 3. ⏰ Native macOS Reminders & Notifications
- **Precision Timer Engine:** Evaluates active reminders every second with sub-second accuracy.
- **Native UserNotification Center:** Posts alerts with `UNNotificationCategory` ensuring reminder text is immediately readable in banner headers.
- **Speech Audio Synchronization:** Features text-to-speech voice modulation (pitch and rate controls: Cute, Normal, Deep, Chipmunk, Fast, Relaxed) with one-click **"Say It"** and speech interruption.

---

## 🏗️ System Architecture

For an in-depth breakdown, see the dedicated [ARCHITECTURE.md](ARCHITECTURE.md).

```
                      +---------------------------------------+
                      |             User Screen               |
                      |  [ Floating Avatar ]   [ Chat Box ]   |
                      +-------------------+-------------------+
                                          |
                                Swift / SwiftUI
                                          |
                      +-------------------v-------------------+
                      |               AppState                |
                      +---------+-------------------+---------+
                                |                   |
                 +--------------+                   +---------------+
                 |                                                  |
      +----------v----------+                            +----------v----------+
      |     OllamaAgent     |                            |   ReminderManager   |
      +----------+----------+                            +----------+----------+
                 | (OpenAI API / Tools)                             | (1s Poll)
      +----------v----------+                            +----------v----------+
      |  Ollama / Local LLM |                            |    reminders.json   |
      +----------+----------+                            +----------+----------+
                 | (Tool Calls)                                     ^
      +----------v----------+                                       |
      |      MCPClient      |                                       |
      +----------+----------+                                       |
                 | (JSON-RPC stdio)                                 |
      +----------v----------+                                       |
      | mcp_scheduler_server+---------------------------------------+
      +---------------------+
```

---

## 📖 How It Works (Layman's Guide)

For a friendly, non-technical explanation of how Shodha functions, check out our [LAYMAN_GUIDE.md](LAYMAN_GUIDE.md).

In short:
1. **The Avatar is your desk buddy:** It sits quietly on the edge of your screen. Click it whenever you want to talk or ask something.
2. **The Brain is inside your computer:** When you ask a question or give a command, Shodha asks your local AI model (Ollama). Your prompts and files never leave your computer.
3. **The Hands are MCP tools:** When you ask Shodha to schedule an alert, the AI uses specialized "hands" (an MCP tool) to note down the reminder and ring a bell on macOS when the time comes!

---

## 🚀 Installation & Setup

### Prerequisites
- macOS 13.0 (Ventura) or newer
- [Swift 5.9+](https://www.swift.org/download/) (included with Xcode Command Line Tools: `xcode-select --install`)
- Python 3.9+ (pre-installed on macOS)
- [Ollama](https://ollama.ai/) installed and running (`ollama serve` and `ollama pull qwen2.5` or `llama3`)

### Quick Install (One Command)
Clone the repository and run the automated installer:

```bash
git clone https://github.com/vdonthireddy/shodha.git
cd shodha
./install.sh
```

The script will:
1. Compile all Swift sources with native optimizations.
2. Package the app bundle with assets and the MCP server.
3. Apply ad-hoc code signatures.
4. Install to `/Applications/Shodha.app`.
5. Register with macOS LaunchServices and launch Shodha.

---

## 💡 Usage Guide

### Opening & Chatting
- **Click the Avatar:** Toggles the chat dialog open or closed.
- **Outside Dismissal:** Clicking outside the dialog or switching windows automatically hides the dialog while keeping your avatar on screen.
- **Menu Bar Icon:** Click the menu bar icon at the top of your screen to toggle Shodha or access settings.

### Asking Questions & Giving Commands
- Ask general knowledge, coding, or writing questions:
  > *"How do I format an ISO date in Python?"*
- Schedule reminders:
  > *"Remind me to submit my report in 15 minutes"*  
  > *"Remind me to stretch at 4:30 PM"*
- Switch active models on the fly using the header picker.
- Click **"🔊 Say It"** if you want Shodha to speak the answer out loud.

---

## 📂 Configuration & Storage

All persistent settings, reminders, and custom avatars are stored locally:

| File / Path | Purpose |
| :--- | :--- |
| `~/Library/Application Support/Shodha/reminders.json` | Active and past scheduled reminders |
| `~/Library/Application Support/Shodha/avatars/` | Uploaded custom avatar images |
| `~/Library/Application Support/Shodha/current_avatar.png` | Currently active screen avatar |
| `~/Library/Application Support/Shodha/notify.log` | macOS notification authorization diagnostics |
| `UserDefaults` (`com.shodha.mac`) | Endpoint URLs, selected voice pitch, speed, and window coordinates |

---

## 📚 Documentation Links

- 🏛️ [**Architecture Deep Dive**](ARCHITECTURE.md) — Technical internals, state machine, threading model, and MCP communication.
- 🐣 [**Layman's Guide to Shodha**](LAYMAN_GUIDE.md) — Simple, easy-to-understand explanation for non-developers.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.
