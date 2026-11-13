import argparse
import json
import re
from pathlib import Path


HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")


def split_markdown_chunks(
    content: str,
    file_stem: str,
    min_chars: int,
    max_chars: int,
):
    """Divide un documento Markdown/texto en pasajes citables por encabezados y párrafos."""
    current_heading = file_stem
    buffer_paras = []
    chunks = []

    def flush():
        nonlocal buffer_paras
        if not buffer_paras:
            return
        text = "\n\n".join(buffer_paras).strip()
        buffer_paras = []
        if len(text) < min_chars:
            return
        chunks.append((current_heading, text))

    paragraphs = re.split(r"\n\s*\n", content.strip())
    for raw_para in paragraphs:
        para = raw_para.strip()
        if not para:
            continue

        lines = para.splitlines()
        heading_match = HEADING_RE.match(lines[0])
        if heading_match:
            flush()
            current_heading = heading_match.group(2).strip()
            rest = "\n".join(lines[1:]).strip()
            if not rest:
                continue
            para = rest

        # Si el párrafo individual excede max_chars, dividir por oraciones.
        if len(para) > max_chars:
            flush()
            sentences = re.split(r"(?<=[.!?])\s+", para)
            acc = ""
            for sent in sentences:
                if acc and len(acc) + 1 + len(sent) > max_chars:
                    if len(acc.strip()) >= min_chars:
                        chunks.append((current_heading, acc.strip()))
                    acc = sent
                else:
                    acc = f"{acc} {sent}".strip()
            if len(acc.strip()) >= min_chars:
                chunks.append((current_heading, acc.strip()))
            continue

        projected = sum(len(p) for p in buffer_paras) + len(para) + (2 * len(buffer_paras))
        if buffer_paras and projected > max_chars:
            flush()
        buffer_paras.append(para)

    flush()
    return chunks


def convert_directory(
    input_dir: Path,
    collection_override: str | None,
    min_chars: int,
    max_chars: int,
):
    files = sorted(
        [
            p
            for p in input_dir.rglob("*")
            if p.is_file() and p.suffix.lower() in {".md", ".markdown", ".txt"}
        ]
    )

    records = []
    row_id = 0
    for file_path in files:
        rel_path = file_path.relative_to(input_dir)
        collection = collection_override or (
            rel_path.parts[0] if len(rel_path.parts) > 1 else file_path.stem
        )
        content = file_path.read_text(encoding="utf-8")
        chunks = split_markdown_chunks(content, file_path.stem, min_chars, max_chars)

        heading_totals: dict[str, int] = {}
        for heading, _ in chunks:
            heading_totals[heading] = heading_totals.get(heading, 0) + 1

        heading_counts: dict[str, int] = {}
        for heading, text in chunks:
            heading_counts[heading] = heading_counts.get(heading, 0) + 1
            idx = heading_counts[heading]
            source_id = f"{rel_path.as_posix()}#{row_id}"
            title = (
                heading
                if heading_totals[heading] == 1
                else f"{heading} (§{idx})"
            )
            search_text = f"{collection} · {heading}: {text}"
            records.append(
                {
                    "row_id": row_id,
                    "source_id": source_id,
                    "title": title,
                    "collection": collection,
                    "group_name": file_path.stem,
                    "text": text,
                    "search_text": search_text,
                    "metadata": {
                        "file": rel_path.as_posix(),
                        "section": heading,
                        "chunk_index": idx,
                    },
                }
            )
            row_id += 1

    return records


def main():
    parser = argparse.ArgumentParser(
        description="Convierte un directorio de archivos .md/.txt al formato estándar corpus.jsonl"
    )
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--collection", type=str, default=None)
    parser.add_argument("--min-chars", type=int, default=40)
    parser.add_argument("--max-chars", type=int, default=700)
    args = parser.parse_args()

    records = convert_directory(
        args.input_dir,
        args.collection,
        args.min_chars,
        args.max_chars,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print(f"Generados {len(records)} pasajes desde {args.input_dir} -> {args.out}")


if __name__ == "__main__":
    main()
