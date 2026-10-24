"""Chroma vector store for semantic long-term memory (Phase 3 wiring)."""

from __future__ import annotations

from typing import Optional, Protocol

from utils.config import Settings


class SemanticMemoryStore(Protocol):
    def upsert(self, memory_id: str, text: str, metadata: dict) -> None: ...
    def search(self, query: str, limit: int = 5) -> list[str]: ...
    def delete(self, memory_id: str) -> None: ...


class ChromaSemanticMemory:
    """
    Chroma-backed RAG index.

    Phase 1 does not attach this to the voice loop yet. Phase 3 will:
    query → embedding → Chroma search → Dialogue Manager / Llama.
    """

    def __init__(self, settings: Settings, persist: bool = False) -> None:
        self._settings = settings
        self._persist = persist
        self._collection = None

    def load(self) -> None:
        if self._collection is not None:
            return
        import chromadb

        if self._persist:
            client = chromadb.PersistentClient(path=str(self._settings.chroma_path))
        else:
            client = chromadb.Client()
        self._collection = client.get_or_create_collection("patient_long_term_memory")

    def upsert(self, memory_id: str, text: str, metadata: dict) -> None:
        self.load()
        assert self._collection is not None
        self._collection.upsert(ids=[memory_id], documents=[text], metadatas=[metadata])

    def search(self, query: str, limit: int = 5) -> list[str]:
        self.load()
        assert self._collection is not None
        result = self._collection.query(query_texts=[query], n_results=limit)
        documents = result.get("documents") or [[]]
        return documents[0]

    def delete(self, memory_id: str) -> None:
        self.load()
        assert self._collection is not None
        self._collection.delete(ids=[memory_id])


class NullSemanticMemory:
    """Used until Phase 3. Same interface as ChromaSemanticMemory."""

    def upsert(self, memory_id: str, text: str, metadata: dict) -> None:
        return None

    def search(self, query: str, limit: int = 5) -> list[str]:
        return []

    def delete(self, memory_id: str) -> None:
        return None
