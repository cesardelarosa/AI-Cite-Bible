import json
import re
import sqlite3
from pathlib import Path
import numpy as np
from sentence_transformers import SentenceTransformer

# Limpieza de mayusculas iniciales de capitulo y tildes arcaicas RVR1909 para el encoder
def clean_for_embedding(text: str) -> str:
    text = re.sub(r"^([A-ZÁÉÍÓÚÑ])([A-ZÁÉÍÓÚÑ]+)\b", lambda m: m.group(1) + m.group(2).lower(), text)
    replacements = {
        r"\bá\b": "a",
        r"\bÁ\b": "A",
        r"\bfué\b": "fue",
        r"\bvió\b": "vio",
        r"\bdió\b": "dio",
    }
    for pattern, repl in replacements.items():
        text = re.sub(pattern, repl, text)
    return text

# Carga y cruce de bible_canonical.json con books_metadata.json
def load_canonical_data(canonical_path: Path, metadata_path: Path):
    with open(metadata_path, "r", encoding="utf-8") as f:
        books_meta = json.load(f)

    abbr_map = {b["abbr"]: b for b in books_meta}

    with open(canonical_path, "r", encoding="utf-8") as f:
        raw_dict = json.load(f)

    records = []
    for idx, (c_id, text) in enumerate(raw_dict.items()):
        abbr, chap_verse = c_id.rsplit(" ", 1)
        chap_str, verse_str = chap_verse.split(":")
        chapter = int(chap_str)
        verse = int(verse_str)

        b_info = abbr_map[abbr]
        clean_display = re.sub(
            r"^([A-ZÁÉÍÓÚÑ])([A-ZÁÉÍÓÚÑ]+)\b",
            lambda m: m.group(1) + m.group(2).lower(),
            text.strip()
        )

        records.append((
            idx,
            c_id,
            b_info["id"],
            abbr,
            b_info["name"],
            b_info["testament"],
            chapter,
            verse,
            clean_display
        ))

    return records

# Creacion de la base de datos SQLite
def build_sqlite_db(records, db_path: Path):
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE verses (
            row_id INTEGER PRIMARY KEY,
            canonical_id TEXT UNIQUE NOT NULL,
            book_id INTEGER NOT NULL,
            book_abbr TEXT NOT NULL,
            book_name TEXT NOT NULL,
            testament TEXT NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            text TEXT NOT NULL
        )
    """)

    cur.executemany("""
        INSERT INTO verses (
            row_id, canonical_id, book_id, book_abbr,
            book_name, testament, chapter, verse, text
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, records)

    cur.execute("CREATE INDEX idx_canonical ON verses(canonical_id)")
    cur.execute("CREATE INDEX idx_book_id ON verses(book_id)")

    conn.commit()
    conn.close()

# Inferencia por lotes y exportacion binaria f32
def generate_embeddings_bin(records, bin_path: Path, model_name: str):
    texts_for_model = [clean_for_embedding(r[8]) for r in records]
    model = SentenceTransformer(model_name, device="cpu")

    embeddings = model.encode(
        texts_for_model,
        batch_size=128,
        show_progress_bar=True,
        normalize_embeddings=True,
        convert_to_numpy=True
    ).astype(np.float32)

    assert embeddings.shape == (len(records), 384), f"Shape inesperado: {embeddings.shape}"
    norms = np.linalg.norm(embeddings[:10], axis=1)
    assert np.allclose(norms, 1.0, atol=1e-4), "Fallo en normalizacion L2"

    embeddings.tofile(bin_path)
    return embeddings.shape

def main():
    root_dir = Path(__file__).resolve().parent.parent
    canonical_json = root_dir / "data" / "bible_canonical.json"
    metadata_json = root_dir / "data" / "books_metadata.json"
    output_db = root_dir / "data" / "canon.db"
    output_bin = root_dir / "data" / "embeddings_384_f32.bin"
    model_name = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"

    records = load_canonical_data(canonical_json, metadata_json)
    print(f"Versiculos procesados: {len(records)}")

    build_sqlite_db(records, output_db)
    print(f"SQLite listo: {output_db} ({output_db.stat().st_size / (1024*1024):.2f} MB)")

    shape = generate_embeddings_bin(records, output_bin, model_name)
    print(f"Binario listo: {output_bin} {shape} ({output_bin.stat().st_size / (1024*1024):.2f} MB)")

if __name__ == "__main__":
    main()
