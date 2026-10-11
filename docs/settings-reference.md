# Antigravity Settings & Configuration Reference

This document provides a comprehensive reference for user settings schemas, configuration file locations, and customization mechanisms for the **Google Antigravity IDE**, the **Antigravity CLI (`agy`)**, and the **Gemini Agent Engine** in `agy-box`.

---

## 1. Directory & File Locations Overview

In Linux environments (and inside the `agy-box` container), configurations are divided between editor/IDE GUI settings (`~/.config/`) and agent CLI/engine settings (`~/.gemini/`):

| Scope | Location | Purpose |
| :--- | :--- | :--- |
| **IDE User Settings** | `~/.config/Antigravity/User/settings.json` (or `~/.config/antigravity/`) | Editor preferences, telemetry, Python/Git options, browser paths. |
| **IDE Keybindings** | `~/.config/Antigravity/User/keybindings.json` | Custom keyboard shortcuts for the IDE. |
| **Workspace Settings** | `<project-root>/.vscode/settings.json` | Repository-specific overrides for editor settings. |
| **CLI Settings** | `~/.gemini/antigravity-cli/settings.json` | Global CLI agent settings (model, tool permissions, trusted workspaces). |
| **Global MCP Servers** | `~/.gemini/settings.json` | Model Context Protocol (MCP) server definitions (stdio and SSE/HTTP). |
| **Global Customizations** | `~/.gemini/config/` | Machine-wide skills, rules, plugins, and hooks. |
| **Project Customizations** | `<project-root>/.agents/` (or `.agent/`, `GEMINI.md`, `AGENTS.md`) | Repository-level agent instructions, custom skills, and rules. |
| **Skel Seed Configuration** | `/etc/skel/.gemini/antigravity-cli/settings.json` | Default template seeded to new user home directories inside `agy-box`. |

> [!NOTE]
> When running `agy-box` via `agy-box-manager`, the user's home directory is isolated by default to `~/.config/agy-box/home` on the host. Paths shown as `~/` within this document map directly to that isolated home directory inside the container.

---

## 2. Antigravity CLI Settings (`~/.gemini/antigravity-cli/settings.json`)

The Antigravity CLI (`agy`) reads its primary configuration from `~/.gemini/antigravity-cli/settings.json`.

### Example Configuration

```json
{
  "model": "Gemini 3.8 Flash (High)",
  "toolPermission": "always-proceed",
  "artifactReviewPolicy": "agent-decides",
  "allowNonWorkspaceAccess": true,
  "verbosity": "low",
  "trustedWorkspaces": [
    "/workspace",
    "/home/user/Repos"
  ],
  "permissions": {
    "allow": [
      "command(git status)",
      "command(git diff)",
      "command(./agy-box-manager)",
      "command(just agy-status)",
      "command(npx bats tests/)"
    ],
    "deny": []
  }
}
```

### Schema & Property Reference

| Property | Type | Description |
| :--- | :--- | :--- |
| `model` | `string` | The foundation model to use for agent interactions (e.g., `"Gemini 3.8 Flash (High)"`, `"Gemini 2.5 Pro"`). |
| `toolPermission` | `string` | Permission policy for executing tools. Common options include `"always-proceed"` (auto-run approved tools) and `"ask-first"` (prompt user before running commands). |
| `artifactReviewPolicy` | `string` | Policy for reviewing generated markdown artifacts. Values: `"agent-decides"`, `"always-review"`, `"never"`. |
| `allowNonWorkspaceAccess` | `boolean` | When set to `true`, permits read/write tool calls to paths outside configured workspaces. |
| `trustedWorkspaces` | `string[]` | List of absolute directory paths the agent is permitted to treat as active workspaces. Inside `agy-box`, `/workspace` is trusted by default. |
| `verbosity` | `string` | Output verbosity level for terminal logs (`"low"`, `"medium"`, `"high"`). |
| `permissions` | `object` | Granular allow/deny lists for tool and shell execution. |
| `permissions.allow` | `string[]` | Tool and command invocations pre-approved to run without explicit interactive confirmation (e.g. `"command(git status)"`). |
| `permissions.deny` | `string[]` | Tool and command patterns explicitly blocked from execution. |

