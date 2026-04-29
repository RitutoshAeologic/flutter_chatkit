# ChatKit AI — RAG Implementation Specification
### Version 2.0 — Final Reference for AI-Assisted Implementation

**Stack:** Flutter ≥3.19 · Dart ≥3.3 · GetX · Groq API (Chat) · Jina AI (Embeddings) · Firebase Auth + RTDB · ObjectBox 4.x  
**Scope:** Adds offline-first RAG (bundled document ingestion → embedding → retrieval → grounded chat) to an existing Flutter chat app.

---

## ⚠️ Rules for AI Tools Reading This Document

> If you are an AI coding assistant implementing from this spec, follow these rules without exception.

1. **Do not invent fields, method signatures, or class names** not defined in this document. If something is unclear, stop and ask.
2. **Do not merge or combine files** listed separately in the File Registry. Each file has exactly one responsibility.
3. **Do not change the service registration order** in Section 4. The order is load-bearing.
4. **Always use `AppConfig`** for API keys, model names, URLs, and thresholds. Never hardcode these values anywhere else.
5. **All ObjectBox queries must be closed** in a `try/finally` block. No exceptions.
6. **Do not add `GetX` state** (`Rx`, `obs`) to service classes. Only controllers hold reactive state.
7. **The `_citationsMap` in `ChatController` must be cleared** whenever `messages.clear()` is called.
8. **Do not use `Get.put()` for controllers** — only `Get.lazyPut()` with `fenix: true` via Bindings.
9. **Error types thrown by each service are specified** in Section 9. Do not throw `Exception` generically.
10. **Read Section 5 (State Machines) before writing any status-related code.**

---

## Table of Contents

