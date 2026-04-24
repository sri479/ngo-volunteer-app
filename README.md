 AI-Powered Disaster Response Coordination

Turns unstructured handwritten field data into dispatched volunteers in under 60 seconds — with zero manual data entry.

Built for Google Solution Challenge 2026

🌍 Problem
Local NGOs and social groups collect critical community needs through paper surveys and field reports during disasters. This data is scattered, unprocessed, and unactionable — making it nearly impossible to coordinate the right volunteers to the right place at the right time.

💡 Solution
it is a full-stack mobile platform that connects field surveyors, AI processing, and NGO coordinators in one realtime pipeline.

Surveyors submit typed reports or photograph handwritten paper surveys
Gemini AI reads the report, extracts every distinct issue, assigns priority scores and required skills
NGO admins search in plain English, see color-coded map pins in realtime, and dispatch the nearest skilled volunteer in one tap


✨ Key Features
For Field Surveyors

Submit typed descriptions or photograph old paper surveys
GPS auto-capture or manual address entry with automatic geocoding
Single report with multiple issues → each becomes a separate trackable need

AI Pipeline

Gemini 2.5 Flash — multimodal analysis (text + vision), extracts category, priority (1–10), summary, required skills
Priority rubric — strict 5-band scoring so not everything is a 10
Jina AI — generates 768-dimensional semantic embeddings per need
Multi-issue extraction — one survey → multiple independent DB rows

NGO Dashboard

Natural language semantic search ("flooding near schools") with 400ms debounce
Category filter chips: Flood / Medical / Infrastructure / Fire / Water
OpenStreetMap with color-coded pins — Red (8–10), Orange (5–7), Green (1–4)
Realtime updates via Supabase Postgres Changes
Two-tab needs list: Unassigned and In Progress
Volunteer matching by skill overlap + GPS proximity (PostGIS ST_Distance)
One-tap dispatch with double-booking prevention


🏗️ Architecture
Flutter Mobile App
    ↓↑ Supabase Auth (JWT)

Supabase Backend (Cloud):
├── field_reports       — surveyor submissions (PostGIS geography)
├── verified_needs      — AI-extracted needs (pgvector 768-dim)
├── profiles            — volunteers + NGO admins
├── assignments         — dispatch tracking
├── DB Trigger → process-report Edge Function
│     ├── Gemini 2.5 Flash API  (text analysis + vision OCR)
│     └── Jina AI API           (embedding generation)
└── search-needs Edge Function
      └── Jina AI API (query embedding) → match_reports RPC (pgvector)

Map:       flutter_map + OpenStreetMap (no API key required)
Geocoding: Nominatim API (manual address → lat/lng coordinates)
Realtime:  Supabase Postgres Changes → Flutter StreamProvider (Riverpod)

🛠️ Tech Stack
 Frontend Flutter (Android, iOS, Web)
State Management Riverpod (StreamProvider for realtime)
Backend Supabase (Postgres, Auth, Storage, Realtime)
AI AnalysisGoogle Gemini 2.5 Flash
Embeddings Jina AI (jina-embeddings-v2-base-en)
Vector Search pgvector (cosine similarity)
Geo Queries PostGIS (ST_Distance proximity matching)
Edge Functions Deno (Supabase Edge Runtime)
Mapflutter_map + OpenStreetMap
Geocoding Nominatim API
