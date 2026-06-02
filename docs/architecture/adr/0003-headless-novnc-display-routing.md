# ADR-0003: Virtual Desktop Display Routing via Xvfb, x11vnc, websockify, noVNC

## Status
Accepted

## Context
When developers use `agy-box` in headless environments (such as remote VMs, Google Cloud Shell, or SSH sessions), direct host-integrated display forwarding (X11/Wayland socket sharing) is unavailable. 

To support these workflows, the sandbox environment must provide a way to launch graphical applications (e.g., Google Chrome, Google Antigravity Agent UI, Antigravity IDE) and interact with them visually. Installing a VNC client on the host computer introduces friction, so a clientless (web-browser-accessible) solution is required.

Furthermore, running these graphic tools under container runtimes without physical GPU devices often results in crashes or errors during hardware driver probes.

## Decision
We implement a virtual desktop infrastructure (VDI) subsystem inside the container, orchestrated by the `agy-vdi` wrapper utility (and accessible via the `agy-box-manager desktop` CLI wrapper).

The VDI architecture routes display signals as follows:
1. **Virtual Framebuffer (Xvfb)**:
   - Starts an in-memory virtual X11 server on display `:99` with a configurable resolution (default `1920x1080` with 24-bit color).
2. **IceWM Window Manager**:
   - Manages windows, panels, menus, and wallpapers inside the virtual screen.
3. **VNC Server (x11vnc)**:
   - Attaches to display `:99` and listens on `127.0.0.1:5900` to stream frame buffer changes over the RFB protocol.
4. **WebSocket Bridge (websockify) & HTML5 Client (noVNC)**:
   - Starts a bridge listening on port `6080` that forwards WebSocket connection frames to the local VNC server.
   - Serves the static noVNC HTML5 VNC viewer files from `/usr/share/novnc`.
5. **Software Rasterization**:
   - Forces software-rendering by exporting `LIBGL_ALWAYS_SOFTWARE=1` and `GALLIUM_DRIVER=llvmpipe` to bypass physical GPU checks and prevent crashes.
6. **Chrome Singleton Lock Resolution**:
   - The startup script scans profile folders for stale Chrome/Electron `SingletonLock` files. When containers are recreated, lock files with mismatched hostnames block browser startup. The wrapper automatically purges these stale locks.

## Consequences
### Trade-offs
- **What becomes easier**:
  - Full GUI access in remote, headless, or virtualized environments directly via standard web browsers (no host software required).
  - Robust application launch stability through software rendering and stale lock cleaning.
  - Safe port exposure boundaries by binding the VNC protocol locally and exposing only the WebSocket port.
- **What becomes harder**:
  - **Performance overhead**: Software rasterization is CPU-bound, which increases host CPU usage and degrades responsiveness for high-framerate visuals or complex layouts.
  - **Network exposure**: By default, noVNC listens on all interfaces (`0.0.0.0:6080`) without password authentication. Users must be warned to restrict access via firewall rules or SSH tunnels when operating outside local networks.
