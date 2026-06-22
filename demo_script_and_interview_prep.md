# Demo Video Script & Interview Preparation
## CardPilot — Visiting Card Digitization & Voice Notes Orchestrator

---

## Demo Video (3–5 minutes)

### Pre-flight checklist (do this 10 minutes before recording)

- [ ] Hit `GET /api/health` to warm up the Render backend
- [ ] Open the live frontend URL in a browser — confirm the sidebar loads
- [ ] Have a sample visiting card image ready (use a real card or a good mock)
- [ ] Have a 15–30 second voice note audio file ready (MP3 or WAV)
- [ ] Open the Google Sheet in another tab so you can switch to it live
- [ ] Ensure WhatsApp is open on your phone for the notification reveal
- [ ] Set your browser zoom to ~90% so all UI elements are visible

---

### Script

**[0:00–0:30] — Hook and overview**

> "I built CardPilot — an AI agent that digitizes visiting cards. You upload a card image, it extracts the contact, checks for duplicates, saves to Google Sheets, and fires a WhatsApp notification. And when you later upload a voice note from the conference, it automatically links it to that contact. The entire workflow is orchestrated by a single LangGraph agent — no separate scripts, no parallel pipelines. Let me show you."

*Screen: Show the live frontend URL. Point out the multi-session sidebar.*

---

**[0:30–1:30] — Happy path: upload a card**

1. Click "New session" → a session appears in the sidebar.
2. Click "Upload card" → select your sample visiting card image.
3. The image appears in the chat as a user message.
4. The progress indicators appear: "🔍 Extracting card details…" → "✋ Waiting for your confirmation…"
5. The **ConfirmationDialog** appears with extracted fields and per-field confidence scores.

> "The agent pauses here — this is LangGraph's interrupt mechanism. The graph is literally suspended, waiting for my input. I can edit any field before confirming. I'll adjust the phone number format..."

6. Edit a field, then click "Confirm & save."
7. Progress resumes: "🔎 Checking for duplicates…" → "💾 Saving to sheet…" → "📲 Sending WhatsApp notification…"
8. Success message: "✅ Contact logged!"

*Switch tab to Google Sheets — show the new row live.*

---

**[1:30–2:00] — WhatsApp notification**

*Switch to phone.*
> "The WhatsApp notification arrived — name, company, phone — so the manager knows without opening Sheets."

*Back to browser.*

---

**[2:00–2:45] — Duplicate detection**

1. Upload the **same card image** again (or a slightly different photo of the same card).
2. Confirm again.
3. The agent returns: "This contact already exists — duplicate detected."

> "The deduplication isn't just exact-match. It uses a weighted similarity score across name, phone, and email — normalizing phone formats, case-insensitive email comparison, and fuzzy name matching. So if the phone is formatted differently or the name has a typo, it still catches it."

*Show the Sheet — confirm no duplicate row was added.*

---

**[2:45–3:45] — Voice note**

1. Back to the original session (select from sidebar).
2. Click "Voice note" → upload the audio file.
3. The audio player appears in the chat.
4. Progress: "🎙️ Processing voice note…" → "📝 Transcribing…" → "🤖 Generating summary…" → "💾 Updating contact record…"
5. Success: "✅ Voice note saved and contact record updated."

*Switch to Google Sheets — scroll right to show audio URL and summary columns updated.*

> "The voice note was automatically linked to the contact we logged earlier — not because I specified which contact it belongs to, but because the LangGraph agent remembered the sheet row ID from the checkpoint in MongoDB. This state survived as a separate HTTP request."

---

**[3:45–4:30] — Architecture walkthrough (optional, if time allows)**

*Show a simple diagram or the README architecture section.*

> "Here's the graph topology. Every node is a Python async function. The edges are conditional — dedup_check routes to either the 'duplicate' branch or 'log_contact' based on the similarity score in state. The interrupt at human_confirmation suspends execution and resumes when I POST to /confirm with the fields. FastAPI itself contains no routing logic — it just seeds state and calls graph.ainvoke()."

---

**[4:30–5:00] — Wrap-up**

