# Final Engineering Review
## CardPilot — Pre-submission Checklist & Improvements

---

## 1. Missing items to add before submission

### 1a. `FakeLLM` in fakes.py — add this to the existing file

The test fakes reference `FakeLLM` but the original `fakes.py` only has `FakeVision`, `FakeSheets`, `FakeWhatsApp`, `FakeTranscription`. **Append this to `backend/tests/agent/fakes.py`:**

```python
class FakeLLM:
    def __init__(self, summary: str = "Met at SaaS conference. Interested in enterprise tier."):
        self.summary = summary
        self.called = False

    async def summarize(self, transcript: str) -> str:
        self.called = True
        return self.summary
```

### 1b. Add `__init__.py` for the new test packages

```bash
touch backend/tests/api/__init__.py
touch backend/tests/tools/__init__.py
```

### 1c. Google Sheets column header row

Your `sheets.py` tool should ensure the Sheet has a header row on first use. Add a `_ensure_headers()` call in `GoogleSheets.__init__` or as a one-time migration step. Without headers, column lookups by name will fail.

Expected headers (match these exactly):
```
row_id | name | phone | email | company | audio_url | voice_summary | logged_at
```

### 1d. Frontend `.env.example`

Create `frontend/.env.example`:
```
# Set this to your deployed backend URL for production builds.
# Leave empty for local dev (Vite proxy handles /api routing).
VITE_API_URL=
```

---

## 2. Security improvements

| Issue | Risk | Fix |
|---|---|---|
| `GOOGLE_SERVICE_ACCOUNT_JSON` as file path | Path leaks in error logs | Accept as inline JSON string; parse with `json.loads()` — already handled in `config.py` ideally |
| CORS `allow_origins=["*"]` in production | Any site can call your API | Set `CORS_ORIGINS` to your specific frontend domain in production `.env` |
| No upload file size limit | DoS via huge file | Add `MAX_UPLOAD_MB` setting; validate in upload routes before reading bytes |
| MongoDB URI in logs | Credential exposure | Ensure logging.py redacts connection strings |
| Cloudinary API secret in env | If env leaks, attacker can delete assets | Scope Cloudinary API key to "upload only" in Cloudinary dashboard |

---

## 3. Possible bugs to verify

**Bug 1: `default_state` called on every card upload (resets existing session)**

In `uploads.py`, `upload_card` does:
```python
init_state = { **default_state(session_id), "stage": "extracting", "raw_image_url": image_url }
result = await graph.ainvoke(init_state, cfg)
```
This replaces the checkpoint on every card upload, which is correct for a fresh card but would lose state if a user uploads a second card in the same session. **Verify** that LangGraph merges state correctly (it should, due to `add_messages` reducer) rather than replacing it wholesale.

**Bug 2: SSE stream opens before `graph.ainvoke()` returns in `upload_card`**

The upload endpoint calls `graph.ainvoke()` synchronously, which runs the graph to completion or interrupt. The SSE stream is a *separate* connection that calls `graph.astream(None, cfg)`. If the graph already ran to an interrupt state, `astream(None, cfg)` may re-run from the interrupt rather than just streaming progress. **Verify** this flow works correctly with a real MongoDB checkpointer — with `MemorySaver` in tests it may behave differently.

**Mitigation:** Consider calling `graph.ainvoke()` in the upload route only to inject state (`aupdate_state`), then let the SSE stream do the actual graph execution. This is architecturally cleaner.

**Bug 3: Audio local URL in confirmation dialog**

`URL.createObjectURL(file)` in `useChat.js` creates a blob URL that only lives while the page is open. If the user refreshes, the audio player breaks. This is acceptable for a prototype but worth noting in the README.

---

## 4. Performance improvements

| Improvement | Impact |
|---|---|
| Cache Google Sheets rows in memory for the duration of one dedup check (currently may fetch all rows on every call) | Reduces Sheets API calls |
| Stream Gemini response tokens to the UI for the extraction step | Reduces perceived latency |
| Use `asyncio.gather()` for Cloudinary upload + graph state update in parallel | Marginal speed improvement |
| Pre-warm the Render backend with a cron job hitting `/api/health` | Eliminates cold-start UX issue |

---

## 5. UI improvements

| Improvement | Where |
|---|---|
| Show uploaded card image thumbnail in the ConfirmationDialog alongside the editable fields | `ConfirmationDialog.jsx` |
| Add a "Copy to clipboard" button on extracted contact fields | `ConfirmationDialog.jsx` |
| Show a "Duplicate found — existing contact" card in the chat with the matched data | `MessageBubble.jsx` (add `type: 'duplicate'`) |
| Mobile responsiveness — hide sidebar behind a hamburger menu on narrow screens | `App.jsx` + `Sidebar.jsx` |
| Keyboard shortcut: Enter to confirm, Escape to reject | `ConfirmationDialog.jsx` |

---

## 6. Submission strength checklist

Before submitting, verify each item end-to-end:

- [ ] Card upload → extraction → confidence scores visible → confirmation dialog appears
- [ ] Confirm with edits → dedup check passes → row appears in Google Sheet
- [ ] WhatsApp notification arrives on the manager's phone
- [ ] Re-upload same card → duplicate detected → no new row in Sheet
- [ ] Voice note upload → transcription → summary → Sheet row updated with audio URL
- [ ] Voice note is correctly linked to the contact from the **same session** (state persistence check)
- [ ] New session → confirm nothing from session 1 leaks into session 2
- [ ] Server restart → existing session can still receive a voice note (MongoDB checkpointer persistence)
- [ ] `/api/health` returns 200 from the deployed Render URL
- [ ] Frontend deployed URL loads within 3 seconds (after warm-up)
- [ ] README has accurate env var names that match `config.py`
- [ ] Demo video is 3–5 minutes, shows all required flows, audio is clear

---

## 7. What makes this submission stand out

1. **Single-agent discipline is provable** — there are no business-logic if-statements in FastAPI routes. Reviewers can read `uploads.py` and see it's purely state injection + `graph.ainvoke()`.

2. **State persistence is real** — the MongoDB checkpointer means voice note linking survives HTTP request boundaries, session restarts, and (if self-hosted) server restarts.

3. **Human-in-the-loop is interactive** — not just a prompt confirmation, but an editable form with per-field confidence scores.

4. **Deduplication is robust** — fuzzy matching with normalization, not just `phone == phone`.

5. **Ports/adapters pattern** — every external service has an abstract interface and a fake implementation, making the graph 100% testable without real credentials.

6. **SSE for real-time progress** — users see exactly which node is executing, in real time, without polling.

7. **Full containerization** — `docker compose up --build` starts the complete stack from scratch.
