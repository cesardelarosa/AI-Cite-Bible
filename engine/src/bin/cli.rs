use engine::SearchEngine;
use std::env;
use std::path::{Path, PathBuf};
use std::time::Instant;

struct AssetPaths {
    db: PathBuf,
    vectors: PathBuf,
    onnx: PathBuf,
    tokenizer: PathBuf,
}

#[derive(Default)]
struct CliOverrides {
    root: Option<PathBuf>,
    db: Option<PathBuf>,
    vectors: Option<PathBuf>,
    onnx: Option<PathBuf>,
    tokenizer: Option<PathBuf>,
    top_k: Option<usize>,
    query_tokens: Vec<String>,
}

fn env_path(name: &str) -> Option<PathBuf> {
    env::var(name).ok().map(PathBuf::from)
}

fn parse_args() -> CliOverrides {
    let args: Vec<String> = env::args().skip(1).collect();
    let mut cfg = CliOverrides::default();

    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        let take_next = |idx: &mut usize| -> Option<PathBuf> {
            if *idx + 1 < args.len() {
                *idx += 2;
                Some(PathBuf::from(&args[*idx - 1]))
            } else {
                *idx += 1;
                None
            }
        };

        if arg == "--root" {
            cfg.root = take_next(&mut i);
        } else if let Some(v) = arg.strip_prefix("--root=") {
            cfg.root = Some(PathBuf::from(v));
            i += 1;
        } else if arg == "--db" {
            cfg.db = take_next(&mut i);
        } else if let Some(v) = arg.strip_prefix("--db=") {
            cfg.db = Some(PathBuf::from(v));
            i += 1;
        } else if arg == "--vectors" {
            cfg.vectors = take_next(&mut i);
        } else if let Some(v) = arg.strip_prefix("--vectors=") {
            cfg.vectors = Some(PathBuf::from(v));
            i += 1;
        } else if arg == "--onnx" {
            cfg.onnx = take_next(&mut i);
        } else if let Some(v) = arg.strip_prefix("--onnx=") {
            cfg.onnx = Some(PathBuf::from(v));
            i += 1;
        } else if arg == "--tokenizer" {
            cfg.tokenizer = take_next(&mut i);
        } else if let Some(v) = arg.strip_prefix("--tokenizer=") {
            cfg.tokenizer = Some(PathBuf::from(v));
            i += 1;
        } else if arg == "--top-k" && i + 1 < args.len() {
            cfg.top_k = args[i + 1].parse::<usize>().ok();
            i += 2;
        } else if let Some(v) = arg.strip_prefix("--top-k=") {
            cfg.top_k = v.parse::<usize>().ok();
            i += 1;
        } else {
            cfg.query_tokens.push(arg.clone());
            i += 1;
        }
    }

    cfg
}

fn first_existing(root: &Path, relative_candidates: &[&str]) -> Option<PathBuf> {
    relative_candidates
        .iter()
        .map(|rel| root.join(rel))
        .find(|path| path.exists())
}

/// Resuelve dinámicamente las rutas de los 4 artefactos requeridos:
/// 1. Flags explícitos (--db, --vectors, --onnx, --tokenizer) o env vars ENGINE_*
/// 2. `--root <PATH>` o `ENGINE_ROOT_DIR`
/// 3. Directorio de trabajo actual (`.`, `..`) y ancestros de `current_exe()`
fn resolve_asset_paths(cfg: &CliOverrides) -> Result<AssetPaths, Box<dyn std::error::Error>> {
    let explicit_db = cfg.db.clone().or_else(|| env_path("ENGINE_DB_PATH"));
    let explicit_vectors = cfg
        .vectors
        .clone()
        .or_else(|| env_path("ENGINE_VECTORS_PATH"));
    let explicit_onnx = cfg.onnx.clone().or_else(|| env_path("ENGINE_ONNX_PATH"));
    let explicit_tokenizer = cfg
        .tokenizer
        .clone()
        .or_else(|| env_path("ENGINE_TOKENIZER_PATH"));

    if let (Some(db), Some(vectors), Some(onnx), Some(tokenizer)) =
        (explicit_db, explicit_vectors, explicit_onnx, explicit_tokenizer)
    {
        return Ok(AssetPaths {
            db,
            vectors,
            onnx,
            tokenizer,
        });
    }

    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(root) = &cfg.root {
        candidates.push(root.clone());
    }
    if let Some(root_env) = env_path("ENGINE_ROOT_DIR") {
        candidates.push(root_env);
    }
    if let Ok(cwd) = env::current_dir() {
        candidates.push(cwd.clone());
        if let Some(parent) = cwd.parent() {
            candidates.push(parent.to_path_buf());
        }
    }
    if let Ok(exe_path) = env::current_exe() {
        let mut cur = exe_path.as_path();
        while let Some(parent) = cur.parent() {
            candidates.push(parent.to_path_buf());
            cur = parent;
        }
    }

    for root in &candidates {
        let db = first_existing(root, &["data/corpus.db", "data/canon.db", "corpus.db", "canon.db"]);
        let vectors = first_existing(
            root,
            &[
                "data/embeddings.bin",
                "data/embeddings_384_f32.bin",
                "embeddings.bin",
                "embeddings_384_f32.bin",
            ],
        );
        let onnx = first_existing(root, &["models/encoder_int8.onnx", "encoder_int8.onnx"]);
        let tokenizer = first_existing(root, &["models/tokenizer.json", "tokenizer.json"]);

        if let (Some(db), Some(vectors), Some(onnx), Some(tokenizer)) = (db, vectors, onnx, tokenizer) {
            return Ok(AssetPaths {
                db,
                vectors,
                onnx,
                tokenizer,
            });
        }
    }

    Err(format!(
        "No se encontraron los 4 artefactos requeridos (db, embeddings.bin, encoder_int8.onnx, tokenizer.json).\n\
         Candidatos explorados: {:?}\n\
         Usa --root <PATH> o --db/--vectors/--onnx/--tokenizer.",
        candidates
    )
    .into())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cfg = parse_args();
    let top_k = cfg.top_k.unwrap_or(3);
    let paths = resolve_asset_paths(&cfg)?;

    let t_init = Instant::now();
    let engine = SearchEngine::new(
        &paths.db,
        &paths.vectors,
        &paths.onnx,
        &paths.tokenizer,
    )?;
    let init_ms = t_init.elapsed().as_secs_f64() * 1000.0;
    let info = engine.corpus_info();
    println!(
        "Motor inicializado en {:.2} ms | Corpus '{}' ({} pasajes, dim={})",
        init_ms, info.title, info.row_count, info.embedding_dim
    );

    let queries: Vec<String> = if !cfg.query_tokens.is_empty() {
        vec![cfg.query_tokens.join(" ")]
    } else if !info.sample_queries.is_empty() {
        info.sample_queries.clone()
    } else {
        vec!["búsqueda semántica de prueba".to_string()]
    };

    for q in queries {
        let t0 = Instant::now();
        let hits = engine.search(&q, top_k)?;
        let elapsed_ms = t0.elapsed().as_secs_f64() * 1000.0;

        println!("\nConsulta: '{}' ({:.2} ms)", q, elapsed_ms);
        for hit in hits {
            println!(
                "  [{:.4}] {} [{} | {}]: {}",
                hit.score,
                hit.passage.title,
                hit.passage.collection,
                hit.passage.source_id,
                hit.passage.text
            );
        }
    }

    Ok(())
}
