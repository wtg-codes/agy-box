# ADR-0002: Credentials Decryption via D-Bus Session Keyring Forwarding and `libsecret`

## Status
Accepted

## Context
Google Chrome and Google Antigravity (Agent UI) store encrypted sensitive credentials, such as Google sign-in tokens, API keys, and saved passwords, in the host system's keyring manager (GNOME Keyring or KWallet).

When running inside the `agy-box` container:
- The applications need access to the D-Bus secret service to retrieve and decrypt these credentials.
- Distrobox forwards the host's D-Bus session socket (`$DBUS_SESSION_BUS_ADDRESS`) into the container.
- However, for applications inside the container to successfully query the D-Bus secret service, they require the proper client library interfaces (`libsecret-1-0`) and Python keyring modules. Without these, authentication silently fails or causes cryptic error messages, and credentials cannot be persisted.

Additionally, in headless or custom systems where D-Bus is completely absent or broken, a standard D-Bus session keyring request fails, blockading the environment setup.

## Decision
We implement a two-tiered decryption and credentials persistence strategy:
1. **Host-Integrated Keyring Access**:
   - Install `libsecret-1-0`, `python3-keyring`, and `python3-keyrings.alt` inside the container base image using `scripts/install-agent-deps.sh`.
   - Forward and bridge the D-Bus session bus address into the sandbox (handled by Distrobox).
2. **Early Keyring & D-Bus Integrity Validation**:
   - The first-time setup assistant (`agy-setup-helper`) queries the D-Bus connection status using `dbus-send` and runs a Python script to verify that credentials can be successfully set, read, and deleted via the `keyring` library.
3. **Encrypted File-Based Keyring Fallback**:
   - If the D-Bus socket or host keyring is unreachable (e.g., in remote headless sessions), the setup assistant guides the user to configure a fallback, file-based encrypted keyring using the alternative backend `keyrings.alt.file.EncryptedKeyring`.
   - The helper prompts the user for a master password, exports this to `$KEYRING_CRYPT_PASSWORD`, and writes it to `~/.config/environment.d/agy-box.conf` to automatically configure subsequent sessions.

## Consequences
### Trade-offs
- **What becomes easier**:
  - Secure credential storage sharing: Chrome and Google Antigravity share authentication sessions seamlessly between host and container.
  - Fail-safe operations: Headless environments without a host D-Bus session can use the container-internal encrypted file keyring fallback.
  - Proactive validation prevents silent sign-in failures and makes debugging authentication issues straightforward.
- **What becomes harder**:
  - The fallback mechanism writes the master password in plaintext inside `~/.config/environment.d/agy-box.conf`, which requires tight file permissions (`600`).
  - Requires maintaining `libsecret` and Python keyring library dependencies inside the container image.
