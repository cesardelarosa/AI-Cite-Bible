import sqlite3
import time
from pathlib import Path
import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

# Simulacion del motor offline puro usando los 4 artefactos estaticos
def main():
    root_dir = Path(__file__).resolve().parent.parent
    db_path = root_dir / "data" / "canon.db"
    bin_path = root_dir / "data" / "embeddings_384_f32.bin"
    onnx_path = root_dir / "models" / "encoder_int8.onnx"
    tokenizer_path = root_dir / "models" / "tokenizer.json"

    tokenizer = Tokenizer.from_file(str(tokenizer_path))
    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])

    raw_bytes = np.fromfile(bin_path, dtype=np.float32)
    matrix = raw_bytes.reshape(-1, 384)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    queries = [
        "siento mucha ansiedad por el futuro y no puedo dormir",
        "me cuesta perdonar a alguien que me ha traicionado",
        "me siento solo y sin fuerzas para seguir adelante"
    ]

    for q in queries:
        t0 = time.perf_counter()

        encoded = tokenizer.encode(q)
        input_ids = np.array([encoded.ids], dtype=np.int64)
        attention_mask = np.array([encoded.attention_mask], dtype=np.int64)

        q_vec = session.run(
            ["sentence_embedding"],
            {"input_ids": input_ids, "attention_mask": attention_mask}
        )[0][0]

        scores = matrix @ q_vec
        top_indices = np.argpartition(scores, -3)[-3:]
        top_indices = top_indices[np.argsort(scores[top_indices])[::-1]]

        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        print(f"\nConsulta: '{q}' ({elapsed_ms:.2f} ms)")

        for idx in top_indices:
            cur.execute(
                "SELECT canonical_id, text FROM verses WHERE row_id = ?",
                (int(idx),)
            )
            cid, text = cur.fetchone()
            print(f"  [{scores[idx]:.4f}] {cid}: {text}")

    conn.close()

if __name__ == "__main__":
    main()
