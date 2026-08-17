#!/usr/bin/env bash
set -euo pipefail
# Edit REPO if you want to target a different repository URL
REPO="https://github.com/Joe2781/Social-app.git"
BRANCH="init/social-x"

TMPDIR="$(mktemp -d)"
echo "Using temp dir: $TMPDIR"
cd "$TMPDIR"

# Clone (shallow) to a temp dir so we don't disturb local clones
git clone "$REPO" repo
cd repo
git fetch origin

# Create or checkout branch
if git rev-parse --verify --quiet "refs/heads/${BRANCH}"; then
  echo "Local branch ${BRANCH} exists — checking out"
  git checkout "${BRANCH}"
else
  # If remote branch exists, base on it; otherwise create new branch from main/default
  if git ls-remote --exit-code --heads origin "${BRANCH}" >/dev/null 2>&1; then
    git checkout -b "${BRANCH}" "origin/${BRANCH}"
  else
    # Try to find default branch name from remote
    DEFAULT_BRANCH=$(git remote show origin | awk -F': ' '/HEAD branch/ {print $2}')
    if [ -z "$DEFAULT_BRANCH" ]; then
      DEFAULT_BRANCH="main"
    fi
    git checkout -b "${BRANCH}" "origin/${DEFAULT_BRANCH}" || git checkout -b "${BRANCH}"
  fi
fi

# Create directories
mkdir -p README.md backend/cmd/server backend/internal/db/sqlite backend/internal/db/ghostdb backend/internal/seed backend/internal/auth backend/internal/handlers frontend/src/components frontend/src/pages .github/workflows frontend

# Write main files (you can review/modify them after the script completes)
cat > README.md <<'EOF'
# Social X (My Social Media App)

This repository contains the Social X MVP: a mobile-first social media platform built with React (Vite + TypeScript + Tailwind) for the frontend and Go for the backend.

Run locally (development):
1. Start the backend:
   - cd backend
   - go run ./cmd/server

2. Start the frontend:
   - cd frontend
   - npm install
   - npm run dev

Seed demo accounts:
- demo1 / password123

This initial commit is a scaffold; I will continue expanding features after you review.
EOF

cat > .env.example <<'EOF'
# Backend
DATABASE_URL=file:./data/socialx.db
PORT=8080
JWT_SECRET=change-me-in-production

# Redis (optional)
REDIS_URL=redis://localhost:6379

# Translation providers
GOOGLE_TRANSLATE_API_KEY=
LIBRE_TRANSLATE_URL=
EOF

cat > .gitignore <<'EOF'
node_modules
frontend/node_modules
backend/bin
backend/data
.env
.env.local
dist
.vscode
.DS_Store
EOF

cat > docker-compose.yml <<'EOF'
version: '3.8'
services:
  backend:
    build: ./backend
    command: go run ./cmd/server
    volumes:
      - ./backend:/app
      - ./backend/data:/app/data
    ports:
      - "8080:8080"
  frontend:
    build: ./frontend
    command: npm run dev
    ports:
      - "5173:5173"
EOF

# Backend go.mod
cat > backend/go.mod <<'EOF'
module github.com/Joe2781/Social-app/backend

go 1.20

require (
    github.com/golang-jwt/jwt/v5 v5.0.0
    golang.org/x/crypto v0.12.0
    modernc.org/sqlite v1.21.0
    github.com/google/uuid v1.3.0
)
EOF

# Backend main
cat > backend/cmd/server/main.go <<'EOF'
package main

import (
    "context"
    "database/sql"
    "embed"
    "log"
    "net/http"
    "os"
    "time"

    _ "modernc.org/sqlite"

    "github.com/Joe2781/Social-app/backend/internal/db/sqliteimpl"
    "github.com/Joe2781/Social-app/backend/internal/handlers"
)

 //go:embed assets/*
var assets embed.FS

