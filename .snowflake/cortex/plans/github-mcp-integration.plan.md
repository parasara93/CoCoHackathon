# Plan: GitHub MCP Integration for Resilience Orchestrator

## Phase 1 Findings — Account Inspection

### Current Account State (LCICFVE-LC84361)
- **Snowflake-managed MCP servers** (`CREATE MCP SERVER`): Supported, 0 exist
- **External MCP servers** (`CREATE EXTERNAL MCP SERVER`): Supported, 0 exist
- **API integrations**: 0 exist (no `external_mcp` integrations)
- **Security integrations**: Only default `SNOWFLAKE$LOCAL_APPLICATION` (OAuth)
- **Secrets**: 0 exist
- **External access integrations**: 0 exist
- **GitHub-related objects**: None

### Supported Method for GitHub MCP
Based on the docs for this account's Snowflake version, the supported path for **connecting a Cortex Agent to an external MCP server as a client** is:

1. **MCP Connectors** — documented under "MCP Connectors" with explicit GitHub instructions
2. Uses `CREATE API INTEGRATION` with `API_PROVIDER = external_mcp`
3. Uses `CREATE EXTERNAL MCP SERVER` referencing the API integration
4. Attaches to agent via `ALTER AGENT ... ADD MCP_SERVER`

This is distinct from `CREATE MCP SERVER` (which *serves* Snowflake tools to external clients).

### GitHub-Specific Configuration (from docs)
The docs provide an explicit GitHub connector flow:
- **MCP URL**: `https://api.githubcopilot.com/mcp`
- **Token endpoint**: `https://github.com/login/oauth/access_token`
- **Authorization endpoint**: `https://github.com/login/oauth/authorize`
- **Auth type**: OAuth2 with client ID + client secret from a GitHub App
- **Callback URL**: `https://identity.snowflake.com/oauth2/callback`

---

## Step 1: Create GitHub App (Manual — You Must Do This)

You need to create a GitHub App in your GitHub account:

1. Go to **github.com** → top-right avatar → **Settings** → **Developer Settings** → **GitHub Apps**
2. Click **New GitHub App**
3. Fill in:
   - **App name**: `snowflake-supply-chain-mcp` (or any unique name)
   - **Homepage URL**: `https://github.com/parasara93/CoCoHackathon`
   - **Callback URLs**: Add exactly:
     ```
     https://identity.snowflake.com/oauth2/callback
     ```
   - **Disable Webhook** (uncheck "Active")
4. Under **Permissions**:
   - **Repository permissions** → **Issues**: **Read and Write**
   - **Repository permissions** → **Metadata**: **Read-only** (required for repo access)
   - Leave all other permissions at "No access"
5. Under **Where can this GitHub App be installed?**:
   - Select **Only on this account**
6. Click **Create GitHub App**
7. On the app settings page:
   - Note the **Client ID** (displayed on the page)
   - Click **Generate a new client secret** and note the **Client Secret** (shown once)
8. Install the app on your account:
   - On the app page, click **Install App** → Select `parasara93` account
   - Select **Only select repositories** → Choose `CoCoHackathon`
   - Click **Install**

After this step, provide me the **Client ID** and **Client Secret**.

---

## Step 2: Create Snowflake API Integration

```sql
CREATE API INTEGRATION github_mcp_integration
  API_PROVIDER = external_mcp
  API_ALLOWED_PREFIXES = ('https://api.githubcopilot.com')
  API_USER_AUTHENTICATION = (
    TYPE = OAUTH2
    OAUTH_CLIENT_ID = '<your_client_id>'
    OAUTH_CLIENT_SECRET = '<your_client_secret>'
    OAUTH_TOKEN_ENDPOINT = 'https://github.com/login/oauth/access_token'
    OAUTH_AUTHORIZATION_ENDPOINT = 'https://github.com/login/oauth/authorize'
    OAUTH_CLIENT_AUTH_METHOD = CLIENT_SECRET_BASIC
    OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  )
  ENABLED = TRUE;
```

