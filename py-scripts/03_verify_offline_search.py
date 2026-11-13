import argparse
import json
import sqlite3
import time
from pathlib import Path
import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer


def load_db_context(cur: sqlite3.Cursor):
    tables = {
        row[0]
        for row in cur.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        ).fetchall()
    }
    if "passages" not in tables:
        raise RuntimeError(
            "La base SQLite debe contener la tabla 'passages'. "
            "Regenera el corpus con py-scripts/build_corpus.py o py-scripts/01_generate_corpus_and_vectors.py."
        )

    dim = 384
    sample_queries = []

    if "corpus_meta" in tables:
        meta = dict(cur.execute("SELECT key, value FROM corpus_meta").fetchall())
        if "embedding_dim" in meta:
            dim = int(meta["embedding_dim"])
        if "sample_queries_json" in meta:
            sample_queries = json.loads(meta["sample_queries_json"])

    return dim, sample_queries


def main():
    root_dir = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description="Verifica búsqueda semántica offline sobre cualquier corpus SQLite + bin + ONNX"
    )
    parser.add_argument("--db", type=Path, default=root_dir / "data" / "canon.db")
    parser.add_argument(
        "--vectors", type=Path, default=root_dir / "data" / "embeddings_384_f32.bin"
    )
    parser.add_argument(
        "--onnx", type=Path, default=root_dir / "models" / "encoder_int8.onnx"
    )
    parser.add_argument(
        "--tokenizer", type=Path, default=root_dir / "models" / "tokenizer.json"
    )
    parser.add_argument("--query", action="append", default=None)
    parser.add_argument("--top-k", type=int, default=3)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    cur = conn.cursor()
    dim, sample_queries = load_db_context(cur)

    tokenizer = Tokenizer.from_file(str(args.tokenizer))
    session = ort.InferenceSession(str(args.onnx), providers=["CPUExecutionProvider"])

    raw_bytes = np.fromfile(args.vectors, dtype=np.float32)
    matrix = raw_bytes.reshape(-1, dim)

    queries = args.query or sample_queries or [
        "siento mucha ansiedad por el futuro y no puedo dormir",
        "me cuesta perdonar a alguien que me ha traicionado",
        "me siento solo y sin fuerzas para seguir adelante",
    ]

    for q in queries:
        t0 = time.perf_counter()

        encoded = tokenizer.encode(q)
        input_ids = np.array([encoded.ids], dtype=np.int64)
        attention_mask = np.array([encoded.attention_mask], dtype=np.int64)

        q_vec = session.run(
            ["sentence_embedding"],
            {"input_ids": input_ids, "attention_mask": attention_mask},
        )[0][0]

        scores = matrix @ q_vec
        k = min(args.top_k, len(scores))
        top_indices = np.argpartition(scores, -k)[-k:]
        top_indices = top_indices[np.argsort(scores[top_indices])[::-1]]

        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        print(f"\nConsulta: '{q}' ({elapsed_ms:.2f} ms)")

        for idx in top_indices:
            cur.execute(
                "SELECT source_id, title, text FROM passages WHERE row_id = ?",
                (int(idx),),
            )
            sid, title, text = cur.fetchone()
            print(f"  [{scores[idx]:.4f}] {title} ({sid}): {text}")

    conn.close()


if __name__ == "__main__":
    main()