func main() {
    port := getenv("PORT", "8080")
    dbURL := getenv("DATABASE_URL", "file:./data/socialx.db")
    log.Printf("starting backend on :%s; db=%s", port, dbURL)

    if err := os.MkdirAll("backend/data", 0755); err != nil {
        log.Printf("mkdir data: %v", err)
    }

    db, err := sql.Open("sqlite", dbURL)
    if err != nil {
        log.Fatalf("open db: %v", err)
    }
    defer db.Close()

    if err := sqliteimpl.Migrate(db); err != nil {
        log.Fatalf("migrate: %v", err)
    }

    ghost, err := sqliteimpl.New(db)
    if err != nil {
        log.Fatalf("ghostdb: %v", err)
    }

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    if err := sqliteimpl.SeedIfNeeded(ctx, ghost); err != nil {
        log.Fatalf("seed: %v", err)
    }

    h := handlers.New(ghost)

    mux := http.NewServeMux()
    mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("ok"))
    })
    mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte("ready"))
    })

    mux.Handle("/api/", http.StripPrefix("/api", h.Routes()))

    mux.Handle("/", http.FileServer(http.FS(assets)))

    srv := &http.Server{
        Addr:         ":" + port,
        Handler:      loggingMiddleware(mux),
        ReadTimeout:  15 * time.Second,
        WriteTimeout: 15 * time.Second,
        IdleTimeout:  60 * time.Second,
    }

    log.Printf("server listening on %s", srv.Addr)
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("listen: %v", err)
    }
}

func getenv(k, def string) string {
    v := os.Getenv(k)
    if v == "" {
        return def
    }
    return v
}

func loggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
    })
}
EOF

# ghostdb interface
cat > backend/internal/db/ghostdb/interface.go <<'EOF'
package ghostdb

import "context"

// Models

type User struct {
    ID                string `db:"id" json:"id"`
    Username          string `db:"username" json:"username"`
    DisplayName       string `db:"display_name" json:"display_name"`
    Email             string `db:"email" json:"email"`
    PasswordHash      string `db:"password_hash" json:"-"`
    AvatarURL         string `db:"avatar_url" json:"avatar_url"`
    Bio               string `db:"bio" json:"bio"`
    PreferredLanguage string `db:"preferred_language" json:"preferred_language"`
    CreatedAt         int64  `db:"created_at" json:"created_at"`
    UpdatedAt         int64  `db:"updated_at" json:"updated_at"`
}

type Post struct {
    ID        string `db:"id" json:"id"`
    AuthorID  string `db:"author_id" json:"author_id"`
    Text      string `db:"text" json:"text"`
    MediaURL  string `db:"media_url" json:"media_url"`
    MediaType string `db:"media_type" json:"media_type"`
    Language  string `db:"language" json:"language"`
    Visibility string `db:"visibility" json:"visibility"`
    CreatedAt int64  `db:"created_at" json:"created_at"`
    UpdatedAt int64  `db:"updated_at" json:"updated_at"`
}

// Database interface
type DB interface {
    CreateUser(ctx context.Context, u *User) error
    GetUserByUsername(ctx context.Context, username string) (*User, error)
    GetUserByID(ctx context.Context, id string) (*User, error)

    CreatePost(ctx context.Context, p *Post) error
    GetPost(ctx context.Context, id string) (*Post, error)
    ListFeed(ctx context.Context, limit, offset int) ([]*Post, error)

    // translation cache
    GetTranslation(ctx context.Context, contentHash, sourceLang, targetLang string) (string, error)
    SetTranslation(ctx context.Context, contentHash, sourceLang, targetLang, translated string) error
}
EOF

# sqlite implementation (migration + basic methods)
cat > backend/internal/db/sqlite/sqlite.go <<'EOF'
package sqliteimpl

import (
    "context"
    "database/sql"
    "errors"
    "time"

    "github.com/google/uuid"
    "github.com/Joe2781/Social-app/backend/internal/db/ghostdb"
)

type sqliteDB struct {
    db *sql.DB
}

func New(db *sql.DB) (ghostdb.DB, error) {
    return &sqliteDB{db: db}, nil
}

func Migrate(db *sql.DB) error {
    schema := `
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  email TEXT,
  password_hash TEXT,
  avatar_url TEXT,
  bio TEXT,
  preferred_language TEXT,
  created_at INTEGER,
  updated_at INTEGER
);

CREATE TABLE IF NOT EXISTS posts (
  id TEXT PRIMARY KEY,
  author_id TEXT NOT NULL,
  text TEXT,
  media_url TEXT,
  media_type TEXT,
  language TEXT,
  visibility TEXT,
  created_at INTEGER,
  updated_at INTEGER,
  FOREIGN KEY(author_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS translation_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_hash TEXT NOT NULL,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  translated_text TEXT NOT NULL,
  created_at INTEGER
);
`
    _, err := db.Exec(schema)
    return err
}

