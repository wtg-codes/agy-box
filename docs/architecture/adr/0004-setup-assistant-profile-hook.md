# ADR-0004: Interactive Setup Assistant Hook in `/etc/profile.d/`

## Status
Accepted

## Context
First-time startup in a developer sandbox requires several setup steps and verification checks (such as loading environment files, seeding browser profiles, configuring Git credentials, setting up API keys, and auditing permissions). If these checks are missed, developers encounter silent failures later.

Automating these checks during container instantiation (e.g., via the container `ENTRYPOINT` or `CMD`) has severe drawbacks:
- It runs as a background command or blocks the startup sequence before a user gets an interactive shell.
- Non-interactive operations (such as running `distrobox-enter` for single-shot commands or automated CI/CD jobs) would trigger the interactive wizard, causing commands to hang waiting for user input.

A solution is required that runs the setup wizard exactly once, automatically, but only when a developer enters a shell session interactively.

## Decision
We implement a login-hook architecture that separates system setup execution from shell initialization:
1. **Interactive Shell Login Hook**:
   - Install a hook script at `/etc/profile.d/agy-setup-check.sh`.
   - The hook loads and exports environment variables from any configuration files inside `~/.config/environment.d/*.conf`.
   - It checks for the existence of the completion flag file `~/.config/agy-box/.setup_done`.
   - If the flag is absent, the hook tests if the session is interactive (`$-` contains `i`) and if both standard input and output are connected to a terminal (`[ -t 0 ] && [ -t 1 ]`).
   - If interactive, it invokes the setup assistant `/usr/local/bin/agy-setup-helper`.
2. **Setup Assistant Wizard**:
   - Checks D-Bus, keyrings, Google Chrome health, Git credentials, and API keys.
   - Provides an interactive "Host Profile Seeding" menu using `gum` to optionally copy host profiles for Chrome, Google Antigravity, and Antigravity IDE (with version-specific path patching in `settings.json`) to the isolated sandbox environment.
   - Runs an optional security audit and permissions hardening check.
   - Writes the `.setup_done` flag file upon completion or explicit skip to prevent subsequent login prompts.

## Consequences
### Trade-offs
- **What becomes easier**:
  - Automated, self-guided onboarding: First-time users are greeted with a visual configuration check without requiring manual documentation search.
  - Zero disruption to non-interactive scripts: TTY and interactive flags prevent the hook from blocking CI pipelines, cron jobs, or single-shot `distrobox-enter` calls.
  - Profile seeding copies the host's authentication and state cleanly to the isolated container environment.
- **What becomes harder**:
  - Login shell performance: Sourcing the profile script adds a slight delay to shell startups (negligible after the setup flag is written).
  - Terminal dependency: If a shell environment has broken standard inputs/outputs, the setup assistant is skipped, which requires manual invocation via `agy-setup-helper`.
