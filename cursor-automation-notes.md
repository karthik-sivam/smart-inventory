# Cursor Cloud Agents API — Automation Setup Notes

> Status: **Research complete, setup deferred.**
> Revisit when ready to wire up the full automated pipeline.

---

## API Key

Stored separately. Format: `crsr_xxxx...`

**Important:** The agent-specific key is generated at:
`cursor.com/dashboard?tab=cloud-agents` → My Settings → API Keys

This is **NOT** the same as a general Cursor dashboard API key. Regular keys work for GET endpoints (`/v0/models`, `/v0/repositories`) but `POST /v0/agents` requires an agent-specific key.

---

## Endpoint

```
POST https://api.cursor.com/v0/agents
```

**Authentication:** HTTP Basic Auth with API key + trailing colon:
```bash
-u "crsr_your_key_here:"
```
(Cursor encodes it as `base64(api_key + ":")`  under the hood)

---

## Payload Format

```json
{
  "prompt": {
    "text": "Your task description here"
  },
  "source": {
    "ref": "main",
    "repository": "https://github.com/your-org/your-repo"
  },
  "target": {
    "autoCreatePr": false
  },
  "model": "default"
}
```

**Available models** (from GET /v0/models):
- `composer-1.5`
- `default` (recommended for automation)
- `claude-4.6-opus-high-thinking`
- etc.

---

## Full curl Example

```bash
curl --request POST \
  --url https://api.cursor.com/v0/agents \
  -u "crsr_your_key_here:" \
  --header "Content-Type: application/json" \
  --data '{
    "prompt": {
      "text": "Read CURSOR_QUEUE.md in this repo. Process all items marked [PENDING]. When done, append results to automation_results.rtf and mark each item [DONE]."
    },
    "source": {
      "ref": "main",
      "repository": "https://github.com/your-org/stoqly"
    },
    "target": {
      "autoCreatePr": false
    },
    "model": "default"
  }'
```

---

## Agent Status Values

Poll the returned `id` to check progress:

| Status | Meaning |
|--------|---------|
| `CREATING` | Spinning up |
| `RUNNING` | Actively working |
| `FINISHED` | Done — check the output |
| `FAILED` | Something went wrong |
| `CANCELLED` | Manually stopped |

---

## Planned Automation Pipeline

When we wire this up, the full flow will be:

```
1. You freeze requirement (message in Cowork)
        ↓
2. PM + Designer agents spawn in parallel (automated)
        ↓
3. You review & approve (human gate)
        ↓
4. Scrum Master + iOS Engineer spawn in parallel (automated)
   iOS Engineer writes spec to CURSOR_QUEUE.md
        ↓
5. Nightly scheduled task (2am) → POST /v0/agents with CURSOR_QUEUE.md contents
        ↓
6. Morning standup reads automation_results.rtf → reports pass/fail
        ↓
7. You test on device (human gate — unavoidable)
```

---

## What Still Needs to Be Done

- [ ] Confirm GitHub repo URL for Stoqly (needed in the `source.repository` field)
- [ ] Store API key securely (environment variable or `.env` file, gitignored)
- [ ] Create `CURSOR_QUEUE.md` with standard format for pending specs
- [ ] Set up nightly scheduled task that reads queue and calls the API
- [ ] Set up morning standup scheduled task that reads `automation_results.rtf`
- [ ] Set up "freeze:" trigger that spawns PM + Designer agents

---

## Sources

- [Cursor Cloud Agents API Docs](https://cursor.com/docs/cloud-agent/api/endpoints)
- [Forum: POST /v0/agents endpoint details](https://forum.cursor.com/t/cloud-agents-api-post-v0-agents/154512)
- [MCPBundles: Cursor Cloud Agents integration](https://www.mcpbundles.com/blog/cursor-cloud-agents-api)
- [Cursor SDK (TypeScript, public beta Apr 2026)](https://forum.cursor.com/t/cursor-sdk-cloud-agents-api-updates/159284)