func (s *sqliteDB) CreateUser(ctx context.Context, u *ghostdb.User) error {
    if u.ID == "" {
        u.ID = uuid.NewString()
    }
    now := time.Now().Unix()
    u.CreatedAt = now
    u.UpdatedAt = now
    _, err := s.db.ExecContext(ctx, `INSERT INTO users(id,username,display_name,email,password_hash,avatar_url,bio,preferred_language,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)`, u.ID, u.Username, u.DisplayName, u.Email, u.PasswordHash, u.AvatarURL, u.Bio, u.PreferredLanguage, u.CreatedAt, u.UpdatedAt)
    if err != nil {
        return err
    }
    return nil
}

func (s *sqliteDB) GetUserByUsername(ctx context.Context, username string) (*ghostdb.User, error) {
    row := s.db.QueryRowContext(ctx, `SELECT id,username,display_name,email,password_hash,avatar_url,bio,preferred_language,created_at,updated_at FROM users WHERE username = ?`, username)
    u := &ghostdb.User{}
    err := row.Scan(&u.ID, &u.Username, &u.DisplayName, &u.Email, &u.PasswordHash, &u.AvatarURL, &u.Bio, &u.PreferredLanguage, &u.CreatedAt, &u.UpdatedAt)
    if err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return nil, nil
        }
        return nil, err
    }
    return u, nil
}

func (s *sqliteDB) GetUserByID(ctx context.Context, id string) (*ghostdb.User, error) {
    row := s.db.QueryRowContext(ctx, `SELECT id,username,display_name,email,password_hash,avatar_url,bio,preferred_language,created_at,updated_at FROM users WHERE id = ?`, id)
    u := &ghostdb.User{}
    err := row.Scan(&u.ID, &u.Username, &u.DisplayName, &u.Email, &u.PasswordHash, &u.AvatarURL, &u.Bio, &u.PreferredLanguage, &u.CreatedAt, &u.UpdatedAt)
    if err != nil {
        return nil, err
    }
    return u, nil
}

func (s *sqliteDB) CreatePost(ctx context.Context, p *ghostdb.Post) error {
    if p.ID == "" {
        p.ID = uuid.NewString()
    }
    now := time.Now().Unix()
    p.CreatedAt = now
    p.UpdatedAt = now
    _, err := s.db.ExecContext(ctx, `INSERT INTO posts(id,author_id,text,media_url,media_type,language,visibility,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)`, p.ID, p.AuthorID, p.Text, p.MediaURL, p.MediaType, p.Language, p.Visibility, p.CreatedAt, p.UpdatedAt)
    return err
}

func (s *sqliteDB) GetPost(ctx context.Context, id string) (*ghostdb.Post, error) {
    row := s.db.QueryRowContext(ctx, `SELECT id,author_id,text,media_url,media_type,language,visibility,created_at,updated_at FROM posts WHERE id = ?`, id)
    p := &ghostdb.Post{}
    err := row.Scan(&p.ID, &p.AuthorID, &p.Text, &p.MediaURL, &p.MediaType, &p.Language, &p.Visibility, &p.CreatedAt, &p.UpdatedAt)
    if err != nil {
        return nil, err
    }
    return p, nil
}

func (s *sqliteDB) ListFeed(ctx context.Context, limit, offset int) ([]*ghostdb.Post, error) {
    rows, err := s.db.QueryContext(ctx, `SELECT id,author_id,text,media_url,media_type,language,visibility,created_at,updated_at FROM posts ORDER BY created_at DESC LIMIT ? OFFSET ?`, limit, offset)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    var out []*ghostdb.Post
    for rows.Next() {
        p := &ghostdb.Post{}
        if err := rows.Scan(&p.ID, &p.AuthorID, &p.Text, &p.MediaURL, &p.MediaType, &p.Language, &p.Visibility, &p.CreatedAt, &p.UpdatedAt); err != nil {
            return nil, err
        }
        out = append(out, p)
    }
    return out, nil
}

func (s *sqliteDB) GetTranslation(ctx context.Context, contentHash, sourceLang, targetLang string) (string, error) {
    row := s.db.QueryRowContext(ctx, `SELECT translated_text FROM translation_cache WHERE content_hash = ? AND source_language = ? AND target_language = ? ORDER BY created_at DESC LIMIT 1`, contentHash, sourceLang, targetLang)
    var t string
    err := row.Scan(&t)
    if err != nil {
        return "", nil
    }
    return t, nil
}

func (s *sqliteDB) SetTranslation(ctx context.Context, contentHash, sourceLang, targetLang, translated string) error {
    _, err := s.db.ExecContext(ctx, `INSERT INTO translation_cache(content_hash,source_language,target_language,translated_text,created_at) VALUES(?,?,?,?,?)`, contentHash, sourceLang, targetLang, translated, time.Now().Unix())
    return err
}
EOF

