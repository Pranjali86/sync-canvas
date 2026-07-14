# SyncCanvas

![React](https://img.shields.io/badge/React-18.x-149ECA?logo=react&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-20.x-339933?logo=node.js&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-5.x-3178C6?logo=typescript&logoColor=white)
![TailwindCSS](https://img.shields.io/badge/TailwindCSS-3.x-38B2AC?logo=tailwind-css&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![Prisma](https://img.shields.io/badge/Prisma-6.x-2D3748?logo=prisma&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-S3%20%2B%20CloudFront%20%2B%20EC2-FF9900?logo=amazonaws&logoColor=white)

**SyncCanvas** is a real-time collaborative visual workspace for system design, diagrams, and team sketching. Multiple users can draw together with live cursor tracking, persistent board history, and secure JWT authentication.

The repository includes Docker-based local development and AWS deployment automation for S3, CloudFront, EC2, and PostgreSQL.

---

## ✨ Features

- **Real-time Collaboration** — Low-latency scene sync via WebSockets; every stroke appears instantly for all participants.
- **Live Cursors & Presence** — See collaborators' cursors and active-user status in real time.
- **Persistent Boards** — Board state is stored in PostgreSQL so work is never lost between sessions.
- **Version History** — Save named snapshots and restore any previous state of a board.
- **Secure Auth** — JWT-based sign-in and sign-up with protected board routes.
- **Viewer Mode** — Share a read-only board link via `?role=viewer`.
- **Premium UI** — Glassmorphic panels, Inter typography, dark/light theme toggle.

---

## 🛠 Tech Stack

### Frontend
| Layer | Technology |
|-------|-----------|
| Framework | React 18 + Vite |
| Language | TypeScript |
| Styling | Tailwind CSS |
| Icons | Lucide React |
| Whiteboard | Excalidraw |
| Routing | React Router v7 |

### Backend
| Layer | Technology |
|-------|-----------|
| Runtime | Node.js 20 |
| Framework | Express |
| WebSocket | `ws` library |
| Auth | JSON Web Tokens (JWT) |
| ORM | Prisma 6 |
| Database | PostgreSQL 16 (Docker) |

### Infrastructure
| Service | Purpose |
|---------|---------|
| AWS S3 | Frontend static hosting |
| AWS CloudFront | CDN + HTTPS + API/WS routing |
| AWS EC2 | Backend server (Docker Compose) |
| GitHub Actions | CI/CD pipeline |

---

## 🏗 Architecture

```
Browser (HTTPS)
      │
      ▼
CloudFront  ──── /          ──►  S3 Bucket (React SPA)
(HTTPS CDN)      /api/*     ──►  EC2 nginx  ──►  Node.js :3000
                 /ws*        ──►  EC2 nginx  ──►  WebSocket Server
                                      │
                                      ▼
                                 PostgreSQL (Docker)
```

All client traffic flows through CloudFront over HTTPS. CloudFront routes API calls and WebSocket connections to the EC2 origin, which runs the Node.js backend and PostgreSQL via Docker Compose.

---

## 🚀 Local Development

### Prerequisites
- Node.js 20+
- Docker & Docker Compose (for PostgreSQL)

### 1. Clone & install

```bash
git clone https://github.com/Pranjali86/sync-canvas.git
cd sync-canvas
npm install
```

### 2. Start PostgreSQL

```bash
docker compose up -d db
```

### 3. Configure environment

Create `server/.env`:
```env
PORT=3000
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/whiteboard"
JWT_SECRET="your-secret-key-here"
CORS_ORIGINS="http://localhost:5173"
```

Create `client/.env`:
```env
VITE_API_BASE_URL=http://localhost:3000
VITE_WS_BASE_URL=ws://localhost:3000
```

### 4. Run migrations & start

```bash
# Apply schema to local DB
cd server && npx prisma db push && cd ..

# Start backend and frontend in parallel
npm run dev
```

| Service | URL |
|---------|-----|
| Frontend | http://localhost:5173 |
| Backend API | http://localhost:3000 |
| Health check | http://localhost:3000/health |

---

## 🐳 Production Deployment

The app ships via **GitHub Actions** on every push to `main`.

### GitHub Secrets required

| Secret | Description |
|--------|-------------|
| `VITE_API_BASE_URL` | CloudFront HTTPS base URL |
| `VITE_WS_BASE_URL` | CloudFront WSS URL with `/ws` path |
| `AWS_ACCESS_KEY_ID` | IAM key with S3 + CloudFront permissions |
| `AWS_SECRET_ACCESS_KEY` | IAM secret |
| `AWS_REGION` | e.g. `ap-south-1` |
| `S3_BUCKET_NAME` | Frontend bucket name |
| `CLOUDFRONT_DISTRIBUTION_ID` | CloudFront distribution ID |
| `EC2_HOST` | EC2 public IP |
| `EC2_SSH_KEY` | PEM private key (contents) |

### Deploy pipeline

1. **Frontend job** — builds the React app with env vars injected at build time, syncs assets to S3 (long-lived cache), uploads `index.html` (no-cache), invalidates CloudFront.
2. **Backend job** (runs after frontend) — SSHs into EC2 and runs `docker compose up -d --build --no-deps server` to rebuild only the server container, preserving the PostgreSQL data volume.

### EC2 `.env` (at `/app/sync-canvas/.env`)

```env
DB_PASSWORD=<strong-random-password>
JWT_SECRET=<long-random-secret>
CORS_ORIGINS=https://<your-cloudfront-domain>.cloudfront.net
```

---

## 📁 Project Structure

```
sync-canvas/
├── client/                  # React + Vite frontend
│   └── src/
│       ├── components/      # Navbar, ProtectedRoute, CursorLayer …
│       ├── contexts/        # AuthContext, ThemeContext
│       ├── hooks/           # useRoom, useWebSocket …
│       ├── pages/           # Home, BoardPage, LoginPage, SignupPage
│       └── services/        # apiClient, socketProtocol
├── server/                  # Node.js + Express backend
│   ├── prisma/              # Schema + migrations
│   └── src/
│       ├── controllers/     # auth, board, health
│       ├── middleware/      # authMiddleware
│       ├── rooms/           # RoomManager
│       ├── services/        # AuthService, DatabaseService
│       └── websocket/       # WebSocketHandler
├── deploy/                  # nginx config + EC2 bootstrap script
├── docker-compose.yml       # PostgreSQL + server containers
└── .github/workflows/       # CI and deploy pipelines
```

---

## 📄 License

MIT. SyncCanvas modifications © Pranjali. The original ExcaliLive copyright and
MIT permission notice are preserved in [LICENSE](LICENSE).
