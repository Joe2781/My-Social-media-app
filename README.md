# SOCIAL X - Production Mobile-First Social Network

A complete, modular social networking platform built with modern web technologies.

## Core Stack

**Frontend:** React + TypeScript + Vite + Tailwind CSS + React Router + TanStack Query  
**Backend:** Go REST API + WebSockets  
**Database:** GhostDB interface with PostgreSQL/SQLite adapter  
**Cache:** Redis interface with local fallback  
**Storage:** StorageProvider interface with local/S3 fallback  
**Authentication:** Secure password hashing + JWT/session + refresh tokens  
**AI Services:** Feed ranking, translation, speech-to-text, media processing  
**GPU/CUDA:** C++/CUDA/PyCUDA workers with CPU fallback  
**Infrastructure:** Docker + Terraform templates  

## Project Structure

```
social-x/
├── frontend/              # React + Vite + TypeScript
├── backend/               # Go REST API + WebSockets
├── workers/               # Media/CPU processing services
├── gpu-services/          # CUDA/GPU computing services
├── database/              # Schema, migrations, models
├── infrastructure/        # Docker, Terraform, config
├── shared/                # Shared types, constants, utilities
└── docs/                  # Architecture & API documentation
```

## Features

- ✅ Authentication (signup, login, JWT, refresh tokens)
- ✅ User profiles with follow/unfollow
- ✅ Posts with images/videos/audio
- ✅ Comments and nested replies
- ✅ Likes and custom reactions
- ✅ Reposts and bookmarks
- ✅ Realtime notifications
- ✅ Realtime chat and messaging
- ✅ Search by hashtags and trending
- ✅ Translation services (multilingual)
- ✅ AI-powered feed ranking
- ✅ Media processing pipeline
- ✅ Admin dashboard
- ✅ System health and monitoring
- ✅ Shard/node orchestration

## Mobile-First UI

- Bottom navigation: Home | Search | Create | Messages | Profile
- Responsive for Android, tablet, desktop
- Dark/light mode
- Skeletons, loading states, error handling
- Touch-friendly controls

## Development

Developed in GitHub Codespaces, accessible on Android via browser.

## Build Phases

1. ✅ Repository structure
2. Database models
3. Authentication
4. User profiles
5. Posts/feed
6. Comments/reactions/follows
7. Media uploads
8. Search/hashtags/trending
9. WebSocket notifications
10. Realtime chat
11. Translation
12. AI feed-ranking
13. Media/GPU worker architecture
14. Shard/orchestrator architecture
15. Admin dashboard
16. Security hardening
17. Tests
18. Mobile testing
19. Integration testing

---

**Status:** Phase 1 - Project structure initialization  
**Last Updated:** 2026-08-17