# Seed
cat > backend/internal/db/sqlite/seed.go <<'EOF'
package sqliteimpl

import (
    "context"
    "time"

    "github.com/Joe2781/Social-app/backend/internal/db/ghostdb"
    "github.com/Joe2781/Social-app/backend/internal/auth"
)

func SeedIfNeeded(ctx context.Context, db ghostdb.DB) error {
    if u, _ := db.GetUserByUsername(ctx, "demo1"); u != nil {
        return nil
    }

    pw, _ := auth.HashPassword("password123")
    users := []ghostdb.User{
        {Username: "demo1", DisplayName: "Demo One", Email: "demo1@example.com", PasswordHash: pw, PreferredLanguage: "en", CreatedAt: time.Now().Unix()},
        {Username: "juan", DisplayName: "Juan", Email: "juan@example.com", PasswordHash: pw, PreferredLanguage: "es", CreatedAt: time.Now().Unix()},
        {Username: "amanda", DisplayName: "Amanda", Email: "amanda@example.com", PasswordHash: pw, PreferredLanguage: "pt", CreatedAt: time.Now().Unix()},
    }
    for i := range users {
        u := users[i]
        db.CreateUser(ctx, &u)
    }

    posts := []ghostdb.Post{
        {AuthorID: "", Text: "Hello Social X 🌍", Language: "en", CreatedAt: time.Now().Unix()},
        {AuthorID: "", Text: "Hola, ¿cómo estás?", Language: "es", CreatedAt: time.Now().Add(-2 * time.Hour).Unix()},
        {AuthorID: "", Text: "Bonjour le monde", Language: "fr", CreatedAt: time.Now().Add(-3 * time.Hour).Unix()},
    }

    u1, _ := db.GetUserByUsername(ctx, "demo1")
    u2, _ := db.GetUserByUsername(ctx, "juan")
    if u1 != nil {
        posts[0].AuthorID = u1.ID
    }
    if u2 != nil {
        posts[1].AuthorID = u2.ID
    }
    for i := range posts {
        p := posts[i]
        db.CreatePost(ctx, &p)
    }
    return nil
}
EOF

# Auth helper
cat > backend/internal/auth/auth.go <<'EOF'
package auth

import (
    "errors"
    "os"
    "time"

    "golang.org/x/crypto/bcrypt"
    "github.com/golang-jwt/jwt/v5"
)

var jwtSecret = []byte(getenv("JWT_SECRET", "dev-secret"))

func getenv(k, def string) string {
    v := os.Getenv(k)
    if v == "" {
        return def
    }
    return v
}

func HashPassword(pw string) (string, error) {
    b, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
    if err != nil {
        return "", err
    }
    return string(b), nil
}

func CompareHash(hash, pw string) error {
    return bcrypt.CompareHashAndPassword([]byte(hash), []byte(pw))
}

func GenerateJWT(sub string, ttl time.Duration) (string, error) {
    claims := jwt.RegisteredClaims{
        Subject:   sub,
        ExpiresAt: jwt.NewNumericDate(time.Now().Add(ttl)),
        IssuedAt:  jwt.NewNumericDate(time.Now()),
    }
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString(jwtSecret)
}

func ParseJWT(tokenStr string) (string, error) {
    tok, err := jwt.ParseWithClaims(tokenStr, &jwt.RegisteredClaims{}, func(token *jwt.Token) (interface{}, error) {
        return jwtSecret, nil
    })
    if err != nil {
        return "", err
    }
    if claims, ok := tok.Claims.(*jwt.RegisteredClaims); ok && tok.Valid {
        return claims.Subject, nil
    }
    return "", errors.New("invalid token")
}
EOF

# Handlers
cat > backend/internal/handlers/handlers.go <<'EOF'
package handlers

import (
    "context"
    "encoding/json"
    "net/http"
    "strconv"
    "time"

    "github.com/Joe2781/Social-app/backend/internal/db/ghostdb"
    "github.com/Joe2781/Social-app/backend/internal/auth"
)

type Handler struct {
    db ghostdb.DB
}

func New(db ghostdb.DB) *Handler {
    return &Handler{db: db}
}

func (h *Handler) Routes() http.Handler {
    mux := http.NewServeMux()
    mux.HandleFunc("/users/register", h.Register)
    mux.HandleFunc("/users/login", h.Login)
    mux.HandleFunc("/feed", h.Feed)
    mux.HandleFunc("/translate", h.Translate)
    return mux
}

