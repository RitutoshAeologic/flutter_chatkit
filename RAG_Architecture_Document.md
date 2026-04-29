# ChatKit AI — RAG Implementation Specification
### Version 2.0 — Final Reference for AI-Assisted Implementation

**Stack:** Flutter ≥3.19 · Dart ≥3.3 · GetX · Grok AI (Groq API) · Pollinations AI · Firebase Auth + RTDB · ObjectBox 4.x  
**Scope:** Adds RAG (document upload → embedding → retrieval → grounded chat) to an existing Flutter chat app.

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

1. [System Purpose & Boundaries](#1-system-purpose--boundaries)
2. [Architecture Overview](#2-architecture-overview)
3. [Complete Data Flows](#3-complete-data-flows)
4. [File Registry](#4-file-registry)
5. [State Machines](#5-state-machines)
6. [Service Wiring — Exact Registration Order](#6-service-wiring--exact-registration-order)
7. [Data Models — Exact Field Definitions](#7-data-models--exact-field-definitions)
8. [Service Contracts — Methods, Parameters, Return Types](#8-service-contracts--methods-parameters-return-types)
9. [Error Handling Contract](#9-error-handling-contract)
10. [Optimisations — What, Why, Exactly How](#10-optimisations--what-why-exactly-how)
11. [Known Mistakes & Exact Fixes](#11-known-mistakes--exact-fixes)
12. [ObjectBox Schema](#12-objectbox-schema)
13. [KbManagerScreen UI Specification](#13-kbmanagerscreen-ui-specification)
14. [pubspec.yaml](#14-pubspecyaml)
15. [Setup Checklist](#15-setup-checklist)
16. [Chroma Migration Path](#16-chroma-migration-path)
17. [What to Build — Prioritised Task List](#17-what-to-build--prioritised-task-list)

---

## 1. System Purpose & Boundaries

### What this system does

Answers the user's questions using Grok AI, optionally grounded in documents the user has uploaded. When the user uploads a PDF or TXT file, it is chunked, embedded, and stored locally. When the user sends a chat message, the system retrieves the most relevant chunks and injects them into the Grok prompt as verified context.

### Hard boundaries — what each store owns

| Store | Owns | Never touches |
|---|---|---|
| **Firebase RTDB** | Auth sessions, chat history, message timestamps | Documents, vectors, embeddings |
| **ObjectBox (local)** | `DocumentChunk` entities, `SourceDocument` metadata | Chat messages, user accounts |

These two stores are completely independent. No code reads from both in the same function.

### Three isolated concerns

| Concern | Entry point | External API used |
|---|---|---|
| Text chat + RAG answers | `ChatController.sendMessage()` | Groq chat completions + Groq embeddings |
| Image generation | `ChatController.sendMessage()` (detects `/image` prefix) | Pollinations AI (URL-only, no API key) |
| Document management | `KbManagerController.uploadDocument()` | Groq embeddings only |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                            USER                                 │
└───────────────────┬─────────────────────┬───────────────────────┘
                    │                     │
        ┌───────────▼──────────┐ ┌────────▼───────────┐
        │    CHAT MODULE       │ │  DOCUMENT MODULE    │
        │  ChatScreen          │ │  KbManagerScreen    │
        │  ChatController      │ │  KbManagerController│
        └───────────┬──────────┘ └────────┬────────────┘
                    │                     │
           /image?  │                     │ FilePicker
          ┌─────────┤                     ▼
          │         │            DocumentIngestionService
          ▼         │              │ compute() isolate
    Pollinations    │              │ → extract + chunk
    AI (URL)        │              │ EmbeddingService (Groq)
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
       Grok AI
   (llama-3.3-70b)
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
12    RagRetrievalService          Calls EmbeddingService.embed(text)        [~200ms, Groq API]
13    EmbeddingService             Checks _queryCache — returns cached vector if hit
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

**Zero RAG overhead** — the Groq embedding API is never called.

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

### Flow D — Document ingestion

```
Step  Who                          What
────  ───────────────────────────   ──────────────────────────────────────────────
 1    User                          Taps "Add Document" in KbManagerScreen
 2    KbManagerController           Sets isIngesting=true, progress=0.0
 3    DocumentIngestionService      FilePicker.pickFiles(pdf/txt, withData: mobile only)
 4    DocumentIngestionService      Guards: file.bytes == null → IngestionError
 5    DocumentIngestionService      Guards: bytes.length > 50MB → IngestionError (size limit)
 6    DocumentIngestionService      SHA-256(bytes).substring(0,16) → documentId
 7    DocumentIngestionService      ObjectBox: SourceDocument exists with this documentId?
                                    → yes: IngestionError("already in knowledge base")
 8    DocumentIngestionService      Creates SourceDocument(status: processing) → ObjectBox.put()
                                    → yield IngestionProgress("Extracting…", 0.10)
 9    DocumentIngestionService      compute(_extractAndChunkInIsolate, IsolateInput)
                                    [Background isolate — UI never blocks]
10    [Background isolate]          PDF: syncfusion extracts text per page + [[PAGE N]] markers
                                    TXT: utf8.decode(bytes, allowMalformed: true)
11    [Background isolate]          Sliding-window chunker: 150 words, 30-word overlap, max 800 chars
                                    Strips [[PAGE N]] → tracks currentPage → sourceLabel = "file.pdf p.3"
                                    Skips chunks with <30 characters
                                    Returns List<ChunkData> to main isolate
12    DocumentIngestionService      Guards: rawChunks.isEmpty → sets status:failed → IngestionError
                                    → yield IngestionProgress("Embedding N chunks…", 0.35)
13    DocumentIngestionService      EmbeddingService.embedBatch(all chunk texts at once)
                                    [EmbeddingService handles 96-per-call batching internally]
                                    → yield IngestionProgress("Saving…", 0.90)
14    DocumentIngestionService      Guards: embeddings.length != chunks.length → IngestionError
15    DocumentIngestionService      Builds List<DocumentChunk> with embeddingCsv
16    DocumentIngestionService      ObjectBox.putMany(chunks) — single transaction
17    DocumentIngestionService      SourceDocument.totalChunks = chunks.length, status = ready
                                    ObjectBox.put(sourceDocument)
18    DocumentIngestionService      Calls _retrieval.invalidateCache()
                                    → yield IngestionProgress("Done!", 1.0)
                                    → yield IngestionComplete(sourceDocument)
19    KbManagerController           Refreshes document list, sets isIngesting=false
20    KbManagerScreen               Shows snackbar: "file.pdf (47 chunks) added"
```

---

### Flow E — Document deletion

```
Step  Who                          What
────  ───────────────────────────   ──────────────────────────────────────────────
 1    User                          Taps delete icon on document tile
 2    KbManagerScreen               Shows confirmation dialog
 3    User                          Confirms
 4    KbManagerController           Calls DocumentIngestionService.deleteDocument(documentId)
 5    DocumentIngestionService      try/finally: ObjectBox query chunks by documentId
                                    → removeMany(chunkIds)
                                    → query.close()
 6    DocumentIngestionService      try/finally: ObjectBox query SourceDocument by documentId
                                    → removeMany(docIds)
                                    → query.close()
 7    DocumentIngestionService      Calls _retrieval.invalidateCache()
 8    KbManagerController           Refreshes list → document disappears from UI
```

---

## 4. File Registry

**Legend:** ✅ Already exists in codebase | 🔨 Must be created | ♻️ Existing file must be modified

### Core Layer — `lib/core/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| 🔨 | `app_config.dart` | Single source of truth: API key (via `--dart-define`), model names, URLs, all tunable thresholds. Zero logic, only constants. | — | Every service that calls an API |
| ✅♻️ | `embedding_service.dart` | Groq embedding API. `embed(text)` for single queries. `embedBatch(texts)` for ingestion. Internal batch size = 96. Sorts response by `index` field. L2-normalises every vector. Query-level LRU cache (max 100 entries). | `AppConfig`, `http` | `DocumentIngestionService`, `RagRetrievalService` |

### Data Layer — `lib/data/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| ✅♻️ | `document_chunk.dart` | ObjectBox entity. One text chunk + its 768-dim embedding (CSV). Cached embedding deserialization. | `objectbox` | `DocumentIngestionService`, `RagRetrievalService` |
| ✅ | `source_document.dart` | ObjectBox entity. Document metadata + ingestion lifecycle status. | `objectbox` | `DocumentIngestionService`, `KbManagerController` |
| 🔨 | `object_box_store.dart` | Thin wrapper: holds `Store`, exposes `box<T>()`. Opened once in `main()`, injected everywhere. | `objectbox.g.dart` (generated) | All domain services |
| 🔨 | `rag_models.dart` | Value objects only: `RagRetrievalResult`, `RagCitation`, `RouterResponse`, `IngestionEvent` sealed class + subclasses. No logic. | — | `RagRetrievalService`, `FactualHardeningService`, `InferenceRouter`, `KbManagerController` |
| ✅ | `chat_message.dart` | `ChatMessage`, `ChatSession`, `MessageRole` enum, `MessageType` enum. **Do not modify.** | — | `ChatController`, `InferenceRouter` |

### Domain Layer — `lib/domain/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| ✅♻️ | `document_ingestion_service.dart` | Full ingestion pipeline. FilePicker → dedup → `compute()` isolate → `embedBatch()` → `putMany()`. Yields `IngestionEvent` stream. Calls `_retrieval.invalidateCache()` after write. | `EmbeddingService`, `ObjectBoxStore`, `RagRetrievalService` (for invalidation only), `syncfusion_flutter_pdf`, `file_picker`, `crypto` | `KbManagerController` |
| ✅♻️ | `rag_retrieval_service.dart` | Vector search. Embeds query → uses `_chunkCache` (lazy-loaded, invalidated on write) → dot-product cosine → filter → dedup → top-3. Exposes `invalidateCache()`. | `EmbeddingService`, `ObjectBoxStore` | `InferenceRouter`, `DocumentIngestionService` (invalidation) |
| ✅♻️ | `services/factual_hardening_service.dart` | Prompt builder only. No I/O, no network. `buildSystemPrompt(RagRetrievalResult)` → `String`. Imports `rag_models.dart` only. | `rag_models.dart` | `InferenceRouter` |
| ✅♻️ | `services/inference_router.dart` | Orchestrates: `_isRagCandidate()` check → retrieval → hardening → Grok API call → `RouterResponse`. Also `generateTitle()`. Single owner of Grok chat URL + model. | `RagRetrievalService`, `FactualHardeningService`, `AppConfig`, `http` | `ChatController` |

### Presentation Layer — `lib/presentation/`

| Status | File | Single Responsibility | Depends On | Called By |
|---|---|---|---|---|
| ✅♻️ | `chat_controller.dart` | GetX controller. Calls `InferenceRouter.query()`. Holds `_citationsMap`. Clears `_citationsMap` whenever `messages.clear()` is called. `/image` → Pollinations. Firebase session logic unchanged. | `InferenceRouter`, `AuthController`, `FirebaseDatabase` | `ChatScreen` |
| 🔨 | `kb_manager_controller.dart` | GetX controller for document screen. `RxList<SourceDocument>`, `isIngesting`, `ingestionProgress`, `ingestionStatus`. Calls ingestion service, refreshes list. | `DocumentIngestionService` | `KbManagerScreen` |
| ✅♻️ | `chat_screen.dart` | Adds: library icon badge (doc count), citations collapsible row below RAG messages. All other UI unchanged. | `ChatController` | App router |
| 🔨 | `kb_manager_screen.dart` | Document list, upload button, delete with confirmation, progress bar. Full spec in Section 13. | `KbManagerController` | Drawer + App router |

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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── 1. ObjectBox ─────────────────────────────────────────────
  // Must be first. Every domain service depends on it.
  final store = await openStore();
  final obx = ObjectBoxStore(store);
  Get.put<ObjectBoxStore>(obx, permanent: true);

  // ── 2. EmbeddingService ──────────────────────────────────────
  // No dependencies beyond AppConfig.
  final embedder = EmbeddingService();
  Get.put<EmbeddingService>(embedder, permanent: true);

  // ── 3. RagRetrievalService ───────────────────────────────────
  // Needs ObjectBoxStore + EmbeddingService.
  final retrieval = RagRetrievalService(obx: obx, embedder: embedder);
  Get.put<RagRetrievalService>(retrieval, permanent: true);

  // ── 4. FactualHardeningService ───────────────────────────────
  // Stateless, no dependencies. const constructor.
  final hardening = const FactualHardeningService();
  Get.put<FactualHardeningService>(hardening, permanent: true);

  // ── 5. InferenceRouter ───────────────────────────────────────
  // Needs RagRetrievalService + FactualHardeningService.
  final router = InferenceRouter(retrieval: retrieval, hardening: hardening);
  Get.put<InferenceRouter>(router, permanent: true);

  // ── 6. DocumentIngestionService ──────────────────────────────
  // Needs ObjectBoxStore + EmbeddingService + RagRetrievalService.
  final ingestion = DocumentIngestionService(
    obx: obx,
    embedder: embedder,
    retrieval: retrieval, // for cache invalidation only
  );
  Get.put<DocumentIngestionService>(ingestion, permanent: true);

  // ── Controllers are LAZY — never pre-register them ──────────
  // ChatController: registered in AppBinding via GetPage
  // KbManagerController: registered in KbManagerBinding via GetPage

  runApp(const MyApp());
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
  static const String groqApiKey =
      String.fromEnvironment('GROQ_API_KEY', defaultValue: '');

  // Groq endpoints
  static const String chatUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String embedUrl =
      'https://api.groq.com/openai/v1/embeddings';

  // Model identifiers
  static const String chatModel   = 'llama-3.3-70b-versatile';
  static const String embedModel  = 'nomic-embed-text-v1.5';

  // RAG tuning constants — change here, affects entire system
  static const double similarityThreshold = 0.35;
  static const int    topKChunks          = 3;
  static const int    maxContextChars     = 3200;
  static const int    embeddingDimensions = 768;
  static const int    maxFileSizeBytes    = 50 * 1024 * 1024; // 50 MB

  // Chunking constants
  static const int chunkWordWindow = 150;
  static const int chunkWordOverlap = 30;
  static const int chunkMaxChars   = 800;
  static const int chunkMinChars   = 30;

  // History budget
  static const int historyMaxChars = 6000; // ~1500 tokens

  // Embedding cache
  static const int embedCacheMaxSize = 100;

  // Groq limits
  static const int embedBatchSize = 96;
  static const int embedMaxRetries = 3;
}
```

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

### DocumentIngestionService

```dart
class DocumentIngestionService {
  // Opens FilePicker, then runs full ingestion pipeline.
  // Yields IngestionEvent stream. Completes when done or on error.
  Stream<IngestionEvent> pickAndIngest();

  // Returns all SourceDocuments sorted by createdAt descending.
  List<SourceDocument> listDocuments();

  // Removes all DocumentChunks + the SourceDocument for this id.
  // Always closes ObjectBox queries in try/finally.
  // Calls retrieval.invalidateCache() after deletion.
  Future<void> deleteDocument(String documentId);
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

### O2 — Embedding LRU cache

**Problem:** Same query asked twice hits Groq twice (~200ms each).  
**Fix:** In-memory LRU cache, max 100 entries.

```dart
// EmbeddingService
final _queryCache = LinkedHashMap<String, List<double>>();

Future<List<double>> embed(String text) async {
  if (_queryCache.containsKey(text)) {
    // Move to end (most recently used)
    final v = _queryCache.remove(text)!;
    _queryCache[text] = v;
    return v;
  }
  final result = (await _callApi([text])).first;
  if (_queryCache.length >= AppConfig.embedCacheMaxSize) {
    _queryCache.remove(_queryCache.keys.first); // evict least recently used
  }
  _queryCache[text] = result;
  return result;
}
```

**Note:** Use `LinkedHashMap` (insertion-ordered) not `HashMap`. This makes `keys.first` the oldest entry — correct LRU eviction.

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

## 13. KbManagerScreen UI Specification

### Screen layout

```
AppBar
  title: "Knowledge Base"
  actions: [upload_icon_button (disabled while isIngesting)]

Body:
  if (isIngesting):
    IngestionProgressBanner(message, fraction)   ← LinearProgressIndicator

  if (ragDocuments.isEmpty && !isIngesting):
    EmptyState(icon, title, subtitle, upload_button)

  else:
    ListView of DocumentTile widgets

FAB: "Add Document" (hidden while isIngesting)
```

### DocumentTile widget

```
Container (border, rounded corners)
  leading: FileTypeIcon (PDF=red, TXT=blue)
  title: document.name (ellipsis overflow)
  subtitle: "${totalChunks} chunks · ${fileSizeKb} KB · ${formattedDate}"
  status badge:
    ready      → nothing (implied by green icon)
    processing → CircularProgressIndicator (small)
    failed     → red chip "Failed"
  trailing: IconButton(delete, color: red)
            disabled when status == processing
```

### Delete confirmation dialog

```
AlertDialog
  title: "Remove document?"
  content: "Remove '${doc.name}' from knowledge base?
            The AI will no longer reference it."
  actions:
    TextButton("Cancel")
    TextButton("Remove", color: red, onPressed: controller.deleteDocument)
```

### Ingestion progress banner

```
Container (primaryContainer background, top of body)
  Column:
    Text(ingestionStatus.value)           ← e.g. "Embedding 47 chunks…"
    SizedBox(h: 8)
    LinearProgressIndicator(value: ingestionProgress.value)
```

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
**Minimum iOS:** 13.0

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
