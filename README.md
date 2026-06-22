# CardPilot — Visiting Card Digitization & Voice Notes Orchestrator

> A full-stack AI agent that photographs visiting cards, extracts contact data, deduplicates against Google Sheets, sends WhatsApp alerts, and links voice notes — all orchestrated by a single LangGraph agent with MongoDB-persisted state.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Tech Stack](#tech-stack)
3. [Local Development Setup](#local-development-setup)
4. [Environment Variables](#environment-variables)
5. [Running with Docker Compose](#running-with-docker-compose)
6. [Deploying to Render](#deploying-to-render)
7. [API Reference](#api-reference)
8. [LangGraph Agent Design](#langgraph-agent-design)
9. [Project Structure](#project-structure)
10. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌──────────────┐    multipart/SSE    ┌─────────────────────────────────────────┐
│  React UI    │ ◄──────────────────►│            FastAPI Backend              │
│ (Vite/Nginx) │                     │                                         │
└──────────────┘                     │  ┌──────────────────────────────────┐   │
                                     │  │        LangGraph Agent           │   │
                                     │  │                                  │   │
                                     │  │  extract_card                    │   │
                                     │  │       ↓                          │   │
                                     │  │  human_confirmation (interrupt)  │   │
                                     │  │       ↓                          │   │
                                     │  │  dedup_check                     │   │
                                     │  │       ↓                          │   │
                                     │  │  log_contact ──► send_notification│  │
                                     │  │       ↓                          │   │
                                     │  │  [await voice] ◄── voice_intake  │   │
                                     │  │       ↓                          │   │
                                     │  │  transcribe → summarize          │   │
                                     │  │       ↓                          │   │
                                     │  │  update_sheet_with_voice         │   │
                                     │  └──────────────────────────────────┘   │
                                     │          │           │           │       │
                                     │    Gemini Vision  Whisper    Gemini LLM │
                                     └──────────┼───────────┼───────────┼──────┘
                                                │           │           │
                                          Google Sheets  Cloudinary  WhatsApp
                                          MongoDB Atlas              Business API
```

**Key design decision — single LangGraph agent:** All business logic (extraction, dedup, Sheet I/O, WhatsApp, voice processing) lives inside the graph as nodes and conditional edges. FastAPI is a thin HTTP layer that seeds state and invokes the graph; it contains no routing logic itself.

**State persistence:** The graph uses a MongoDB-backed checkpointer. This means a voice note uploaded in a separate HTTP request minutes later automatically finds `sheet_row_id` from the same session checkpoint without any extra user input.

---

## Tech Stack

| Layer | Technology |
|---|---|
| AI orchestration | LangGraph (StateGraph + MongoDBSaver) |
| LLM / Vision | Gemini 2.5 Flash |
| Transcription | OpenAI Whisper API |
| Backend | FastAPI + Python 3.12 |
| Frontend | React 18 + Vite + Tailwind CSS |
| Database (state) | MongoDB Atlas M0 (free tier) |
| Contact database | Google Sheets API |
| Notifications | WhatsApp Business API (Meta Cloud API) |
| Media storage | Cloudinary (free tier) |
| Containerization | Docker + Docker Compose |
| Deployment | Render (backend Web Service + frontend Static Site) |

---

## Local Development Setup

### Prerequisites

- Python 3.12+
- Node.js 20+
- Docker & Docker Compose (optional, for containerised run)

### 1. Clone the repository

```bash
git clone https://github.com/your-username/visiting-card-agent.git
cd visiting-card-agent
```

### 2. Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
pip install -r requirements-dev.txt  # for tests
cp .env.example .env
# Edit .env with your real credentials (see Environment Variables below)
uvicorn app.main:create_app --factory --reload --port 8000
```

### 3. Frontend

```bash
cd frontend
npm install
# Optional: create frontend/.env.local with VITE_API_URL=http://localhost:8000
npm run dev
```

The frontend dev server runs on `http://localhost:5173` and proxies `/api/*` to the backend.

### 4. Running tests

```bash
cd backend
pytest -v
```

---

## Environment Variables

Copy `backend/.env.example` to `backend/.env` and fill in the values below.

| Variable | Description |
|---|---|
| `ENVIRONMENT` | `local` or `production` |
| `LOG_LEVEL` | `DEBUG` / `INFO` / `WARNING` |
| `CORS_ORIGINS` | JSON array of allowed frontend origins, e.g. `["http://localhost:5173"]` |
| `MONGODB_URI` | MongoDB Atlas connection string |
| `MONGODB_DB_NAME` | Database name (e.g. `visiting_card_agent`) |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Path to the service-account JSON file **or** the full JSON as a single-line string |
| `GOOGLE_SHEET_ID` | The ID segment from your Sheet URL (`/d/<ID>/edit`) |
| `GEMINI_API_KEY` | Google AI Studio API key |
| `OPENAI_API_KEY` | OpenAI API key (for Whisper transcription) |
| `WHATSAPP_ACCESS_TOKEN` | Meta permanent access token |
| `WHATSAPP_PHONE_NUMBER_ID` | Your WhatsApp Business phone number ID |
| `WHATSAPP_MANAGER_NUMBER` | Recipient number in E.164 format (e.g. `+919876543210`) |
| `CLOUDINARY_CLOUD_NAME` | Cloudinary cloud name |
| `CLOUDINARY_API_KEY` | Cloudinary API key |
| `CLOUDINARY_API_SECRET` | Cloudinary API secret |

### Google Service Account setup

1. Google Cloud Console → APIs & Services → Credentials → Create Service Account.
2. Grant it the **Editor** role (or a custom role with Sheets API write access).
3. Keys → Add Key → JSON. Download the file.
4. **Share your target Google Sheet** with the service account's email address (found in the JSON as `client_email`) — this is the most common setup mistake.
5. Set `GOOGLE_SERVICE_ACCOUNT_JSON` to the path of the downloaded file, or paste the entire JSON (minified, one line) as the env value.

### WhatsApp template

Before sending messages, submit a message template in the Meta developer dashboard:
- Template name: `new_contact_logged`
- Category: **Utility**
- Body: `A new contact has been logged: {{1}} from {{2}}. Phone: {{3}}.`

Template approval takes minutes to ~24 hours. Kick this off **immediately** — it's the longest external dependency.

---

## Running with Docker Compose

```bash
# Ensure backend/.env is filled in
docker compose up --build
```

- Frontend: `http://localhost:3000`
- Backend: `http://localhost:8000`
- API docs: `http://localhost:8000/docs`

---

## Deploying to Render

### Backend (Web Service)

1. New → Web Service → connect your GitHub repo.
2. Root directory: `backend`
3. Build command: `pip install -r requirements.txt`
4. Start command: `uvicorn app.main:create_app --factory --host 0.0.0.0 --port $PORT`
5. Add all environment variables from the table above in the Render dashboard.
6. For `GOOGLE_SERVICE_ACCOUNT_JSON`, paste the minified JSON string directly as the env value (no file path needed in production).

### Frontend (Static Site)

1. New → Static Site → same repo.
2. Root directory: `frontend`
3. Build command: `npm install && npm run build`
4. Publish directory: `dist`
5. Add environment variable: `VITE_API_URL=https://your-backend.onrender.com`

> **Cold start note:** Render's free tier spins down after 15 minutes of inactivity. Warm up the backend before your demo by hitting `/api/health`.

---

## API Reference

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/health` | Health check |
| `GET` | `/api/sessions` | List all sessions (sorted by last active) |
| `POST` | `/api/sessions` | Create a new session |
| `POST` | `/api/sessions/{id}/upload/card` | Upload a visiting card image |
| `POST` | `/api/sessions/{id}/upload/voice` | Upload a voice note |
| `POST` | `/api/sessions/{id}/confirm` | Confirm or reject extracted details |
| `GET` | `/api/sessions/{id}/stream` | SSE stream of agent progress events |

Full interactive docs at `/docs` (Swagger) and `/redoc`.

---

## LangGraph Agent Design

The agent is a `StateGraph` compiled with a MongoDB checkpointer. Here is the node sequence:

```
[START]
   │
   ▼
extract_card          — Gemini Vision reads the card image URL and returns structured fields + confidence scores
   │
   ▼
human_confirmation    — Graph INTERRUPT; waits for the user to confirm/edit/reject via the UI
   │ (resume)
   ▼
dedup_check           — Reads all rows from Google Sheets; fuzzy-matches on name + phone + email using combined similarity score
   │                   — If duplicate: notifies user, transitions to awaiting_voice (no new row)
   │                   — If unique: continues
   ▼
log_contact           — Appends a new row to Google Sheets; stores row_id in checkpoint state
   │
   ▼
send_notification     — Calls WhatsApp Business API with the contact details; failure is non-fatal
   │
   ▼
[awaiting_voice]      — Graph pauses; session stays open for a voice note upload

On next invocation (voice note upload):
   │
   ▼
voice_intake          — audio_url is injected into checkpoint state
   │
   ▼
transcribe_audio      — OpenAI Whisper transcribes the audio URL
   │
   ▼
summarize_transcript  — Gemini LLM summarises the transcript into a concise note
   │
   ▼
update_sheet_with_voice — Finds the row by sheet_row_id and updates the audio_url + summary columns
   │
   ▼
[END]
```

**Why LangGraph and not a function pipeline?**
The graph topology provides three things a plain Python pipeline cannot:
1. **Interrupt / resume** — the human-confirmation step pauses execution mid-graph, returns control to the user, and resumes from the exact same state across a different HTTP request.
2. **Persistent state** — the MongoDB checkpointer keeps `sheet_row_id`, `active_contact_name`, and the full message history alive between the card upload and the voice note upload, which can arrive minutes or hours apart.
3. **Conditional routing** — the dedup edge branches to a "duplicate" path without the caller needing to know; routing is data-driven inside the graph.

---

## Project Structure

```
visiting-card-agent/
├── backend/
│   ├── app/
│   │   ├── agent/
│   │   │   ├── graph.py          # StateGraph definition; all edges and conditions
│   │   │   ├── state.py          # AgentState TypedDict + default_state()
│   │   │   ├── checkpointer.py   # MongoDB-backed LangGraph checkpointer factory
│   │   │   ├── ports.py          # Abstract interfaces (Vision, Sheets, etc.)
│   │   │   └── nodes/            # One file per graph node
│   │   │       ├── extraction.py
│   │   │       ├── confirmation.py
│   │   │       ├── dedup.py
│   │   │       ├── sheet_write.py
│   │   │       ├── notify.py
│   │   │       ├── voice_intake.py
│   │   │       ├── transcription.py
│   │   │       ├── summary.py
│   │   │       └── sheet_update.py
│   │   ├── api/
│   │   │   ├── dependencies.py
│   │   │   └── routes/
│   │   │       ├── health.py
│   │   │       ├── sessions.py
│   │   │       ├── uploads.py    # Card + voice upload; invokes graph
│   │   │       └── stream.py     # SSE endpoint; maps node names → progress msgs
│   │   ├── core/
│   │   │   ├── config.py         # Pydantic Settings; reads from .env
│   │   │   ├── exceptions.py     # Custom exception types + FastAPI handlers
│   │   │   └── logging.py        # Structured JSON logging
│   │   ├── models/
│   │   │   └── session.py        # SessionMeta, SessionCreate Pydantic models
│   │   ├── tools/                # Real implementations of the port interfaces
│   │   │   ├── vision.py         # GeminiVision
│   │   │   ├── sheets.py         # GoogleSheets
│   │   │   ├── whatsapp.py       # WhatsAppNotifier
│   │   │   ├── audio.py          # WhisperTranscription
│   │   │   ├── storage.py        # CloudinaryStorage
│   │   │   └── llm.py            # GeminiLLM (summary)
│   │   └── main.py               # FastAPI app factory + lifespan
│   ├── tests/
│   │   ├── agent/                # Graph-level tests with fake ports
│   │   ├── api/                  # Route integration tests
│   │   └── tools/                # Unit tests for dedup, similarity, etc.
│   ├── Dockerfile
│   ├── requirements.txt
│   └── .env.example
├── frontend/
│   ├── src/
│   │   ├── api/client.js         # All fetch/SSE calls to the backend
│   │   ├── hooks/
│   │   │   ├── useSessions.js    # Session CRUD + selection
│   │   │   └── useChat.js        # Upload, confirm, SSE, message state
│   │   ├── components/chat/
│   │   │   ├── Sidebar.jsx       # Session list + new session button
│   │   │   ├── ChatWindow.jsx    # Message list + interrupt slot
│   │   │   ├── MessageBubble.jsx # Renders text/image/audio/progress/error
│   │   │   ├── ConfirmationDialog.jsx  # Human-in-the-loop card review
│   │   │   └── InputBar.jsx      # File pickers + drag-and-drop
│   │   ├── App.jsx
│   │   └── main.jsx
│   ├── Dockerfile                # Multi-stage: Vite build → Nginx
│   ├── nginx.conf                # SPA routing + /api proxy to backend
│   └── package.json
└── docker-compose.yml
```

---

## Troubleshooting

**"Session not found" on upload**
Make sure you created a session (`POST /api/sessions`) before uploading. The frontend does this automatically when you click "New session".

**WhatsApp message not arriving**
- Verify the template `new_contact_logged` is approved in the Meta dashboard.
- The recipient number (`WHATSAPP_MANAGER_NUMBER`) must have sent a message to your test number within the last 24 hours, OR you must be using an approved template (which bypasses the 24-hour rule).
- Check the backend logs for `whatsapp_sent: false` — the agent continues even if WhatsApp fails.

**Google Sheets "Permission denied"**
You must share the target Sheet with the service account email (`client_email` field inside the JSON). This is the single most common setup issue.

**Render cold start / timeout on first request**
Render's free instances sleep after 15 minutes. Hit `GET /api/health` once to warm up the backend before your demo.

**Voice note not linked to the right contact**
The link is maintained via `sheet_row_id` in the LangGraph checkpoint. If the session was reset (e.g. a new session created), upload a card first to establish the checkpoint before uploading a voice note.

**Cloudinary upload fails locally**
Ensure `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, and `CLOUDINARY_API_SECRET` are set. The free tier supports 25 GB storage and 25 GB bandwidth — more than enough for this demo.