type registerReq struct {
    Username string `json:"username"`
    Password string `json:"password"`
    Email    string `json:"email"`
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        w.WriteHeader(http.StatusMethodNotAllowed)
        return
    }
    var req registerReq
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    pw, err := auth.HashPassword(req.Password)
    if err != nil {
        http.Error(w, "internal", http.StatusInternalServerError)
        return
    }
    u := &ghostdb.User{
        Username:     req.Username,
        DisplayName:  req.Username,
        Email:        req.Email,
        PasswordHash: pw,
        CreatedAt:    time.Now().Unix(),
    }
    if err := h.db.CreateUser(context.Background(), u); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    w.WriteHeader(http.StatusCreated)
}

type loginReq struct {
    Username string `json:"username"`
    Password string `json:"password"`
}

type loginResp struct {
    Token string `json:"token"`
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        w.WriteHeader(http.StatusMethodNotAllowed)
        return
    }
    var req loginReq
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    u, err := h.db.GetUserByUsername(context.Background(), req.Username)
    if err != nil || u == nil {
        http.Error(w, "invalid credentials", http.StatusUnauthorized)
        return
    }
    if err := auth.CompareHash(u.PasswordHash, req.Password); err != nil {
        http.Error(w, "invalid credentials", http.StatusUnauthorized)
        return
    }
    tok, err := auth.GenerateJWT(u.ID, 24*time.Hour)
    if err != nil {
        http.Error(w, "token error", http.StatusInternalServerError)
        return
    }
    json.NewEncoder(w).Encode(loginResp{Token: tok})
}

func (h *Handler) Feed(w http.ResponseWriter, r *http.Request) {
    q := r.URL.Query()
    page, _ := strconv.Atoi(q.Get("page"))
    if page < 1 {
        page = 1
    }
    limit, _ := strconv.Atoi(q.Get("limit"))
    if limit <= 0 {
        limit = 10
    }
    offset := (page - 1) * limit
    posts, err := h.db.ListFeed(context.Background(), limit, offset)
    if err != nil {
        http.Error(w, "failed", http.StatusInternalServerError)
        return
    }
    json.NewEncoder(w).Encode(posts)
}

func (h *Handler) Translate(w http.ResponseWriter, r *http.Request) {
    q := r.URL.Query()
    text := q.Get("text")
    target := q.Get("target")
    if target == "" {
        target = "en"
    }
    source := detectLanguage(text)
    hash := simpleHash(text + source + target)
    if cached, _ := h.db.GetTranslation(context.Background(), hash, source, target); cached != "" {
        json.NewEncoder(w).Encode(map[string]string{"translated": cached, "source": source})
        return
    }
    translated := fallbackTranslate(text, source, target)
    h.db.SetTranslation(context.Background(), hash, source, target, translated)
    json.NewEncoder(w).Encode(map[string]string{"translated": translated, "source": source})
}

func detectLanguage(s string) string {
    for _, r := range s {
        if r > 127 {
            return "es"
        }
    }
    return "en"
}

func simpleHash(s string) string {
    h := 0
    for _, c := range s {
        h = (h*31 + int(c)) % 1000000007
    }
    return strconv.Itoa(h)
}

func fallbackTranslate(text, source, target string) string {
    if source == target || text == "" {
        return text
    }
    return "[" + target + "] " + text
}
EOF

# Frontend skeleton
cat > frontend/package.json <<'EOF'
{
  "name": "social-x-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "lint": "echo 'lint not configured'"
  },
  "dependencies": {
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "react-router-dom": "6.14.1",
    "@tanstack/react-query": "5.9.2"
  },
  "devDependencies": {
    "typescript": "5.1.6",
    "vite": "5.0.0",
    "@vitejs/plugin-react": "4.0.0",
    "tailwindcss": "3.5.0",
    "postcss": "8.4.21",
    "autoprefixer": "10.4.14"
  }
}
EOF

cat > frontend/vite.config.ts <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:8080'
    }
  }
})
EOF

cat > frontend/index.html <<'EOF'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Social X</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

mkdir -p frontend/src
cat > frontend/src/main.tsx <<'EOF'
import React from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
EOF

cat > frontend/src/index.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

html, body, #root { height: 100%; }
body { @apply bg-gray-50 text-gray-900; }
EOF