1. [0. Crash Course for Fresh Developers](#0-crash-course-for-fresh-developers)
2. [1. System Purpose & Boundaries](#1-system-purpose--boundaries)
3. [2. Architecture Overview](#2-architecture-overview)
4. [3. Complete Data Flows](#3-complete-data-flows)
5. [4. File Registry](#4-file-registry)
6. [5. State Machines](#5-state-machines)
7. [6. Service Wiring — Exact Registration Order](#6-service-wiring--exact-registration-order)
8. [7. Data Models — Exact Field Definitions](#7-data-models--exact-field-definitions)
9. [8. Service Contracts — Methods, Parameters, Return Types](#8-service-contracts--methods-parameters-return-types)
10. [9. Error Handling Contract](#9-error-handling-contract)
11. [10. Optimisations — What, Why, Exactly How](#10-optimisations--what-why-exactly-how)
12. [11. Known Mistakes & Exact Fixes](#11-known-mistakes--exact-fixes)
13. [12. ObjectBox Schema](#12-objectbox-schema)
14. [13. KbManagerScreen UI Specification](#13-kbmanagerscreen-ui-specification)
15. [14. pubspec.yaml](#14-pubspecyaml)
16. [15. Setup Checklist](#15-setup-checklist)
17. [16. Chroma Migration Path](#16-chroma-migration-path)
18. [17. What to Build — Prioritised Task List](#17-what-to-build--prioritised-task-list)

---

## 0. Crash Course for Fresh Developers: How This App Works

Welcome to the project! If you are new to AI or RAG, read this section first. It explains the core concepts and exactly how this Flutter application works from end-to-end.

### What is RAG? (Retrieval-Augmented Generation)
Standard LLMs (like ChatGPT or Groq) have a fixed knowledge base from when they were trained. They don't know about *your* private company PDFs, recent banking rules, or custom documents. **RAG** solves this by injecting your documents directly into the prompt before the AI answers.

Here is the basic concept of RAG:
1. **Ingestion (Preparation):** You take a massive PDF, break it into tiny paragraphs (called "chunks"), and mathematically convert those chunks into arrays of floating-point numbers (called "embeddings" or "vectors"). You save these in a local database (ObjectBox).
2. **Retrieval (Search):** When the user asks "What is the EMI policy?", you convert their question into a mathematical vector using the *same* embedding API. You then ask the database: "Find me the top 3 chunks whose vectors are mathematically closest (cosine similarity) to the user's question vector."
3. **Generation (Answering):** You take the text from those top 3 matched chunks, paste them into a hidden "System Prompt," and send it to the LLM (Groq) along with the user's question. The LLM reads your provided text and formulates a human-friendly answer.

### Step-by-Step: What happens when the app launches?
This app is designed as an "offline-first, developer-bundled" RAG system. The user does not upload PDFs. The developer bundles PDFs in the `assets/pdfs/` folder.

1. **Booting Up (`main.dart`):** The app starts up. It connects to Firebase (for auth/chat history) and ObjectBox (our local database).
2. **Checking for New PDFs (`AssetIngestionService`):** The app scans the `assets/pdfs/` folder. It looks at the file names and checks ObjectBox to see if they have been processed yet. 
3. **Processing (If new):** If the PDF hasn't been seen before, the app runs an isolated background thread. It extracts the raw text from the PDF, slices it into 150-word chunks, and sends those chunks to the **Jina AI API** to get their vector embeddings. It then saves everything into ObjectBox.
4. **App Ready:** Once the initial indexing is done, the app enters a "Ready" state. All knowledge is safely stored on the user's phone.

### Step-by-Step: What happens when the user asks a question?
1. **User asks a question:** The user types "What is the penalty for late payment?" and hits send (`ChatController`).
2. **Checking the Network:** The app instantly checks if the user is online using `NetworkService`. If offline, it shows a red banner and stops.
3. **Retrieval (`RagRetrievalService`):** The app takes the user's question and sends it to the **Jina API** to get an embedding vector. This usually takes ~200ms. *Optimization: If the user asked this before, we use our fast L1/L2 cache and skip the API entirely.*
4. **Local Vector Search:** The app compares the question's vector against the thousands of chunk vectors sitting in ObjectBox. It grabs the top 3 best matching paragraphs.
5. **Prompt Building (`FactualHardeningService`):** The app constructs a hidden, strict prompt that looks like this:
   > *"You are a helpful assistant. You must ONLY answer using the provided facts below. If the answer is not in the facts, say 'I could not find this information.' \n\nFACT 1: A late payment incurs a 5% penalty. \nFACT 2: Payments are due on the 1st of the month."*
6. **LLM Generation (`InferenceRouter`):** The app sends this massive prompt + the user's chat history to **Groq (Llama 3.1 8b)**.
7. **UI Update:** Groq streams/returns the answer: *"The penalty for a late payment is 5%."* The app displays the answer in the chat bubble and creates a small "Citation Chip" below it showing exactly which PDF page the answer came from!

### Key Design Philosophies You Must Know
* **No LLM Hallucinations:** We specifically instruct Groq to *never* use its own general knowledge. It is only a "formatting engine" that reads the ObjectBox search results and makes them sound nice.
* **Speed is King:** Mobile networks are slow. Every architectural decision (like persistent HTTP clients, L1 memory caching, L2 disk caching, network pre-warming, and strict text truncation) is designed to keep the total response time under 2 seconds.
* **Separation of Concerns:** `EmbeddingService` only talks to Jina. `InferenceRouter` only talks to Groq. `AssetIngestionService` only handles parsing PDFs. Do not mix them.

---

## 1. System Purpose & Boundaries

### What this system does

Answers the user's questions using Groq AI, strictly grounded in documents bundled by the developer. On first launch, the app auto-ingests bundled PDFs from `assets/pdfs/`, chunks them, embeds them via Jina AI, and stores them locally. When the user sends a chat message, the system retrieves the most relevant chunks and injects them into the Groq prompt as verified context.

**Crucial constraint:** Users cannot upload their own documents. All knowledge is baked in at build time. General LLM knowledge is bypassed.

### Hard boundaries — what each store owns

| Store | Owns | Never touches |
|---|---|---|
| **Firebase RTDB** | Auth sessions, chat history, message timestamps | Documents, vectors, embeddings |
| **ObjectBox (local)** | `DocumentChunk` entities, `SourceDocument` metadata | Chat messages, user accounts |
| **SharedPreferences** | Persistent embedding cache (L2) | Chat history |

These stores are completely independent. No code reads from multiple in the same function.

### Two isolated concerns

| Concern | Entry point | External API used |
|---|---|---|
| Text chat + RAG answers | `ChatController.sendMessage()` | Groq chat completions + Jina embeddings |
| Bundled document parsing | `AssetIngestionService.forceReingest()` | Jina embeddings only |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                            USER                                 │
└───────────────────┬─────────────────────┬───────────────────────┘
                    │                     │
        ┌───────────▼──────────┐ ┌────────▼───────────┐
        │    CHAT MODULE       │ │  DOCUMENT MODULE    │
        │  ChatScreen          │ │  KbViewerScreen     │
        │  ChatController      │ │  (Read-only)        │
        └───────────┬──────────┘ └────────┬────────────┘
                    │                     │
                    │              assets/pdfs/ bundled files
                    │                     │
                    │            AssetIngestionService
                    │              │ compute() isolate
                    │              │ → extract + chunk
                    │              │ EmbeddingService (Jina AI)
                    │              │ → embedBatch() batch=96
                    │              │ ObjectBox.putMany()
                    │              │ → invalidateCache()
                    ▼              │
             InferenceRouter ◄─────┘ (shared EmbeddingService)
                    │
          ┌─────────┴──────────┐
          │                    │
          ▼                    ▼
   RagRetrievalService   FactualHardeningService
   (embed + search)      (prompt builder, no I/O)
          │
          ▼
       Groq AI
   (llama-3.1-8b-instant)
          │
          ▼
   RouterResponse
   (content + citations)
          │
          ▼
   ChatController
   (update UI + Firebase)
```

---

## 3. Complete Data Flows

### Flow A — Text chat, documents exist (RAG active)

```
Step  Who                         What
────  ───────────────────────────  ──────────────────────────────────────────────
 1    User                         Types message, taps send
 2    ChatController               Trims text, checks not empty + not sending
 3    ChatController               Creates user ChatMessage (uuid, content, role=user, now)
 4    ChatController               Appends to messages list (UI updates immediately)
 5    ChatController               Saves user message to Firebase RTDB
 6    ChatController               Appends loading-placeholder ChatMessage (isLoading=true)
 7    ChatController               Calls InferenceRouter.query(text, history: last N chars-budgeted)
 8    InferenceRouter              Checks _isRagCandidate(text) — skip if <3 words
 9    InferenceRouter              Calls RagRetrievalService.retrieve(text)
10    RagRetrievalService          Checks ready-document count — if 0, returns empty immediately
11    RagRetrievalService          Checks _chunkCache — loads from ObjectBox only if null
12    RagRetrievalService          Calls EmbeddingService.embed(text)        [~200ms, Jina API]
13    EmbeddingService             Checks 3-layer cache (L1 Memory, L2 Disk) — returns if hit
14    RagRetrievalService          Dot-product scores all cached chunks       [~2ms CPU]
15    RagRetrievalService          Filters score >= 0.35, dedup by sourceLabel, take top-3
16    RagRetrievalService          Returns RagRetrievalResult(contextBlock, citations, hasContext)
17    InferenceRouter              Calls FactualHardeningService.buildSystemPrompt(result)
18    FactualHardeningService      Returns system prompt string (with VERIFIED FACTS block if hasContext)
19    InferenceRouter              Builds messages: [system, ...budgetedHistory, user]
20    InferenceRouter              POST to Groq chat completions              [~800ms]
21    InferenceRouter              Returns RouterResponse(content, citations, usedRag=true)
22    ChatController               Replaces loading-placeholder with real ChatMessage
23    ChatController               Stores citations: _citationsMap[messageId] = citations
24    ChatController               Saves assistant ChatMessage to Firebase RTDB
25    ChatController               Calls refreshSessions() for sidebar title update
26    ChatScreen                   Rebuilds: markdown bubble + collapsible citations row
```

**Total added latency from RAG:** Step 12 (~200ms, skipped on cache hit) + Step 14 (~2ms). Everything else is free.

---

### Flow B — Text chat, no documents uploaded

Steps 1–7 identical.  
Step 8: `_isRagCandidate` — passes if ≥3 words.  
Step 10: `SourceDocument.count(status: ready) == 0` → returns `RagRetrievalResult.empty()` **immediately**.  
Steps 17–26: identical. System prompt is plain persona. No citations. No UI citations row shown.

**Zero RAG overhead** — the Jina embedding API is never called.

---

### Flow C — Image generation

```
Step  Who                What
────  ────────────────   ──────────────────────────────────────────────────────
 1    User               Types "/image a sunset over mountains"
 2    ChatController     Detects trimmedText.startsWith('/image ')
 3    ChatController     Extracts prompt = text after '/image '
 4    ChatController     Builds URL: https://image.pollinations.ai/prompt/{encoded}
                         ?width=1024&height=1024&nologo=true&seed={epoch_ms}
 5    ChatController     Creates ChatMessage(type: image, imageUrl: url)
 6    ChatController     Saves to Firebase RTDB
 7    ChatScreen         Renders ImageMessageBubble (no citations row)
```

InferenceRouter, RagRetrievalService, EmbeddingService — **none are called**.

---

### Flow D — Bundled Asset Ingestion

```
Step  Who                          What
────  ───────────────────────────   ──────────────────────────────────────────────
 1    App Launch                    AssetIngestionService initialized
 2    AssetIngestionService         Reads AssetManifest to find all PDFs in assets/pdfs/
 3    AssetIngestionService         Compares with ObjectBox SourceDocuments
 4    AssetIngestionService         If matches, skips. If new/changed, deletes old and auto-starts ingestion
 5    AssetIngestionService         Extracts text using syncfusion_flutter_pdf
 6    AssetIngestionService         Chunks text and strips UI markers
 7    AssetIngestionService         Calls EmbeddingService.embedBatch(chunks) via Jina
 8    AssetIngestionService         Saves to ObjectBox (SourceDocument + DocumentChunks)
 9    AssetIngestionService         Calls _retrieval.invalidateCache()
10    KbViewerScreen                Updates UI from _IndexingState to document list
```

---

### Flow E — Document deletion

**REMOVED**: The app no longer supports deleting documents from the UI. Documents are strictly managed by the developer via the `assets/pdfs/` directory. Changing the bundled files and rebuilding the app automatically triggers a clean re-ingestion.

---

## 4. File Registry

**Legend:** ✅ Already exists in codebase | 🔨 Must be created | ♻️ Existing file must be modified

### Core Layer — `lib/core/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| 🔨 | `app_config.dart` | Single source of truth: API key (via `--dart-define`), model names, URLs, all tunable thresholds. Zero logic, only constants. | — | Every service that calls an API |
| ✅♻️ | `embedding_service.dart` | Jina embedding API. `embed(text)` for single queries. `embedBatch(texts)` for ingestion. L2-normalises every vector. 3-Layer Cache: L1 memory LRU, L2 SharedPreferences disk cache, L3 persistent `http.Client`. Includes `warmUp()` method. | `AppConfig`, `http`, `shared_preferences` | `AssetIngestionService`, `RagRetrievalService` |

### Data Layer — `lib/data/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| ✅♻️ | `document_chunk.dart` | ObjectBox entity. One text chunk + its 768-dim embedding (CSV). Cached embedding deserialization. | `objectbox` | `AssetIngestionService`, `RagRetrievalService` |
| ✅ | `source_document.dart` | ObjectBox entity. Document metadata + ingestion lifecycle status. | `objectbox` | `AssetIngestionService`, `KbViewerScreen` |
| 🔨 | `object_box_store.dart` | Thin wrapper: holds `Store`, exposes `box<T>()`. Opened once in `main()`, injected everywhere. | `objectbox.g.dart` (generated) | All domain services |
| 🔨 | `rag_models.dart` | Value objects only: `RagRetrievalResult`, `RagCitation`, `RouterResponse`, `IngestionEvent` sealed class + subclasses. No logic. | — | `RagRetrievalService`, `FactualHardeningService`, `InferenceRouter`, `KbManagerController` |
| ✅ | `chat_message.dart` | `ChatMessage`, `ChatSession`, `MessageRole` enum, `MessageType` enum. **Do not modify.** | — | `ChatController`, `InferenceRouter` |

### Domain Layer — `lib/domain/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| ✅♻️ | `asset_ingestion_service.dart` | Auto-ingestion pipeline. Reads `assets/pdfs/`, extracts, chunks, embeds via `embedBatch()`, and stores in ObjectBox. Handles network failures gracefully. | `EmbeddingService`, `ObjectBoxStore`, `RagRetrievalService`, `syncfusion_flutter_pdf` | `main.dart` |
| ✅♻️ | `rag_retrieval_service.dart` | Vector search. Embeds query → uses `_chunkCache` (lazy-loaded, invalidated on write) → dot-product cosine → filter → dedup → top-3. Exposes `invalidateCache()`. | `EmbeddingService`, `ObjectBoxStore` | `InferenceRouter`, `AssetIngestionService` (invalidation) |
| ✅♻️ | `services/factual_hardening_service.dart` | Prompt builder only. No I/O, no network. `buildSystemPrompt(RagRetrievalResult)` → `String`. Imports `rag_models.dart` only. | `rag_models.dart` | `InferenceRouter` |
| ✅♻️ | `services/inference_router.dart` | Orchestrates: `_isRagCandidate()` check → retrieval → hardening → Grok API call → `RouterResponse`. Also `generateTitle()`. Single owner of Grok chat URL + model. | `RagRetrievalService`, `FactualHardeningService`, `AppConfig`, `http` | `ChatController` |

### Presentation Layer — `lib/presentation/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| ✅♻️ | `chat_controller.dart` | GetX controller. Calls `InferenceRouter.query()`. Holds `_citationsMap`. Updates UI state. Integrates `NetworkService` for connectivity monitoring. | `InferenceRouter`, `NetworkService` | `ChatScreen` |
| ✅♻️ | `chat_screen.dart` | Adds: library icon badge, network banners (offline & slow response), auto-scrolling, keyboard dismiss. | `ChatController`, `NetworkService` | App router |
| ✅♻️ | `kb_viewer_screen.dart` | Read-only document list showing bundled assets. Shows `_IndexingState` (spinner) while ingesting. | `AssetIngestionService` | Drawer + App router |

### Wiring — `lib/`

| Status | File | Responsibility |
|---|---|---|
| ✅♻️ | `main.dart` | `async main()`. Firebase init → ObjectBox `openStore()` → service registration in exact order from Section 6. |
| 🔨 | `app_binding.dart` | Permanent service registration (services only). |
| 🔨 | `kb_manager_binding.dart` | `Get.lazyPut<KbManagerController>(fenix: true)`. Used by router only. |

---

## 5. State Machines

### IngestionStatus (SourceDocument.status)

```
                  ┌─────────────────────────────┐
                  │                             │
            ┌─────▼──────┐              ┌───────▼──────┐
  start ───► │  queued    │──────────►  │  processing  │
            └────────────┘  ingestDoc   └───────┬───────┘
                                                │
                                   ┌────────────┴──────────┐
                                   │                       │
                             ┌─────▼──────┐        ┌──────▼───────┐
                             │   ready    │        │    failed    │
                             └─────┬──────┘        └──────────────┘
                                   │
                           user deletes doc
                                   │
                               (removed)
```

| Status | UI display | Can user delete? | Included in RAG search? |
|---|---|---|---|
| `queued` | Grey — "Queued" | Yes | No |
| `processing` | Spinner — "Processing…" | No (button disabled) | No |
| `ready` | Green — chunk count + size | Yes | **Yes** |
| `failed` | Red — "Failed — tap to retry" | Yes | No |

**Rule:** RAG search (`RagRetrievalService`) must filter chunks only from documents with `status = 'ready'`. See `_chunkCache` loading in Section 10.

---

### Citation visibility (ChatController._citationsMap)

```
Session selected / new chat started
        │
        ▼ messages.clear() + _citationsMap.clear()
        │
User sends message
        │
        ▼ InferenceRouter.query() returns RouterResponse
        │
  usedRag == true?
   ├── YES → _citationsMap[reply.id] = citations
   └── NO  → nothing added (citations row not shown)
        │
Session deleted / clearAllHistory()
        │
        ▼ messages.clear() + _citationsMap.clear()
```

---

## 6. Service Wiring — Exact Registration Order

Copy this exactly into `main.dart`. The order is load-bearing — each service uses the one registered before it.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. ObjectBox ─────────────────────────────────────────────
  final store = await openStore();
  final obx = ObjectBoxStore(store);
  Get.put<ObjectBoxStore>(obx, permanent: true);

  // ── 2. NetworkService (connectivity monitoring) ──────────────
  Get.put<NetworkService>(NetworkService(), permanent: true);

  // ── 3. EmbeddingService (Jina — ingestion only) ──────────────
  final embedder = EmbeddingService();
  await embedder.init(); // loads disk cache
  Get.put<EmbeddingService>(embedder, permanent: true);
  unawaited(embedder.warmUp()); // pre-warm TCP/TLS connection

  // ── 4. RagRetrievalService ───────────────────────────────────
  final retrieval = RagRetrievalService(obx: obx, embedder: embedder);
  Get.put<RagRetrievalService>(retrieval, permanent: true);

  // ── 5. AssetIngestionService ─────────────────────────────────
  final assetIngestion = AssetIngestionService(
    obx: obx,
    embedder: embedder,
    retrieval: retrieval,
  );
  Get.put<AssetIngestionService>(assetIngestion, permanent: true);

  // ── 6. Decide initial route ──────────────────────────────────
  final initialRoute = assetIngestion.isAlreadyIngested
      ? AppRoutes.chat
      : AppRoutes.ingestion;

  runApp(ChatKitApp(initialRoute: initialRoute));
}
```

**Why controllers must be lazy:** Controllers hold `Rx` state that drives UI. Registering them before `runApp()` means they exist with no widget tree, making `Get.context` null and causing crash on any dialog or navigation call.

---

## 7. Data Models — Exact Field Definitions

### ChatMessage (existing — do not change)

```dart
enum MessageRole { user, assistant }
enum MessageType { text, image }

class ChatMessage {
  final String id;          // UUID v4
  final String content;     // message text or "Generated image for: …"
  final MessageRole role;
  final DateTime createdAt;
  final bool isLoading;     // true only for placeholder bubble
  final MessageType type;   // defaults to text
  final String? imageUrl;   // non-null only when type == image
}
```

### RagRetrievalResult (in `rag_models.dart`)

```dart
class RagRetrievalResult {
  final String contextBlock;       // formatted text injected into system prompt
  final List<RagCitation> citations;
  final bool hasContext;           // false → plain persona prompt used

  const RagRetrievalResult({
    required this.contextBlock,
    required this.citations,
    required this.hasContext,
  });

  const RagRetrievalResult.empty()
      : contextBlock = '',
        citations = const [],
        hasContext = false;
}
```

### RagCitation (in `rag_models.dart`)

```dart
class RagCitation {
  final int index;           // [1], [2], [3] — matches in-prompt numbering
  final String sourceLabel;  // "report.pdf p.3" — shown in UI chip
  final double score;        // cosine similarity 0.0–1.0
  final String preview;      // first 90 chars of chunk text
}
```

### RouterResponse (in `rag_models.dart`)

```dart
class RouterResponse {
  final String content;               // assistant reply text
  final List<RagCitation> citations;  // empty if RAG not used
  final bool usedRag;
}
```

### IngestionEvent sealed class (in `rag_models.dart`)

```dart
sealed class IngestionEvent {}

class IngestionProgress extends IngestionEvent {
  final String message;   // human-readable status
  final double fraction;  // 0.0 – 1.0 for progress bar
}

class IngestionComplete extends IngestionEvent {
  final SourceDocument document;
}

class IngestionError extends IngestionEvent {
  final String message;   // shown in snackbar
}
```

---

## 8. Service Contracts — Methods, Parameters, Return Types

### AppConfig

```dart
class AppConfig {
  static const String jinaApiKey =
      String.fromEnvironment('JINA_API_KEY', defaultValue: '');
  static const String groqApiKey =
      String.fromEnvironment('GROQ_API_KEY', defaultValue: '');

  // Endpoints
  static const String chatUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String embedUrl =
      'https://api.jina.ai/v1/embeddings';

  // Model identifiers
  static const String chatModel   = 'llama-3.1-8b-instant';
  static const String embedModel  = 'jina-embeddings-v2-base-en';

  // RAG tuning constants — change here, affects entire system
  static const double similarityThreshold  = 0.25;
  static const int    topKChunks           = 3;
  static const int    chunkContextMaxChars = 600;
  static const int    embeddingDimensions  = 768;
  static const int    maxFileSizeBytes     = 50 * 1024 * 1024; // 50 MB

  // Chunking constants
  static const int chunkWordWindow = 150;
  static const int chunkWordOverlap = 30;
  static const int chunkMaxChars   = 800;
  static const int chunkMinChars   = 30;

  // Embedding cache
  static const int embedCacheMaxSize = 200;

  // Limits
  static const int embedBatchSize = 96;
  static const int embedMaxRetries = 3;
}
```

> **Why `String.fromEnvironment`?**  
> We **never** hardcode API keys directly into the source code. Doing so would leak your keys if you push the code to a public Git repository. 
> `String.fromEnvironment` reads values passed from the command line *at compile time*. 
> 
> To run the app during development, you must pass these flags:
> `flutter run --dart-define=JINA_API_KEY=jina_... --dart-define=GROQ_API_KEY=gsk_...`
> 
> To build an APK for production:
> `flutter build apk --dart-define=JINA_API_KEY=... --dart-define=GROQ_API_KEY=...`

### EmbeddingService

```dart
class EmbeddingService {
  // Embeds a single query. Uses LRU cache — same text = no API call.
  Future<List<double>> embed(String text);

  // Embeds many texts. Handles batching at 96/call internally.
  // Returns vectors in the SAME ORDER as input (sorted by API 'index' field).
  // All vectors are L2-normalised.
  Future<List<List<double>>> embedBatch(List<String> texts);
}
```

### RagRetrievalService

```dart
class RagRetrievalService {
  // Main retrieval. Returns empty result if no ready documents exist,
  // or if query scores below threshold on all chunks.
  Future<RagRetrievalResult> retrieve(String query);

  // Called by DocumentIngestionService after any write.
  // Forces _chunkCache to reload on next retrieve() call.
  void invalidateCache();
}
```

### FactualHardeningService

```dart
class FactualHardeningService {
  const FactualHardeningService();

  // Returns RAG-augmented system prompt if result.hasContext,
  // otherwise returns plain persona prompt.
  // No I/O. Pure string transformation.
  String buildSystemPrompt(RagRetrievalResult result);
}
```

### InferenceRouter

```dart
class InferenceRouter {
  // Main query entry point.
  // history: already budgeted to AppConfig.historyMaxChars by caller (ChatController).
  Future<RouterResponse> query(String text, {List<ChatMessage> history});

  // Fire-and-forget title generation. Returns null on failure.
  Future<String?> generateTitle(String firstUserMessage);
}
```

### AssetIngestionService

```dart
class AssetIngestionService {
  // Checks AssetManifest, compares to ObjectBox, handles updates/deletions.
  // Then auto-starts ingestion if needed.
  // Yields IngestionEvent stream for the UI.
  Stream<IngestionEvent> forceReingest();

  // Returns all SourceDocuments in the system.
  List<SourceDocument> listReadyDocuments();

  // Sync state.
  bool get isAlreadyIngested;
}
```

---

## 9. Error Handling Contract

### Exception types

```dart
// lib/core/app_exceptions.dart

// Thrown by EmbeddingService when API call fails after retries
class EmbeddingException implements Exception {
  final String message;
  final int? statusCode;
  const EmbeddingException(this.message, {this.statusCode});
}

// Thrown by InferenceRouter when Grok API call fails
class RouterException implements Exception {
  final String message;
  final int? statusCode;
  const RouterException(this.message, {this.statusCode});
}
```

### Who catches what

| Thrown by | Caught by | Action |
|---|---|---|
| `EmbeddingException` (in retrieval) | `InferenceRouter.query()` | Log, return `RagRetrievalResult.empty()`, continue to Grok without RAG context |
| `EmbeddingException` (in ingestion) | `DocumentIngestionService` pipeline | `yield IngestionError(message)`, set `SourceDocument.status = failed` |
| `RouterException` | `ChatController.sendMessage()` | Remove loading placeholder, `Get.snackbar('Error', message)` |
| `IngestionError` (event) | `KbManagerController` stream listener | Set `isIngesting=false`, `Get.snackbar('Upload Failed', message)` |
| Any unhandled exception | `ChatController.sendMessage()` catch block | Remove loading placeholder, generic snackbar |

### Key rule: RAG failures must never crash chat

```dart
// InferenceRouter.query() — required pattern
RagRetrievalResult ragResult = const RagRetrievalResult.empty();
try {
  if (_isRagCandidate(text)) {
    ragResult = await _retrieval.retrieve(text);
  }
} on EmbeddingException catch (e) {
  debugPrint('RAG retrieval failed, degrading gracefully: $e');
  // ragResult stays empty — chat continues without context
}
```

---

## 10. Optimisations — What, Why, Exactly How

### O1 — Chunk cache with explicit invalidation

**Problem:** `ObjectBox.getAll()` on every message loads ~15 MB of chunk data into memory each time.  
**Fix:** Cache in `RagRetrievalService`. Invalidate only on document write/delete.

```dart
// RagRetrievalService
List<DocumentChunk>? _chunkCache;

void invalidateCache() => _chunkCache = null;

Future<RagRetrievalResult> retrieve(String query) async {
  // Load only chunks from READY documents
  _chunkCache ??= _obx
      .box<DocumentChunk>()
      .getAll()
      .where((c) {
        // Only use chunks from documents that are fully ready
        // (avoids serving partial chunks from failed ingestions)
        return true; // documentId index used — filtering done at source
      })
      .toList();
  // ...
}
```

**Who calls `invalidateCache()`:** `DocumentIngestionService.deleteDocument()` and at the end of `DocumentIngestionService`'s ingestion pipeline (after `putMany`). Nowhere else.

---

### O2 — 3-Layer Embedding Cache

**Problem:** Same query asked twice hits Jina twice (~200ms each). App restart loses cache.  
**Fix:** L1 in-memory LRU, L2 SharedPreferences disk cache.

```dart
// EmbeddingService
// L1: Memory
final _memCache = <String, List<double>>{};
// L2: Disk
SharedPreferences? _prefs;

Future<List<double>> embed(String text) async {
  if (_memCache.containsKey(text)) {
    final v = _memCache.remove(text)!;
    _memCache[text] = v; // Move to front
    return v;
  }
  final result = (await _callApi([text])).first;
  _memCache[text] = result;
  _saveDiskCache();
  return result;
}
```

---

### O2b — Persistent HTTP Client

**Problem:** Mobile networks pay a huge penalty (3-5s) for DNS + TCP + TLS handshake on the first request of a session.  
**Fix:** Use a single persistent `http.Client` for Jina. Cuts subsequent requests from ~3s to ~200ms.

```dart
final http.Client _httpClient = http.Client();
// Used for all _callApi POST requests.
```

---

### O2c — Network Pre-warming

**Problem:** Even with persistent client, the *first* query still pays the TCP tax.  
**Fix:** Fire an `unawaited(embedder.warmUp())` call in `main.dart` the moment the app boots.

```dart
Future<void> warmUp() async {
  await _callApi(['ok']); // Establishes TCP/TLS silently
}
```

---

### O3 — Early exit when no documents are ready

**Problem:** Even with chunk cache, embedding the query costs ~200ms if no documents exist.  
**Fix:** Count ready documents before calling embed.

```dart
// RagRetrievalService.retrieve() — first lines
Future<RagRetrievalResult> retrieve(String query) async {
  // Free count — no data loaded
  final readyCount = _obx
      .box<SourceDocument>()
      .query(SourceDocument_.status.equals(IngestionStatus.ready.name))
      .build()
      .count();
  if (readyCount == 0) return const RagRetrievalResult.empty();
  // ...continue with embed + search
}
```

---

### O4 — Skip RAG for trivial messages

**Problem:** "ok", "thanks", "tell me more" waste an embed call.  
**Fix:** Single compound guard in `InferenceRouter`.

```dart
// InferenceRouter — exact implementation
bool _isRagCandidate(String query) {
  final trimmed = query.trim();
  // Must pass BOTH conditions — not OR
  return trimmed.split(' ').length >= 3 && trimmed.length >= 12;
}
```

**Why both conditions:** "how?" is 1 word (fails word check). "yes please help" is 3 words 15 chars (passes both). Short messages that somehow hit both thresholds are still worth checking.

---

### O5 — History token budget (character-based)

**Problem:** `history.take(10)` can be up to 10,240 tokens if each message is 1024 tokens.  
**Fix:** Budget by character count, newest messages first.

```dart
// ChatController — call this before passing history to InferenceRouter
List<ChatMessage> _budgetedHistory() {
  final result = <ChatMessage>[];
  int chars = 0;
  for (final msg in messages.reversed.where((m) => !m.isLoading)) {
    if (chars + msg.content.length > AppConfig.historyMaxChars) break;
    result.insert(0, msg); // maintain chronological order
    chars += msg.content.length;
  }
  return result;
}
```

---

### O6 — Single embedBatch call per ingestion

**Problem:** Inner loop calling `embedBatch` with 16 texts at a time doubles/triples API calls since `EmbeddingService` already batches at 96.  
**Fix:** Pass all chunk texts at once.

```dart
// DocumentIngestionService — CORRECT
final allTexts = rawChunks.map((c) => c.text).toList();
final allEmbeddings = await _embedder.embedBatch(allTexts);
// EmbeddingService handles 96-per-call splitting internally
```

---

### O7 — Single putMany transaction

ObjectBox wraps `putMany()` in a single write transaction. Do not loop with individual `put()` calls.

```dart
// ✅ CORRECT — one transaction, fast
_obx.box<DocumentChunk>().putMany(chunks);

// ❌ WRONG — N transactions, N× slower
for (final chunk in chunks) {
  _obx.box<DocumentChunk>().put(chunk);
}
```

---

### O8 — File size guard before reading bytes

**Problem:** `withData: true` loads the entire file into RAM. A 100 MB PDF will OOM crash.

```dart
// DocumentIngestionService — check size before reading bytes
final result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['pdf', 'txt'],
  withData: true,
  allowMultiple: false,
);
final file = result?.files.first;
if (file == null) return; // user cancelled

if ((file.size) > AppConfig.maxFileSizeBytes) {
  yield IngestionError(
    'File too large (${(file.size / 1048576).toStringAsFixed(1)} MB). '
    'Maximum is ${AppConfig.maxFileSizeBytes ~/ 1048576} MB.',
  );
  return;
}
```

---

### O9 — Embedding deserialization cache per chunk

**Problem:** `embeddingCsv.split(',').map(double.parse)` on a 768-value string is called once per chunk per query. At 3000 chunks = 2.3M parse calls per message.  
**Fix:** Cache the deserialized list on the entity object.

```dart
// DocumentChunk
List<double>? _cachedEmbedding;

List<double> get embedding {
  _cachedEmbedding ??= embeddingCsv.isEmpty
      ? const []
      : embeddingCsv.split(',').map(double.parse).toList();
  return _cachedEmbedding!;
}
```

This works because `_chunkCache` in `RagRetrievalService` holds the same object references. The cache is populated on first access and reused on every subsequent query until `invalidateCache()` is called.

---

## 11. Known Mistakes & Exact Fixes

### M1 — ObjectBox queries not closed in try/finally

**Affects:** `DocumentIngestionService.deleteDocument()`

```dart
// ❌ WRONG — query leaks if findIds() throws
final q = box.query(...).build();
box.removeMany(q.findIds());
q.close();

// ✅ CORRECT
final q = box.query(...).build();
try {
  box.removeMany(q.findIds());
} finally {
  q.close(); // runs even if removeMany throws
}
```

Apply this pattern to every ObjectBox query in every file.

---

### M2 — API key in multiple files

**Affects:** `rag/rag_bindings.dart`, `rag/chat_service_rag.dart`

Remove all `static const String _groqApiKey = 'gsk_...'` declarations from service files. Use `AppConfig.groqApiKey` everywhere.

---

### M3 — ChatService singleton ignores late RAG injection

**Affects:** `rag/chat_service_rag.dart`

```dart
// ❌ WRONG — first caller wins; late RAG injection silently ignored
static ChatService? _instance;
factory ChatService({RagRetrievalService? ragRetrieval}) {
  _instance ??= ChatService._internal(ragRetrieval: ragRetrieval);
  return _instance!;
}
```

Remove `ChatService` entirely. `ChatController` calls `InferenceRouter` directly. `InferenceRouter` is registered as a permanent singleton with all deps wired at startup.

---

### M4 — FactualHardeningService imports service class for value object

**Affects:** `domain/services/factual_hardening_service.dart`

```dart
// ❌ WRONG — couples pure prompt-builder to domain service
import '../rag_retrieval_service.dart';

// ✅ CORRECT — import value objects only
import '../../data/rag_models.dart';
```

---

### M5 — `_citationsMap` never cleared on session switch

**Affects:** `rag/chat_controller_rag.dart`

Every call to `messages.clear()` must also clear `_citationsMap`:

```dart
// ChatController — extract as private method
void _clearMessages() {
  messages.clear();
  _citationsMap.clear(); // ← always together
}

// Replace all messages.clear() calls with _clearMessages()
// This includes: startNewChat(), selectSession(), clearAllHistory()
```

---

### M6 — `unawaited()` used without explicit import

**Affects:** `rag/chat_controller_rag.dart`

```dart
// Add at top of file
import 'dart:async' show unawaited;

// All fire-and-forget calls must have error handlers
unawaited(
  _service.updateSessionTitle(uid, sessionId, text).catchError(
    (Object e) => debugPrint('Title update failed: $e'),
  ),
);
```

---

### M7 — KbManagerController registered inside build() method

**Affects:** Any placement of `Get.put<KbManagerController>()` in widget code.

```dart
// ✅ CORRECT — in KbManagerBinding
class KbManagerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<KbManagerController>(
      () => KbManagerController(
        ingestion: Get.find<DocumentIngestionService>(),
      ),
      fenix: true, // auto-recreates after disposal, no double-registration
    );
  }
}
```

---

## 12. ObjectBox Schema

Run `dart run build_runner build --delete-conflicting-outputs` after any entity change. Commit both `objectbox.g.dart` and `objectbox-model.json`. **Never delete `objectbox-model.json`** — it tracks schema versions and is required for migrations.

### DocumentChunk entity

```dart
@Entity()
class DocumentChunk {
  @Id()
  int id = 0;

  @Index()                  // enables fast filter by documentId
  String documentId = '';   // SHA-256 prefix of parent SourceDocument

  String sourceLabel = '';  // "file.pdf p.3" — shown in citation chip
  String text = '';         // chunk text ≤800 chars — sent to Grok as context
  int startOffset = 0;      // word index in original document
  int chunkIndex = 0;       // sequential position within document
  String embeddingCsv = ''; // 768 floats joined by ','
  String createdAt = '';    // ISO-8601

  // Transient — not persisted by ObjectBox, computed on demand
  @Transient()
  List<double>? _cachedEmbedding;

  DocumentChunk();

  List<double> get embedding {
    _cachedEmbedding ??= embeddingCsv.isEmpty
        ? const []
        : embeddingCsv.split(',').map(double.parse).toList();
    return _cachedEmbedding!;
  }
}
```

### SourceDocument entity

```dart
@Entity()
class SourceDocument {
  @Id()
  int id = 0;

  @Unique()                  // prevents duplicate ingestion
  String documentId = '';    // SHA-256(bytes).substring(0, 16)

  String name = '';          // original filename
  String fileType = '';      // 'pdf' or 'txt'
  int totalChunks = 0;       // set after ingestion completes
  int fileSizeBytes = 0;
  String status = 'queued';  // see State Machine in Section 5
  String createdAt = '';
  String updatedAt = '';
}
```

### Relation

`DocumentChunk.documentId` matches `SourceDocument.documentId`. No ObjectBox `@Relation()` annotation needed — manual join via `@Index()` query. This keeps deletion simple: query chunks by documentId, removeMany.

---

## 13. KbViewerScreen UI Specification

### Screen layout

```
AppBar
  title: "Knowledge Base"

Body:
  if (_docs.isNotEmpty):
    InfoBanner(count, totalChunks)  ← "2 documents bundled"

  if (_docs.isEmpty):
    _IndexingState(spinner, title, subtitle)  ← "Setting up your knowledge base…"

  else:
    ListView of DocumentTile widgets
```

### DocumentTile widget

```
Card
  leading: PDF Icon (red/blue)
  title: document.name (ellipsis overflow)
  subtitle: "${totalChunks} chunks · ${fileSizeKb} KB"
  trailing: Badge ("Built-in")
```

### Delete confirmation dialog

**REMOVED:** Users cannot delete bundled documents.

### Ingestion progress banner

**REMOVED:** Handled by full-page `_IndexingState` since ingestion only blocks on the very first launch.

### Navigation

Access from chat screen drawer: `ListTile("Knowledge Base", badge: doc count)` → `Get.to(KbManagerScreen, binding: KbManagerBinding())`.

Access from chat screen AppBar: library icon with badge showing document count.

---

## 14. pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter

  # ── Already in project ──────────────────────────────────────
  get: ^4.6.6
  firebase_core: ^3.0.0
  firebase_auth: ^5.0.0
  firebase_database: ^11.0.0
  http: ^1.2.0
  flutter_markdown: ^0.7.3
  flutter_animate: ^4.5.0
  uuid: ^4.4.0

  # ── RAG additions ────────────────────────────────────────────
  objectbox: ^4.0.1
  objectbox_flutter_libs: ^4.0.1   # native C library for Android/iOS
  file_picker: ^8.1.2
  syncfusion_flutter_pdf: ^26.2.14  # text-based PDFs only
  crypto: ^3.0.3                    # SHA-256 deduplication
  intl: ^0.19.0                     # date formatting in KbManagerScreen

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.11
  objectbox_generator: ^4.0.1
```

**Minimum Flutter version:** 3.19.0 (required by ObjectBox 4.x / Dart 3.3)  
**Minimum Android SDK:** 21  
**Minimum iOS:** 15.0

---

## 15. Setup Checklist

Complete every step in order. Each one is a prerequisite for the next.

```
□ Step 1 — Add dependencies
  flutter pub get

□ Step 2 — Generate ObjectBox binding
  dart run build_runner build --delete-conflicting-outputs
  Verify these files were created:
    lib/objectbox.g.dart
    lib/objectbox-model.json
  Commit BOTH files to version control.
  NEVER add objectbox-model.json to .gitignore.

□ Step 3 — Android: NDK filter
  In android/app/build.gradle, inside android { defaultConfig { } }:
    ndk {
        abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86_64'
    }

□ Step 4 — iOS: no extra steps
  ObjectBox ships as XCFramework. flutter pub get handles it.

□ Step 5 — API key (never commit to git)
  Development:
    flutter run --dart-define=GROQ_API_KEY=gsk_your_key_here
  CI / Production build:
    flutter build apk --dart-define=GROQ_API_KEY=gsk_your_key_here
  Add to .gitignore: *.env, .dart_defines

□ Step 6 — Syncfusion license (production only)
  In main(), before runApp():
    SfGlobalLocalizations.load(...);  // or SfLicenseProvider.registerLicense(key)
  Development works without a license key.

□ Step 7 — Smoke test ObjectBox
  In main(), after openStore():
    debugPrint('OBX ready — '
      'chunks: ${store.box<DocumentChunk>().count()}, '
      'docs: ${store.box<SourceDocument>().count()}');
  Expected output on first run: "OBX ready — chunks: 0, docs: 0"
```

---

## 16. Chroma Migration Path

When migrating from ObjectBox in-memory search to Chroma (or any vector DB), exactly two domain files change. Nothing in the presentation layer, chat flow, or Firebase integration changes.

### What changes

**`RagRetrievalService.retrieve()`** — replace local search with HTTP:

```dart
// Replace this block:
_chunkCache ??= _obx.box<DocumentChunk>().getAll();
final scored = _chunkCache!.map((chunk) { ... dotProduct ... });

// With this:
final response = await http.post(
  Uri.parse('${AppConfig.chromaUrl}/api/v1/collections/${AppConfig.chromaCollection}/query'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'query_embeddings': [queryVec],
    'n_results': AppConfig.topKChunks,
    'include': ['documents', 'metadatas', 'distances'],
  }),
);
// Parse response.body → build RagRetrievalResult
```

**`DocumentIngestionService` ingestion pipeline** — replace `ObjectBox.putMany()` with Chroma upsert:

```dart
// Chroma upsert payload (correct fields):
await http.post(
  Uri.parse('${AppConfig.chromaUrl}/api/v1/collections/${AppConfig.chromaCollection}/upsert'),
  body: jsonEncode({
    'ids': chunks.map((c) => '${c.documentId}_${c.chunkIndex}').toList(),
    'embeddings': allEmbeddings,
    'documents': chunks.map((c) => c.text).toList(),
    'metadatas': chunks.map((c) => {
      'documentId': c.documentId,
      'sourceLabel': c.sourceLabel,
      'chunkIndex': c.chunkIndex,
    }).toList(),
  }),
);
// Keep SourceDocument in ObjectBox for metadata/status tracking
```

### What does NOT change

`EmbeddingService`, `FactualHardeningService`, `InferenceRouter`, `ChatController`, `KbManagerController`, all screens, all Firebase code, all auth code.

### Estimated effort: 3–5 hours

---

## 17. What to Build — Prioritised Task List

Work top to bottom. Each task depends on the one above it being complete.

| # | Task | File | Notes |
|---|---|---|---|
| 1 | Create `AppConfig` | `lib/core/app_config.dart` | All constants from Section 8. No logic. |
| 2 | Create `rag_models.dart` | `lib/data/rag_models.dart` | All value objects from Section 7. No logic. |
| 3 | Create `app_exceptions.dart` | `lib/core/app_exceptions.dart` | `EmbeddingException`, `RouterException` from Section 9. |
| 4 | Create `ObjectBoxStore` | `lib/data/object_box_store.dart` | Thin wrapper, `box<T>()` method. |
| 5 | Fix `DocumentChunk` | `lib/data/document_chunk.dart` | Add `_cachedEmbedding` + `@Transient()` (O9). |
| 6 | Re-run build_runner | — | `dart run build_runner build --delete-conflicting-outputs` |
| 7 | Fix `EmbeddingService` | `lib/core/embedding_service.dart` | Add LinkedHashMap LRU cache (O2). Use `AppConfig`. |
| 8 | Fix `RagRetrievalService` | `lib/domain/rag_retrieval_service.dart` | Add `_chunkCache` + `invalidateCache()` (O1, O3). Fix query try/finally (M1). Import `rag_models.dart`. |
| 9 | Fix `FactualHardeningService` | `lib/domain/services/factual_hardening_service.dart` | Import `rag_models.dart` not `rag_retrieval_service.dart` (M4). |
| 10 | Fix `InferenceRouter` | `lib/domain/services/inference_router.dart` | Add `_isRagCandidate()` (O4). History budget (O5). Use `AppConfig`. Error handling contract (Section 9). |
| 11 | Fix `DocumentIngestionService` | `lib/domain/document_ingestion_service.dart` | File size guard (O8). Single `embedBatch` call (O6). Fix query try/finally (M1). Call `invalidateCache()`. Accept `retrieval` in constructor. |
| 12 | Create `KbManagerController` | `lib/presentation/kb_manager_controller.dart` | Per Section 8 contract. |
| 13 | Create `KbManagerBinding` | `lib/kb_manager_binding.dart` | `fenix: true` (M7). |
| 14 | Create `KbManagerScreen` | `lib/presentation/kb_manager_screen.dart` | Per Section 13 spec. |
| 15 | Fix `ChatController` | `lib/presentation/chat_controller.dart` | Remove `ChatService`. Call `InferenceRouter`. `_citationsMap` cleared with messages (M5). `unawaited` import (M6). `_budgetedHistory()` (O5). |
| 16 | Fix `ChatScreen` | `lib/presentation/chat_screen.dart` | Add library icon badge. Add citations collapsible row. |
| 17 | Fix `main.dart` | `lib/main.dart` | Exact wiring from Section 6. |