---

## 3. Global MCP Configuration (`~/.gemini/settings.json`)

Model Context Protocol (MCP) servers allow the agent to connect to local tools and remote services. Global MCP servers are configured in `~/.gemini/settings.json`.

### Schema & Examples

#### Stdio Transport (Local Processes)

```json
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    },
    "custom-python-mcp": {
      "command": "python3",
      "args": ["-m", "my_mcp_package"],
      "env": {
        "DEBUG": "1"
      }
    }
  }
}
```

#### Remote HTTP / SSE Transport

```json
{
  "mcpServers": {
    "gws-drive": {
      "serverUrl": "https://drivemcp.googleapis.com/mcp/v1",
      "oauth": {
        "clientId": "<CLIENT_ID>",
        "clientSecret": "<CLIENT_SECRET>"
      }
    }
  }
}
```

---

## 4. Antigravity IDE Settings (`~/.config/Antigravity/User/settings.json`)

Antigravity IDE is built on a VS Code base and follows the standard VS Code settings format, extended with Antigravity-specific configuration namespaces.

### Example Configuration

```json
{
  "antigravity.account.enableTelemetry": false,
  "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable",
  "window.titleBarStyle": "native",
  "python.languageServer": "Default",
  "git.autofetch": true,
  "git.confirmSync": false,
  "remote.autoForwardPortsSource": "hybrid",
  "workbench.colorTheme": "Default Dark+"
}
```

### Key Properties

| Property | Type | Description | Default / Recommended in `agy-box` |
| :--- | :--- | :--- | :--- |
| `antigravity.account.enableTelemetry` | `boolean` | Enables or disables telemetry metrics collection. | `false` |
| `antigravity.browser.chromeBinaryPath` | `string` | Path to the Chrome or Chromium binary used for agent browser automation and DevTools auditing. | `"/usr/bin/google-chrome-stable"` (x86_64) or `"/usr/bin/chromium"` (arm64) |
| `window.titleBarStyle` | `string` | Window decoration mode. In containerized VDI desktop environments (IceWM), `"native"` ensures correct window borders and decorations. | `"native"` |
| `python.languageServer` | `string` | Language server engine for Python editing. | `"Default"` |
| `git.autofetch` | `boolean` | Whether git repositories automatically fetch updates from remotes. | `true` |
| `git.confirmSync` | `boolean` | Prompt confirmation before synchronizing git branches. | `false` |
| `remote.autoForwardPortsSource` | `string` | Mechanism for detecting ports forwarded from containers or remote sessions. | `"hybrid"` |

---

## 5. Customizations Discovery & Precedence

Antigravity loads customizations (rules, skills, plugins, hooks) in a tiered hierarchy to balance project specificity with global user preferences.

### Loading Priority (Highest to Lowest)

1. **Workspace Project**: Defined in `<project-root>/.agents/` or `<project-root>/GEMINI.md` / `AGENTS.md`.
2. **Declared Project Configurations**: Customizations explicitly listed in `<project-root>/skills.json` or `plugins.json`.
3. **Global User Discovery**: Files placed under `~/.gemini/config/skills/`, `~/.gemini/config/plugins/`, etc.
4. **Built-in System Customizations**: Bundled platform skills mounted directly by the agent runtime.
5. **Global Declared Configurations**: Explicit entries in global JSON configs.

### Directory Rules (`GEMINI.md` / `AGENTS.md`)
Rules files can be placed at the root of a repository or in subdirectories. As the agent navigates files, it walks up the directory hierarchy to the repository root, injecting all applicable rules into the conversation context with automatic deduplication.
