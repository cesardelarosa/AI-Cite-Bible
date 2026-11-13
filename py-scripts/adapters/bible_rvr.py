import argparse
import json
import re
from pathlib import Path


def clean_for_embedding(text: str) -> str:
    """Normaliza mayúsculas iniciales de capítulo y tildes arcaicas RVR1909 para el encoder."""
    text = re.sub(
        r"^([A-ZÁÉÍÓÚÑ])([A-ZÁÉÍÓÚÑ]+)\b",
        lambda m: m.group(1) + m.group(2).lower(),
        text,
    )
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


def clean_display_text(text: str) -> str:
    return re.sub(
        r"^([A-ZÁÉÍÓÚÑ])([A-ZÁÉÍÓÚÑ]+)\b",
        lambda m: m.group(1) + m.group(2).lower(),
        text.strip(),
    )


def export_rvr_records(canonical_path: Path, metadata_path: Path):
    """Genera registros normalizados compatibles con `build_corpus.py` desde RVR1909."""
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
        display_text = clean_display_text(text)
        search_text = clean_for_embedding(display_text)
        testament_code = b_info["testament"]
        group_name = (
            "Antiguo Testamento"
            if testament_code == "AT"
            else ("Nuevo Testamento" if testament_code == "NT" else testament_code)
        )

        records.append(
            {
                "row_id": idx,
                "source_id": c_id,
                "title": f"{b_info['name']} {chapter}:{verse}",
                "collection": b_info["name"],
                "group_name": group_name,
                "text": display_text,
                "search_text": search_text,
                "metadata": {
                    "book_id": b_info["id"],
                    "book_abbr": abbr,
                    "testament": testament_code,
                    "chapter": chapter,
                    "verse": verse,
                },
            }
        )

    return records


def write_jsonl(records, out_path: Path) -> int:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return len(records)


def main():
    root_dir = Path(__file__).resolve().parent.parent.parent
    parser = argparse.ArgumentParser(
        description="Convierte bible_canonical.json + books_metadata.json al formato estándar corpus.jsonl"
    )
    parser.add_argument(
        "--canonical",
        type=Path,
        default=root_dir / "data" / "bible_canonical.json",
    )
    parser.add_argument(
        "--metadata",
        type=Path,
        default=root_dir / "data" / "books_metadata.json",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=root_dir / "data" / "rvr1909_corpus.jsonl",
    )
    args = parser.parse_args()

    records = export_rvr_records(args.canonical, args.metadata)
    count = write_jsonl(records, args.out)
    print(f"Exportados {count} pasajes a {args.out}")


if __name__ == "__main__":
    main()