cat > frontend/src/App.tsx <<'EOF'
import React from 'react'
import Home from './pages/Home'

export default function App() {
  return (
    <div className="min-h-screen flex flex-col">
      <div className="flex-1">
        <Home />
      </div>
    </div>
  )
}
EOF

cat > frontend/src/pages/Home.tsx <<'EOF'
import React, { useEffect, useState } from 'react'
import PostCard from '../components/PostCard'
import BottomNav from '../components/BottomNav'

type Post = {
  id: string
  author_id: string
  text: string
  media_url?: string
  language?: string
}

export default function Home(){
  const [posts, setPosts] = useState<Post[]>([])
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    load()
  }, [])

  async function load(){
    setLoading(true)
    const res = await fetch(`/api/feed?page=${page}&limit=10`)
    const data = await res.json()
    setPosts((p)=>[...p, ...data])
    setPage(page+1)
    setLoading(false)
  }

  return (
    <div className="max-w-md mx-auto p-4">
      <header className="mb-4">
        <h1 className="text-2xl font-semibold">Social X</h1>
      </header>

      <main className="space-y-4">
        {posts.map((post)=> (
          <PostCard key={post.id} post={post} />
        ))}
        {loading ? <div>Loading...</div> : <button onClick={load} className="w-full py-2 bg-white border rounded">Load more</button>}
      </main>

      <div className="fixed bottom-0 left-0 right-0 bg-white border-t">
        <BottomNav />
      </div>
    </div>
  )
}
EOF

cat > frontend/src/components/BottomNav.tsx <<'EOF'
import React from 'react'

export default function BottomNav(){
  return (
    <div className="max-w-md mx-auto flex justify-around py-2">
      <button className="flex flex-col items-center text-sm">
        <div>🏠</div>
        <div>Home</div>
      </button>
      <button className="flex flex-col items-center text-sm">
        <div>🔍</div>
        <div>Search</div>
      </button>
      <button className="flex flex-col items-center text-sm">
        <div>➕</div>
        <div>Create</div>
      </button>
      <button className="flex flex-col items-center text-sm">
        <div>💬</div>
        <div>Messages</div>
      </button>
      <button className="flex flex-col items-center text-sm">
        <div>👤</div>
        <div>Profile</div>
      </button>
    </div>
  )
}
EOF

cat > frontend/src/components/PostCard.tsx <<'EOF'
import React, {useState} from 'react'

export default function PostCard({post}:{post:any}){
  const [showTrans, setShowTrans] = useState(false)
  return (
    <div className="bg-white rounded-lg p-4 shadow-sm">
      <div className="flex items-center mb-2">
        <div className="w-10 h-10 bg-gray-200 rounded-full mr-3"></div>
        <div>
          <div className="font-semibold">User</div>
          <div className="text-xs text-gray-500">{post.created_at ? new Date(post.created_at*1000).toLocaleString() : ''}</div>
        </div>
      </div>
      <div className="mb-2">
        <div className="text-base break-words">{showTrans ? '[en] ' + post.text : post.text}</div>
      </div>
      {post.media_url && <img src={post.media_url} alt="media" className="w-full rounded" />}
      <div className="mt-2 flex items-center text-sm text-gray-600 space-x-4">
        <button>❤️ 0</button>
        <button>💬 0</button>
        <button>↗ 0</button>
        <button onClick={()=>setShowTrans(s=>!s)} className="ml-auto">{showTrans ? 'See Original' : 'See Translation'}</button>
      </div>
    </div>
  )
}
EOF

# CI
cat > .github/workflows/ci.yml <<'EOF'
name: CI

on:
  push:
    branches: [ main, init/** ]
  pull_request:
    branches: [ main ]

jobs:
  backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.20'
      - name: Run tests
        working-directory: backend
        run: |
          go test ./...

  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '18'
      - name: Install and build
        working-directory: frontend
        run: |
          npm ci
          npm run build
EOF

# Finalize commit
git add -A
git commit -m "init: project skeleton for Social X (backend + frontend)" || echo "nothing to commit"

# Push
echo "Pushing branch ${BRANCH} to origin..."
git push -u origin "${BRANCH}"

echo "Done. Branch ${BRANCH} pushed to origin. Cleanup local temp."
cd /
rm -rf "$TMPDIR"
echo "Next steps:"
echo "  - Open a PR on GitHub from branch ${BRANCH} -> main"
echo "  - To run backend locally: cd backend && go run ./cmd/server"
echo "  - To run frontend locally: cd frontend && npm install && npm run dev"
