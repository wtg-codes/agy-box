# agy-box System Architecture & Design Guide

This document provides a deep dive into the inner workings of the `agy-box` developer sandbox, detailing how it achieves seamless host integration, manages graphical rendering, secures credentials, and facilitates first-time configuration.

---

## 1. System Topology & Bridging

Unlike typical sandbox runtimes that completely isolate applications, `agy-box` uses **Distrobox** (on top of Podman or Docker) to act as a **host-integrated developer environment**.

```mermaid
graph TD
    subgraph Host ["Host OS (Immutable/Atomic e.g., Bluefin, Silverblue)"]
        UserHome["User Home (~/) <br> stores .config/environment.d/agy-box.conf"]
        Display["Display Server (Wayland / X11)"]
        DBus["D-Bus Session Bus <br> (Secret Service / GNOME Keyring)"]
        FlatpakChrome["Un-sandboxed Chrome Binary <br> (/var/lib/flatpak/.../chrome)"]
    end

    subgraph Bridge ["Distrobox Bridge"]
        MountHome["Home Volume Mount"]
        ForwardSockets["Socket Forwarding (X11/Wayland/DBUS)"]
    end

    subgraph Sandbox ["agy-box Sandbox Container (Ubuntu Toolbox Base)"]
        BaseOS["Base OS Layer (Ubuntu)"]
        KeyringClient["Keyring integration (libsecret-1-0)"]
        
        subgraph Setup ["First-Time Setup Assistant"]
            SetupHelper["agy-setup-helper <br> (checks API Keys, Keyring, Git, Chrome)"]
            ProfileHook["/etc/profile.d/agy-setup-check.sh"]
        end

        subgraph Suite ["Antigravity Developer Suite"]
            IDE["Google Antigravity (Agent UI) <br> (canvas workspace, terminal, course labs)"]
            CLI["Antigravity CLI (agy) <br> (WebSocket loops, lab submission)"]
            SDK["Antigravity Python SDK (google-antigravity) <br> (GCS auth, local Port 8080 API)"]
            ChromeWrapper["Google Chrome <br> (google-chrome-stable wrapper)"]
        end
    end

    UserHome <-->|"Mounts to /var/home/wtg"| MountHome
    MountHome <--> BaseOS
    
    DBus -->|"Forward D-Bus Socket"| ForwardSockets
    ForwardSockets --> KeyringClient
    KeyringClient -->|"Decrypt tokens"| ChromeWrapper
    KeyringClient -->|"Decrypt tokens"| IDE
    
    Display -->|"X11 / Wayland Socket Forwarding"| ForwardSockets
    ForwardSockets --> IDE
    ForwardSockets --> ChromeWrapper
    
    IDE <-->|"WebSocket Loop"| CLI
    SDK -->|"Local API calls (Port 8080)"| IDE
    IDE -->|"Chrome DevTools Protocol (CDP)"| ChromeWrapper
    ChromeWrapper -->|"Launch un-sandboxed"| FlatpakChrome
    
    ProfileHook -->|"Trigger on first bash login"| SetupHelper
    SetupHelper -->|"Verify & write keys"| UserHome

    %% Modern Theme Styling
    classDef host fill:#e0f2fe,stroke:#0284c7,stroke-width:2px,color:#0369a1;
    classDef bridge fill:#fffbeb,stroke:#d97706,stroke-width:2px,color:#b45309;
    classDef sandbox fill:#f0fdf4,stroke:#16a34a,stroke-width:2px,color:#15803d;
    classDef setup fill:#faf5ff,stroke:#9333ea,stroke-width:2px,color:#7e22ce;

    class UserHome,Display,DBus,FlatpakChrome host;
    class MountHome,ForwardSockets bridge;
    class BaseOS,KeyringClient,IDE,CLI,SDK,ChromeWrapper sandbox;
    class SetupHelper,ProfileHook setup;
```

---

## 2. Interactive Setup Assistant Sequence Flow

