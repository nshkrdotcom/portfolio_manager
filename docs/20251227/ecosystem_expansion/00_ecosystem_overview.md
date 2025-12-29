# Portfolio Ecosystem Overview

## Executive Summary

The Portfolio ecosystem consists of three layered Elixir packages implementing a production-grade RAG (Retrieval-Augmented Generation) system using hexagonal architecture. A fourth repository, `rag_ex`, serves as an experimental prototype with advanced features that can inform future development.

## Architecture Comparison

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PORTFOLIO ECOSYSTEM (v0.2.0)                         │
│                   Clean Hexagonal Architecture                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  portfolio_manager (Application Layer)                              │   │
│  │  - CLI tools (mix portfolio.*)                                      │   │
│  │  - User-facing API                                                  │   │
│  │  - OTP supervision                                                  │   │
│  │  - Examples & documentation                                         │   │
│  └──────────────────────────────┬──────────────────────────────────────┘   │
│                                 │                                           │
│  ┌──────────────────────────────┴──────────────────────────────────────┐   │
│  │  portfolio_core (Domain Layer)          portfolio_index (Adapters)  │   │
│  │  - 8 port specifications                - Pgvector adapter          │   │
│  │  - Manifest engine                      - Neo4j adapter             │   │
│  │  - Adapter registry                     - Gemini embedder/LLM       │   │
│  │  - Telemetry framework                  - Broadway pipelines        │   │
│  │  - Pure interfaces                      - RAG strategies            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           RAG_EX (v0.4.0)                                   │
│                   Feature-Rich Prototype                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Monolithic but Modular Architecture                                │   │
│  │                                                                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │   Router    │  │   Chunker   │  │  Retriever  │                 │   │
│  │  │ (8 providers│  │(6 strategies│  │ (4 types)   │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  │                                                                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │ VectorStore │  │ GraphStore  │  │   Agent     │                 │   │
│  │  │ (pgvector)  │  │(TripleStore)│  │ (tools)     │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  │                                                                     │   │
│  │  ┌─────────────┐  ┌─────────────┐                                  │   │
│  │  │  Pipeline   │  │  Embedding  │                                  │   │
│  │  │   (DAG)     │  │  Service    │                                  │   │
│  │  └─────────────┘  └─────────────┘                                  │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Comparative Analysis

| Aspect | Portfolio Ecosystem | rag_ex |
|--------|---------------------|--------|
| **Architecture** | Clean hexagonal, 3 packages | Monolithic with internal modularity |
| **Maturity** | v0.1.1-0.2.0 (new) | v0.4.0 (established) |
| **Code Size** | ~2000 LOC across 3 packages | 66 modules, 532KB |
| **LLM Providers** | Gemini (full), OpenAI/Anthropic (stubs) | 8 providers with routing |
| **Chunking** | Recursive (1 strategy) | 6 strategies with behaviors |
| **Vector Store** | Pgvector only | Pgvector + future options |
| **Graph Store** | Neo4j only | Pgvector + TripleStore (RocksDB) |
| **RAG Strategies** | Hybrid, SelfRAG (Agentic/Graph stubs) | Semantic, FullText, Hybrid, Graph |
| **Pipelines** | Broadway-based | DAG-based with caching |
| **Agent Framework** | Not present | Full tool-using agents |
| **Test Coverage** | Mox-based mocks | Mimic-based, credential-dependent |
| **Hex.pm Published** | Yes (core, index) | Yes |

## Key Insights

### Portfolio Ecosystem Strengths
1. **Clean separation of concerns** - Pure domain layer with zero external dependencies
2. **Manifest-driven configuration** - Runtime adapter selection without code changes
3. **Registry pattern** - Fast O(1) adapter lookup with ETS
4. **Publishable packages** - Each layer independently versioned on Hex.pm
5. **Strong typing** - Comprehensive typespecs throughout

### Portfolio Ecosystem Gaps (vs rag_ex)
1. **Limited provider support** - Only Gemini fully implemented
2. **Single chunking strategy** - Missing semantic, sentence, paragraph chunkers
3. **No agent framework** - Cannot do tool-based reasoning
4. **No pipeline orchestration** - Missing DAG workflows with caching
5. **Limited retrieval strategies** - No full-text search, no hybrid with RRF
6. **No streaming support** - LLM streaming not implemented

### rag_ex Strengths
1. **Feature richness** - 8 providers, 6 chunkers, 4 retrievers
2. **Advanced graph storage** - TripleStore with RDF semantics
3. **Agent framework** - Tool-using agents with session memory
4. **Pipeline orchestration** - DAG workflows with parallelism
5. **Active development** - Rapid iteration cycle

### rag_ex Gaps (vs Portfolio)
1. **Monolithic structure** - Hard to use individual components
2. **No manifest system** - Configuration scattered
3. **Dependency complexity** - Many optional deps to manage
4. **Breaking changes** - Frequent API changes in minor versions
5. **Test reliability** - Credential-dependent tests

## Strategic Recommendations

### Phase 1: Foundation Strengthening
- Portfolio: Add more LLM providers, chunking strategies
- rag_ex: Stabilize API, complete TripleStore adapter

### Phase 2: Feature Parity
- Portfolio: Add agent framework, pipeline orchestration from rag_ex
- rag_ex: Add manifest system, registry pattern from Portfolio

### Phase 3: Convergence (Optional)
- Consider extracting rag_ex best components into portfolio_index
- Or maintain both with clear differentiation (stable vs experimental)

## Document Structure

Each repository has the following expansion documents:

1. `01_current_state.md` - Detailed analysis of current implementation
2. `02_expansion_roadmap.md` - Feature expansion plans with priorities
3. `03_implementation_details.md` - Technical specifications for new features
4. `04_migration_guide.md` - For rag_ex: migration path to portfolio ecosystem
