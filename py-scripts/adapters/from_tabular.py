import argparse
import csv
import json
from pathlib import Path


def load_rows(input_path: Path):
    suffix = input_path.suffix.lower()
    if suffix == ".csv":
        with open(input_path, "r", encoding="utf-8", newline="") as f:
            return list(csv.DictReader(f))
    if suffix == ".jsonl":
        rows = []
        with open(input_path, "r", encoding="utf-8") as f:
            for line in f:
                stripped = line.strip()
                if stripped:
                    rows.append(json.loads(stripped))
        return rows
    if suffix == ".json":
        with open(input_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            return [{"key": k, "text": v} for k, v in data.items()]
        raise ValueError("El archivo JSON debe contener una lista de objetos o un diccionario clave-valor.")
    raise ValueError(f"Formato no soportado: {input_path.suffix}")


def main():
    parser = argparse.ArgumentParser(
        description="Convierte CSV, JSON o JSONL genérico al formato estándar corpus.jsonl"
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--text-col", type=str, default="text")
    parser.add_argument("--search-col", type=str, default=None)
    parser.add_argument("--id-col", type=str, default=None)
    parser.add_argument("--title-col", type=str, default=None)
    parser.add_argument("--collection-col", type=str, default=None)
    parser.add_argument("--group-col", type=str, default=None)
    parser.add_argument("--default-collection", type=str, default="Colección")
    args = parser.parse_args()

    raw_rows = load_rows(args.input)
    records = []

    for idx, row in enumerate(raw_rows):
        text = str(row.get(args.text_col, "")).strip()
        if not text:
            continue

        source_id = str(row[args.id_col]) if args.id_col and args.id_col in row else f"doc_{idx}"
        title = str(row[args.title_col]) if args.title_col and args.title_col in row else source_id
        collection = (
            str(row[args.collection_col])
            if args.collection_col and args.collection_col in row
            else args.default_collection
        )
        group_name = str(row[args.group_col]) if args.group_col and args.group_col in row else ""
        search_text = (
            str(row[args.search_col]).strip()
            if args.search_col and row.get(args.search_col)
            else text
        )

        reserved = {
            args.text_col,
            args.search_col,
            args.id_col,
            args.title_col,
            args.collection_col,
            args.group_col,
        }
        extra_meta = {k: v for k, v in row.items() if k not in reserved and v is not None}

        records.append(
            {
                "row_id": len(records),
                "source_id": source_id,
                "title": title,
                "collection": collection,
                "group_name": group_name,
                "text": text,
                "search_text": search_text,
                "metadata": extra_meta,
            }
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print(f"Convertidos {len(records)} registros -> {args.out}")


if __name__ == "__main__":
    main()