When a user opens an interactive shell session in the `agy-box` container for the first time, a hook in `/etc/profile.d/agy-setup-check.sh` is triggered. The helper handles verifying the environment and setting up credentials.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Hook as profile.d/agy-setup-check.sh
    participant Helper as usr/local/bin/agy-setup-helper
    participant HostFS as Host Filesystem (~/.config/agy-box)
    participant DBus as Host D-Bus Session
    participant Config as environment.d/agy-box.conf

    User->>Hook: Launch interactive shell (tty)
    Hook->>HostFS: Check if .setup_done exists
    alt Flag exists
        HostFS-->>Hook: Yes, skip setup
    else Flag does not exist
        HostFS-->>Hook: No, trigger setup assistant
        Hook->>Helper: Execute
        Helper->>User: Display greeting banner & prompt to run setup [Y/n]
        alt User declines
            User-->>Helper: 'n'
            Helper->>HostFS: Create .setup_done
            Helper-->>User: Exit immediately
        else User accepts
            User-->>Helper: 'Y' (or default)
            
            Note over Helper,DBus: Stage 1: Keyring & D-Bus Validation
            Helper->>DBus: Test ListNames reply via dbus-send
            DBus-->>Helper: Reply received (healthy)
            Helper->>Helper: Check if secret-tool is installed
            
            Note over Helper,Config: Stage 2: API Keys Configuration
            Helper->>Config: Search for GEMINI_API_KEY / ANTIGRAVITY_API_KEY
            alt Keys not found
                Helper->>User: Prompt to configure API keys now? [Y/n]
                User-->>Helper: 'Y'
                Helper->>User: Request GEMINI_API_KEY
                User-->>Helper: Enter API key (or skip)
                Helper->>User: Request ANTIGRAVITY_API_KEY
                User-->>Helper: Enter API key (or skip)
                Helper->>Config: Write keys to environment.d config
            end
            
            Note over Helper: Stage 3: Google Chrome Health
            Helper->>Helper: Execute google-chrome-stable --version
            
            Note over Helper: Stage 4: Git Identity Configuration
            Helper->>Helper: Read global user.name & user.email
            alt Git configs missing
                Helper->>User: Prompt and read Git user.name / user.email
                Helper->>Helper: Write global git configs
            end

            Note over Helper: Stage 4.5: Optional Skills Pack & Security Auditing
            alt User opts-in to Audit
                Helper->>Helper: Audit root boundary, DBus owner, and scan wildcard ports
                Helper->>Helper: Verify Android USB, gcloud, VDI toolchains
                Helper->>HostFS: Offer to harden key file permissions (chmod 600)
            end

            Note over Helper,HostFS: Stage 5: Flag Completion
            Helper->>HostFS: Create ~/.config/agy-box/.setup_done
            Helper-->>User: Success message & exit
        end
    end

    %% Diagram Styling
    style Hook fill:#faf5ff,stroke:#9333ea,stroke-width:1px
    style Helper fill:#faf5ff,stroke:#9333ea,stroke-width:1px
    style HostFS fill:#fffbeb,stroke:#d97706,stroke-width:1px
    style DBus fill:#e0f2fe,stroke:#0284c7,stroke-width:1px
    style Config fill:#fffbeb,stroke:#d97706,stroke-width:1px