> "The full stack: React frontend, FastAPI backend, LangGraph agent with MongoDB checkpointing, Google Sheets as the contact database, Cloudinary for audio storage, OpenAI Whisper for transcription, Gemini for extraction and summarization, and WhatsApp Business API for notifications. All containerized with Docker, deployed on Render. Links in the description. Happy to answer questions."

---

## Anticipated Interview Questions & Strong Answers

---

**Q: Why LangGraph and not just a function pipeline?**

> Three reasons. First, the human-in-the-loop confirmation requires a true pause-and-resume across separate HTTP requests — that's exactly what LangGraph's interrupt mechanism gives you. A function pipeline would need you to build a custom state machine. Second, the MongoDB checkpointer makes session state durable across restarts, so the voice note upload can happen hours later and still find the right contact. Third, conditional routing (the dedup branch) lives inside the graph as data-driven edges, not scattered if-statements in the API layer. LangGraph makes these patterns first-class.

---

**Q: How does the deduplication work?**

> It's weighted fuzzy similarity across three fields. Email gets the highest weight — if emails match case-insensitively, it's almost certainly the same person. Phone is normalized first (strip spaces, dashes, brackets, normalize country codes) then compared exactly. Name uses token-set ratio so "Alice Smith" and "A. Smith" still score well. The combined score is compared against a 0.6 threshold. Below that, it's a new contact; above, it's a duplicate.

---

**Q: What happens if the Gemini API is down?**

> The extraction node wraps the API call in a try/except. On failure it sets stage to 'error' and populates error_message in state. The SSE stream picks up the error stage and pushes an error event to the frontend, which renders it as a red error bubble. The session remains open so the user can retry — they just upload the card again.

---

**Q: How is state linked between the card upload and the voice note upload?**

> When log_contact successfully appends a row to Sheets, it writes the row UUID (`sheet_row_id`) into the AgentState and the graph checkpointer persists that to MongoDB. When the voice note arrives as a separate HTTP request, the uploads route calls `graph.aupdate_state()` to inject the audio URL into the existing checkpoint, then re-invokes the graph from the `voice_intake` node. The graph reads `sheet_row_id` from its own state — no session hacks, no frontend passing IDs around.

---

**Q: What are the production risks you'd address before going live?**

> Four main ones. One: Render's free tier cold-starts — I'd upgrade to a paid instance or use a keep-alive ping. Two: Google Sheets has rate limits (~100 requests/100 seconds); I'd add a write queue and retry with exponential backoff for real scale. Three: Cloudinary free tier bandwidth limits — I'd move to a proper S3 bucket. Four: the WhatsApp template is tied to a test number — I'd complete Business Verification to send to arbitrary numbers.

---

**Q: Why MongoDB and not a SQL database for checkpointing?**

> LangGraph's MongoDB checkpointer is the official first-party integration for document storage of graph state. State is a nested dict of varying shape (different sessions might be at different stages with different fields populated) — document storage handles that schema flexibility better than rigid SQL columns. MongoDB Atlas M0 is also the free tier explicitly mentioned in the assignment spec.

---

**Q: What's the confidence score and why did you include it?**

> Gemini's extraction prompt asks for a 0–1 confidence score per field alongside the extracted value. This surfaces when OCR is uncertain — a stylized font, a glossy card, a smudged area. Rather than hiding that uncertainty, the ConfirmationDialog shows it as a colour-coded badge next to each field. Red means the agent is unsure; the user knows to double-check that field before confirming. It also makes the human-in-the-loop step more useful — users don't just rubber-stamp everything.

---

## Talking Points for Q&A

- The single-agent constraint is the hardest architectural constraint — explain how you honoured it.
- Deduplication is the most common failure mode in demos — explain the fuzzy logic unprompted.
- SSE was chosen over WebSocket because it's simpler (one-directional) and sufficient for the use case.
- The ports/adapters pattern (abstract interfaces + real implementations + fake implementations for tests) is worth mentioning for code quality points.
- You skipped LinkedIn enrichment deliberately — ToS issues and fragility in a 48-hour window.
