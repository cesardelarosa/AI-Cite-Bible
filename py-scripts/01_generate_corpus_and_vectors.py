import argparse
import json
from pathlib import Path

from adapters.bible_rvr import export_rvr_records
from build_corpus import build_corpus


def main():
    py_dir = Path(__file__).resolve().parent
    root_dir = py_dir.parent

    parser = argparse.ArgumentParser(
        description="Genera canon.db (passages + corpus_meta) y embeddings_384_f32.bin para RVR1909"
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
        "--manifest",
        type=Path,
        default=py_dir / "manifests" / "rvr1909.json",
    )
    parser.add_argument(
        "--out-db",
        type=Path,
        default=root_dir / "data" / "canon.db",
    )
    parser.add_argument(
        "--out-bin",
        type=Path,
        default=root_dir / "data" / "embeddings_384_f32.bin",
    )
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--device", type=str, default="cpu")
    parser.add_argument(
        "--skip-embeddings",
        action="store_true",
        help="Regenera solo canon.db manteniendo el embeddings_384_f32.bin existente",
    )
    args = parser.parse_args()

    with open(args.manifest, "r", encoding="utf-8") as f:
        meta_config = json.load(f)

    records = export_rvr_records(args.canonical, args.metadata)
    print(f"Pasajes RVR1909 procesados: {len(records)}")

    dim, count = build_corpus(
        records=records,
        out_db=args.out_db,
        out_bin=args.out_bin,
        meta_config=meta_config,
        batch_size=args.batch_size,
        device=args.device,
        skip_embeddings=args.skip_embeddings,
    )

    print(
        f"SQLite listo: {args.out_db} ({count} filas, dim={dim}, "
        f"{args.out_db.stat().st_size / (1024*1024):.2f} MB)"
    )
    print(
        f"Binario listo: {args.out_bin} ({args.out_bin.stat().st_size / (1024*1024):.2f} MB)"
    )


if __name__ == "__main__":
    main()
