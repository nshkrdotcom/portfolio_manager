# Portfolio Manager Ecosystem Design Docs

This set documents the long term architecture for a portfolio-scale RAG ecosystem.
It assumes portfolio_manager is the user-facing app and rag_ex is a library.

## Contents

1. 00_overview.md
   - Vision, principles, and decision drivers
2. 01_rag_ex_review.md
   - Critical review of rag_ex capabilities and gaps
3. 02_architecture_options.md
   - Option space and tradeoffs
4. 03_recommended_architecture.md
   - Recommended multi-lib architecture and boundaries
5. 04_manifest_hex_core.md
   - Manifest-based hexagonal core design
6. 05_storage_graph_vector.md
   - Graph, vector, relational, and triple-store topology
7. 06_pipeline_and_ops.md
   - Pipelines, chunking, embedding, retrieval, and ops
8. 07_migration_plan.md
   - Incremental migration from current system

