import argparse
import json
import sqlite3
from pathlib import Path


DEFAULT_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"


def load_jsonl_records(jsonl_path: Path):
    records = []
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for idx, line in enumerate(f):
            stripped = line.strip()
            if not stripped:
                continue
            item = json.loads(stripped)
            row_id = int(item.get("row_id", idx))
            if row_id != len(records):
                raise ValueError(
                    f"row_id debe ser secuencial 0..N-1; esperado {len(records)}, recibido {row_id}"
                )
            text = str(item["text"]).strip()
            search_text = str(item.get("search_text") or text).strip()
            records.append(
                {
                    "row_id": row_id,
                    "source_id": str(item["source_id"]),
                    "title": str(item.get("title") or item["source_id"]),
                    "collection": str(item.get("collection") or ""),
                    "group_name": str(item.get("group_name") or ""),
                    "text": text,
                    "search_text": search_text,
                    "metadata": item.get("metadata") or {},
                }
            )
    if not records:
        raise ValueError(f"No se encontraron registros válidos en {jsonl_path}")
    return records


def build_sqlite_db(records, db_path: Path, meta: dict):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute(
        """
        CREATE TABLE corpus_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """
    )

    cur.execute(
        """
        CREATE TABLE passages (
            row_id INTEGER PRIMARY KEY,
            source_id TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            collection TEXT NOT NULL,
            group_name TEXT NOT NULL DEFAULT '',
            text TEXT NOT NULL,
            metadata_json TEXT NOT NULL DEFAULT '{}'
        )
        """
    )

    meta_rows = [(str(k), str(v)) for k, v in meta.items()]
    cur.executemany("INSERT INTO corpus_meta (key, value) VALUES (?, ?)", meta_rows)

    passage_rows = [
        (
            r["row_id"],
            r["source_id"],
            r["title"],
            r["collection"],
            r["group_name"],
            r["text"],
            json.dumps(r["metadata"], ensure_ascii=False),
        )
        for r in records
    ]
    cur.executemany(
        """
        INSERT INTO passages (
            row_id, source_id, title, collection, group_name, text, metadata_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        passage_rows,
    )

    cur.execute("CREATE INDEX idx_passages_source_id ON passages(source_id)")
    cur.execute("CREATE INDEX idx_passages_collection ON passages(collection)")

    conn.commit()
    conn.close()


def generate_embeddings_bin(
    records,
    bin_path: Path,
    model_name: str,
    batch_size: int = 128,
    device: str = "cpu",
):
    import numpy as np
    from sentence_transformers import SentenceTransformer

    texts_for_model = [r["search_text"] for r in records]
    model = SentenceTransformer(model_name, device=device)

    embeddings = model.encode(
        texts_for_model,
        batch_size=batch_size,
        show_progress_bar=True,
        normalize_embeddings=True,
        convert_to_numpy=True,
    ).astype(np.float32)

    if embeddings.ndim != 2 or embeddings.shape[0] != len(records):
        raise AssertionError(f"Shape inesperado: {embeddings.shape}")

    norms = np.linalg.norm(embeddings[: min(10, len(records))], axis=1)
    if not np.allclose(norms, 1.0, atol=1e-4):
        raise AssertionError("Fallo en normalización L2 de los embeddings")

    bin_path.parent.mkdir(parents=True, exist_ok=True)
    embeddings.tofile(bin_path)
    return embeddings.shape


def infer_dim_from_bin(bin_path: Path, num_rows: int) -> int:
    byte_size = bin_path.stat().st_size
    if byte_size % (num_rows * 4) != 0:
        raise ValueError(
            f"{bin_path} ({byte_size} bytes) no es múltiplo de {num_rows} filas x 4 bytes."
        )
    return byte_size // (num_rows * 4)


def build_corpus(
    records,
    out_db: Path,
    out_bin: Path,
    meta_config: dict,
    batch_size: int = 128,
    device: str = "cpu",
    skip_embeddings: bool = False,
):
    model_name = meta_config.get("model_name", DEFAULT_MODEL)

    if skip_embeddings:
        if not out_bin.exists():
            raise FileNotFoundError(
                f"--skip-embeddings requiere que ya exista el binario: {out_bin}"
            )
        embedding_dim = infer_dim_from_bin(out_bin, len(records))
    else:
        shape = generate_embeddings_bin(
            records,
            out_bin,
            model_name=model_name,
            batch_size=batch_size,
            device=device,
        )
        embedding_dim = int(shape[1])

    sample_queries = meta_config.get("sample_queries", [])
    sqlite_meta = {
        "corpus_id": meta_config.get("corpus_id", "default"),
        "title": meta_config.get("title", "CITADOR SEMÁNTICO"),
        "subtitle": meta_config.get("subtitle", "¿Qué pasaje o idea deseas consultar?"),
        "search_hint": meta_config.get(
            "search_hint", "Escribe una situación, concepto o pregunta..."
        ),
        "version": meta_config.get("version", "1.0.0"),
        "language": meta_config.get("language", "es"),
        "model_name": model_name,
        "embedding_dim": str(embedding_dim),
        "row_count": str(len(records)),
        "sample_queries_json": json.dumps(sample_queries, ensure_ascii=False),
    }

    build_sqlite_db(records, out_db, sqlite_meta)
    return embedding_dim, len(records)


def main():
    root_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description="Construye SQLite (passages + corpus_meta) y matriz binaria f32 desde cualquier corpus.jsonl"
    )
    parser.add_argument("--input", type=Path, required=True, help="Ruta a corpus.jsonl")
    parser.add_argument("--out-db", type=Path, default=root_dir / "data" / "canon.db")
    parser.add_argument(
        "--out-bin", type=Path, default=root_dir / "data" / "embeddings_384_f32.bin"
    )
    parser.add_argument("--manifest", type=Path, default=None, help="JSON opcional de metadatos")
    parser.add_argument("--corpus-id", type=str, default=None)
    parser.add_argument("--title", type=str, default=None)
    parser.add_argument("--subtitle", type=str, default=None)
    parser.add_argument("--search-hint", type=str, default=None)
    parser.add_argument("--version", type=str, default=None)
    parser.add_argument("--language", type=str, default=None)
    parser.add_argument("--model", type=str, default=None)
    parser.add_argument("--sample-query", action="append", default=None)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--device", type=str, default="cpu")
    parser.add_argument(
        "--skip-embeddings",
        action="store_true",
        help="Reconstruye solo la SQLite reutilizando un .bin ya existente y alineado",
    )
    args = parser.parse_args()

    meta_config = {}
    if args.manifest is not None:
        with open(args.manifest, "r", encoding="utf-8") as f:
            meta_config = json.load(f)

    overrides = {
        "corpus_id": args.corpus_id,
        "title": args.title,
        "subtitle": args.subtitle,
        "search_hint": args.search_hint,
        "version": args.version,
        "language": args.language,
        "model_name": args.model,
        "sample_queries": args.sample_query,
    }
    for k, v in overrides.items():
        if v is not None:
            meta_config[k] = v

    records = load_jsonl_records(args.input)
    dim, count = build_corpus(
        records=records,
        out_db=args.out_db,
        out_bin=args.out_bin,
        meta_config=meta_config,
        batch_size=args.batch_size,
        device=args.device,
        skip_embeddings=args.skip_embeddings,
    )

    print(f"Corpus construido: {count} pasajes (dim={dim})")
    print(f"  SQLite: {args.out_db} ({args.out_db.stat().st_size / (1024*1024):.2f} MB)")
    print(f"  Binario: {args.out_bin} ({args.out_bin.stat().st_size / (1024*1024):.2f} MB)")


if __name__ == "__main__":
    main()
