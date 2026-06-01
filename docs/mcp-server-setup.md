# 🔧 Google Workspace MCP Server Setup — Step by Step

> **Goal**: Get Drive, Gmail, Calendar MCP servers working in your `agy` CLI so you can read/create Google Docs, access Shared Drives, search email, etc.

---

## Current State

| Component | Status |
|-----------|--------|
| `agy` CLI v1.0.3 | ✅ Installed, signed in as `wtgranstaff@gmail.com` (AI Ultra) |
| ADC credentials | ✅ `/var/home/wtg/.gcloud_config/application_default_credentials.json` |
| GCP Project | ❌ **None set** — need to create or select one |
| gcloud auth | ❌ **No credentialed accounts** — need `gcloud auth login` |
| OAuth Client ID | ❌ **None created** — need Desktop Application type |
| MCP servers | ❌ **Not configured** |

---

## Step 1: gcloud Auth Login (YOU — Terminal)

```bash
gcloud auth login
```

This opens a browser to sign in. Use your **Gmail account** (wtgranstaff@gmail.com) since that's your AI Ultra account.

---

## Step 2: Create or Select a GCP Project (YOU — Browser)

> [!IMPORTANT]
> This step MUST be done in the browser at [console.cloud.google.com](https://console.cloud.google.com)

**Option A — Create new project:**
1. Go to https://console.cloud.google.com/projectcreate
2. Name it something like `wtg-workspace-mcp`
3. Note the **Project ID** (e.g., `wtg-workspace-mcp`)

**Option B — Use existing project:**
If you already have a GCP project, note its Project ID.

Then set it in gcloud:
```bash
gcloud config set project YOUR_PROJECT_ID
```

---

## Step 3: Enable Required APIs (YOU — Terminal or Browser)

**Via terminal:**
```bash
gcloud services enable drive.googleapis.com
gcloud services enable gmail.googleapis.com
gcloud services enable calendar-json.googleapis.com
gcloud services enable docs.googleapis.com
gcloud services enable sheets.googleapis.com
gcloud services enable slides.googleapis.com
gcloud services enable people.googleapis.com
```

**Or via browser:** https://console.cloud.google.com/apis/library

---

## Step 4: Configure OAuth Consent Screen (YOU — Browser)

1. Go to https://console.cloud.google.com/apis/credentials/consent
2. Choose **External** user type (unless you have a Workspace org, then Internal)
3. Fill in:
   - App name: `WTG Workspace Agent`
   - User support email: your email
   - Developer contact: your email
4. **Scopes**: Skip for now (MCP servers request their own scopes)
5. **Test users**: Add `wtgranstaff@gmail.com`
6. Save

---

## Step 5: Create OAuth 2.0 Client ID (YOU — Browser)

1. Go to https://console.cloud.google.com/apis/credentials
2. Click **+ CREATE CREDENTIALS** → **OAuth client ID**
3. Application type: **Desktop application**
4. Name: `WTG MCP Client`
5. Click **Create**
6. **Copy the Client ID and Client Secret** — you'll need both

---

## Step 6: Set Quota Project for ADC (YOU — Terminal)

```bash
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

This fixes the "quota exceeded" warning you saw.

---

## Step 7: Configure MCP Servers in agy CLI (I CAN HELP)

Once you have the Client ID and Client Secret from Step 5, we need to add the MCP servers to your `agy` config.

The config file is at: `/var/home/wtg/.gemini/antigravity-cli/settings.json`

We'll add an `mcpServers` block like this:

```json
{
  "mcpServers": {
    "google-drive": {
      "url": "https://drivemcp.googleapis.com/mcp/v1",
      "auth": {
        "clientId": "YOUR_CLIENT_ID.apps.googleusercontent.com",
        "clientSecret": "YOUR_CLIENT_SECRET"
      }
    },
    "google-docs": {
      "url": "https://docsmcp.googleapis.com/mcp/v1",
      "auth": {
        "clientId": "YOUR_CLIENT_ID.apps.googleusercontent.com",
        "clientSecret": "YOUR_CLIENT_SECRET"
      }
    },
    "gmail": {
      "url": "https://gmailmcp.googleapis.com/mcp/v1",
      "auth": {
        "clientId": "YOUR_CLIENT_ID.apps.googleusercontent.com",
        "clientSecret": "YOUR_CLIENT_SECRET"
      }
    },
    "google-calendar": {
      "url": "https://calendarmcp.googleapis.com/mcp/v1",
      "auth": {
        "clientId": "YOUR_CLIENT_ID.apps.googleusercontent.com",
        "clientSecret": "YOUR_CLIENT_SECRET"
      }
    }
  }
}
```

> [!NOTE]
> The exact config format may vary depending on whether `agy` uses the same `settings.json` format as Gemini CLI. We'll verify when we get to this step.

---

## Step 8: Authenticate MCP Servers (YOU — Terminal)

After configuring, you'll need to authenticate each MCP server:

```bash
agy mcp auth google-drive
agy mcp auth gmail
agy mcp auth google-calendar
```

Each will open a browser for OAuth consent.

---

## Step 9: Test (I CAN HELP)

Once configured, test each server:
- "List files in my Drive" → tests Drive MCP
- "Search my email for recent messages" → tests Gmail MCP
- "What's on my calendar today?" → tests Calendar MCP

---

## What YOU Need to Do vs What I Can Do

| Step | Who | Why |
|------|-----|-----|
| 1. `gcloud auth login` | **YOU** | Browser auth required |
| 2. Create GCP project | **YOU** | Browser console required |
| 3. Enable APIs | **YOU** (or I can give you the commands) | Needs authenticated gcloud |
| 4. OAuth consent screen | **YOU** | Browser console required |
| 5. Create OAuth Client ID | **YOU** | Browser console required |
| 6. Set quota project | **YOU** | Needs authenticated gcloud |
| 7. Configure MCP in settings.json | **ME** | Just a file edit — give me the Client ID/Secret |
| 8. Auth MCP servers | **YOU** | Browser auth required |
| 9. Test | **TOGETHER** | Verify everything works |

---

## Time Estimate

| Steps 1-6 (Browser/Setup) | ~10 minutes |
|---|---|
| Step 7 (Config) | ~1 minute |
| Steps 8-9 (Auth + Test) | ~5 minutes |
| **Total** | **~15-20 minutes** |