```

---

## 3. D-Bus session keyring pipelines

Google Chrome and Google Antigravity (Agent UI) encrypt credentials (e.g. Google sign-in tokens, saved passwords) using the host OS keyring manager (GNOME Keyring or KWallet). 

Even though the D-Bus socket is forwarded into the sandbox container by Distrobox, client applications must have the `libsecret` library installed inside the container to make method calls over D-Bus to request credentials decryption. Without `libsecret-1-0`, these apps fail to authenticate silently.

```mermaid
graph LR
    subgraph Sandbox ["agy-box Container"]
        IDE["Google Antigravity (Agent UI)"]
        Chrome["Google Chrome"]
        LibSecret["libsecret-1.0 Client"]
    end

    subgraph Bridge ["Socket Bind Forwarding"]
        DBusSocket["/run/user/1000/bus"]
    end

    subgraph Host ["Host Session"]
        HostDBus["D-Bus Session Daemon"]
        Keyring["GNOME Keyring Daemon <br> (Secret Service API)"]
    end

    IDE -->|Request stored secret| LibSecret
    Chrome -->|Request stored secret| LibSecret
    LibSecret -->|D-Bus Messages| DBusSocket
    DBusSocket -->|Forward| HostDBus
    HostDBus -->|Method Call| Keyring
    Keyring -->|Return Credentials| HostDBus
    HostDBus -->|Forward| DBusSocket
    DBusSocket -->|D-Bus Reply| LibSecret
    LibSecret -->|Decrypted Token| IDE
    LibSecret -->|Decrypted Token| Chrome

    %% Modern Theme Styling
    classDef host fill:#e0f2fe,stroke:#0284c7,stroke-width:2px,color:#0369a1;
    classDef bridge fill:#fffbeb,stroke:#d97706,stroke-width:2px,color:#b45309;
    classDef sandbox fill:#f0fdf4,stroke:#16a34a,stroke-width:2px,color:#15803d;

    class HostDBus,Keyring host;
    class DBusSocket bridge;
    class IDE,Chrome,LibSecret sandbox;
```

---

## 4. Port Mappings & IPC Loops

The components of the Antigravity developer suite communicate over a series of ports and sockets inside the container loop:

| Port | Protocol | Source | Target | Description |
| :--- | :--- | :--- | :--- | :--- |
| **8080** | HTTP | Python SDK (`google-antigravity`) | Google Antigravity (Agent UI) | Localhost developer API server mapping workspace canvases. |
| **9222** | WebSocket / CDP | Google Antigravity (Agent UI) | `google-chrome-stable` | Chrome DevTools Protocol port to dynamically execute web commands. |
| **5900** | RFB | VNC Clients | `x11vnc` | Internal virtual display VNC server stream (bound securely to `127.0.0.1`). |
| **6080** | HTTP / WS | Web Browsers | `websockify` / noVNC | noVNC HTML5 client portal enabling remote/VDI browser desktop access. |
| **dynamic** | WebSocket | Antigravity CLI (`agy`) | Google Antigravity (Agent UI) | Active loop coordinating lab course task completion updates. |

---

## 5. VDI Web Desktop (Headless Display Routing)

To support remote development, headless environments (e.g. Google Cloud Shell, VMs), and easy environment debugging, the workspace provides a built-in virtual desktop environment utilizing **noVNC** and **Xvfb**.

```mermaid
graph TD
    subgraph Browser ["Host Web Browser"]
        noVNC["noVNC HTML5 Client <br> (http://localhost:6080/vnc.html)"]
    end

    subgraph Sandbox ["agy-box Container (Headless)"]
        Websockify["websockify <br> (Port 6080)"]
        X11VNC["x11vnc <br> (Port 5900, 127.0.0.1)"]
        Openbox["Openbox Window Manager <br> (DISPLAY=:99)"]
        Xvfb["Xvfb virtual display <br> (DISPLAY=:99)"]
        IDE["Google Antigravity (Agent UI) <br> (renders inside Xvfb)"]
        Chrome["Google Chrome <br> (renders inside Xvfb)"]
    end

    noVNC <-->|"WebSocket Stream"| Websockify
    Websockify <-->|"RFB Loop"| X11VNC
    X11VNC -->|"Inspect frame buffer"| Xvfb
    Openbox -->|"Manage Windows"| Xvfb
    IDE -->|"Draw GUI"| Xvfb
    Chrome -->|"Draw GUI"| Xvfb

    %% Styling
    classDef client fill:#e0f2fe,stroke:#0284c7,stroke-width:2px,color:#0369a1;
    classDef server fill:#f0fdf4,stroke:#16a34a,stroke-width:2px,color:#15803d;

    class noVNC client;
    class Websockify,X11VNC,Openbox,Xvfb,IDE,Chrome server;
```

