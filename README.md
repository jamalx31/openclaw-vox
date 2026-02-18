# OpenClaw Vox

A macOS menu-bar voice assistant for [OpenClaw](https://github.com/anthropics/openclaw). Designed to run on a separate Mac from your OpenClaw server, it lets you talk to your AI agent hands-free using push-to-talk.

## Features

- Menu bar app with floating overlay widget
- Push-to-talk hotkey: **⌃⌥ Space** (hold to record, release to send)
- Local speech-to-text (Apple Speech framework)
- Text-to-speech replies with streaming typewriter effect
- Structured AI responses: short spoken summary + full written answer
- Customizable agent name (default: "OpenClaw")
- Persisted settings (URL, token, session, agent name)

## Prerequisites

- macOS 14+
- Swift 5.9+
- An OpenClaw instance running on another machine (or locally)

## Build & Run

```bash
swift build
swift run
```

On first launch, grant the requested permissions:

- **Microphone** — required for voice input
- **Speech Recognition** — required for on-device speech-to-text
- **Input Monitoring** (optional) — enables the eventTap hotkey backend for more reliable push-to-talk; without it, the app falls back to the Carbon hotkey API

## OpenClaw Channel Setup

1. Open the OpenClaw dashboard on your server
2. Create a new channel named **`openclaw-vox`**
3. Copy the **Gateway URL** (e.g. `http://localhost:18789`) and **Gateway Token** from the channel settings

## Secure Connection via SSH Tunnel

If your OpenClaw server is on a remote machine, use an SSH tunnel to securely forward the gateway port:

```bash
ssh -L 18789:localhost:18789 user@openclaw-host
```

This forwards your local port `18789` to the OpenClaw server's gateway port over an encrypted SSH connection. Then set your Gateway URL to `http://localhost:18789` in the app.

## App Configuration

Open the menu bar dropdown to configure:

| Setting | Description |
|---|---|
| **Gateway URL** | Base URL of the OpenClaw gateway. Point to `http://localhost:18789` if using an SSH tunnel, or the LAN address of your OpenClaw server. |
| **Gateway Token** | Bearer token from the `openclaw-vox` channel settings. |
| **Session ID** | Controls conversation history. Obtained from the OpenClaw dashboard. Sessions can be shared across clients — use the same ID to continue a conversation, or a different one for a fresh context. |
| **Agent Name** | Display name shown in the overlay header (default: "OpenClaw"). |

## Security Notes

- Use an SSH tunnel to connect to remote OpenClaw instances — do not expose the gateway port to the public internet.
- Keep your gateway token private.
- For LAN-only setups, ensure the network is trusted (e.g. Tailscale, VPN, or home network).