---

## Step 3: Create External MCP Server

```sql
CREATE EXTERNAL MCP SERVER SUPPLY_CHAIN_DW.GOLD.GITHUB_MCP_SERVER
  WITH DISPLAY_NAME = 'GitHub (parasara93/CoCoHackathon)'
  URL = 'https://api.githubcopilot.com/mcp'
  API_INTEGRATION = github_mcp_integration;
```

---

## Step 4: Validate MCP Connection

```sql
DESCRIBE EXTERNAL MCP SERVER SUPPLY_CHAIN_DW.GOLD.GITHUB_MCP_SERVER;
SHOW EXTERNAL MCP SERVERS IN SUPPLY_CHAIN_DW.GOLD;
```

Then initiate OAuth flow (interactive browser step):
```sql
SELECT SYSTEM$START_USER_OAUTH_FLOW('GITHUB_MCP_INTEGRATION');
```
This returns an authorization URL. You open it in a browser, authorize the GitHub App, then complete with:
```sql
SELECT SYSTEM$FINISH_OAUTH_FLOW('<query_string_from_callback>');
```

---

## Step 5: Add GitHub MCP to Orchestrator

```sql
ALTER AGENT SUPPLY_CHAIN_DW.GOLD.RESILIENCE_ORCHESTRATOR
  ADD MCP_SERVER = 'SUPPLY_CHAIN_DW.GOLD.GITHUB_MCP_SERVER';
```

Then update the orchestrator specification to add GitHub Issue governance rules to the instructions. The updated instructions will add:

```yaml
# Added to orchestration instructions:

GitHub Issue Action Rules:
- The orchestrator can create GitHub Issues in parasara93/CoCoHackathon ONLY when the user explicitly asks.
- Trigger phrases: "create a GitHub issue", "raise an issue on GitHub", "open a GitHub issue", etc.
- Never create a GitHub Issue automatically because a risk was detected.
- Prefer creating the internal RISK_CASE first via create_risk_case.
- Include the CASE_ID in the GitHub Issue body when available.
- Target repository: parasara93/CoCoHackathon only.
- Never modify source code, merge PRs, close issues, or perform unrelated GitHub actions.
- Issue title format: [Supply Chain Risk] <entity> — <risk summary>
- Issue body: structured with Risk Case ID, Entity, Risk Type, Severity, Evidence, Impact, Recommended Action, Source.
```

The `mcp_servers` section is added alongside the existing `tools` and `tool_resources` (which remain unchanged):

```yaml
mcp_servers:
  - server_spec:
      name: "SUPPLY_CHAIN_DW.GOLD.GITHUB_MCP_SERVER"
```

---

## Step 6: Validate Updated Orchestrator

- `DESCRIBE AGENT SUPPLY_CHAIN_DW.GOLD.RESILIENCE_ORCHESTRATOR`
- Confirm all 6 existing tools still present (5 agent_toolset + 1 generic)
- Confirm `mcp_servers` section references `GITHUB_MCP_SERVER`
- Confirm instructions include GitHub governance rules
- Confirm repository restriction to `parasara93/CoCoHackathon` in instructions
- Confirm explicit user approval required by instructions

---

## What Requires Your Manual Action

| Step | Action | Why |
|---|---|---|
| Step 1 | Create GitHub App on github.com | OAuth credentials cannot be generated programmatically from Snowflake |
| Step 1 | Install app on `parasara93` account with repo `CoCoHackathon` | GitHub App installation requires account owner consent |
| Step 1 | Provide Client ID and Client Secret to me | Needed for API Integration creation |
| Step 4 | Open OAuth authorization URL in browser | Interactive GitHub consent flow cannot be automated |
| Step 4 | Run SYSTEM$FINISH_OAUTH_FLOW with callback query string | Completes the OAuth handshake |

Everything else (API Integration, External MCP Server, Agent modification, validation) I execute after you provide the credentials.
