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

/// Resuelve dinámicamente las rutas de los 4 artefactos requeridos:
/// 1. Argumento CLI `--root <PATH>`
/// 2. Variables de entorno (BIBLE_ROOT_DIR o rutas individuales)
/// 3. Directorio de trabajo actual (`.`) y su directorio padre (`..`)
/// 4. Árbol de directorios relativo al ejecutable actual (`current_exe()`)
fn resolve_asset_paths(custom_root: Option<&Path>) -> Result<AssetPaths, Box<dyn std::error::Error>> {
    // 1. Rutas explicitamente especificadas via variables de entorno
    let env_db = env::var("BIBLE_DB_PATH").ok().map(PathBuf::from);
    let env_vectors = env::var("BIBLE_VECTORS_PATH").ok().map(PathBuf::from);
    let env_onnx = env::var("BIBLE_ONNX_PATH").ok().map(PathBuf::from);
    let env_tokenizer = env::var("BIBLE_TOKENIZER_PATH").ok().map(PathBuf::from);

    if let (Some(db), Some(vectors), Some(onnx), Some(tokenizer)) =
        (env_db, env_vectors, env_onnx, env_tokenizer)
    {
        return Ok(AssetPaths {
            db,
            vectors,
            onnx,
            tokenizer,
        });
    }

    // 2. Lista de candidatos para la raíz del proyecto
    let mut candidates: Vec<PathBuf> = Vec::new();

    if let Some(root) = custom_root {
        candidates.push(root.to_path_buf());
    }

    if let Ok(root_env) = env::var("BIBLE_ROOT_DIR") {
        candidates.push(PathBuf::from(root_env));
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

    // 3. Buscar el primer candidato que contenga los 4 artefactos
    for root in &candidates {
        let db = root.join("data/canon.db");
        let vectors = root.join("data/embeddings_384_f32.bin");
        let onnx = root.join("models/encoder_int8.onnx");
        let tokenizer = root.join("models/tokenizer.json");

        if db.exists() && vectors.exists() && onnx.exists() && tokenizer.exists() {
            return Ok(AssetPaths {
                db,
                vectors,
                onnx,
                tokenizer,
            });
        }
    }

    Err(format!(
        "No se encontraron los 4 artefactos canónicos requeridos:\n\
         - data/canon.db\n\
         - data/embeddings_384_f32.bin\n\
         - models/encoder_int8.onnx\n\
         - models/tokenizer.json\n\
         Candidatos explorados: {:?}\n\
         Configura BIBLE_ROOT_DIR o usa --root <PATH>.",
        candidates
    )
    .into())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().skip(1).collect();

    let mut custom_root: Option<PathBuf> = None;
    let mut query_tokens: Vec<String> = Vec::new();

    let mut i = 0;
    while i < args.len() {
        if args[i] == "--root" && i + 1 < args.len() {
            custom_root = Some(PathBuf::from(&args[i + 1]));
            i += 2;
        } else if let Some(stripped) = args[i].strip_prefix("--root=") {
            custom_root = Some(PathBuf::from(stripped));
            i += 1;
        } else {
            query_tokens.push(args[i].clone());
            i += 1;
        }
    }

    let paths = resolve_asset_paths(custom_root.as_deref())?;

    let t_init = Instant::now();
    // Instanciación inmutable: SearchEngine ya no requiere mutabilidad exclusiva (&mut self)
    let engine = SearchEngine::new(
        &paths.db,
        &paths.vectors,
        &paths.onnx,
        &paths.tokenizer,
    )?;
    let init_ms = t_init.elapsed().as_secs_f64() * 1000.0;
    println!("Motor inicializado en {:.2} ms (Zero-Copy mmap)", init_ms);

    let queries: Vec<String> = if query_tokens.is_empty() {
        vec![
            "siento mucha ansiedad por el futuro y no puedo dormir".to_string(),
            "me cuesta perdonar a alguien que me ha traicionado".to_string(),
            "me siento solo y sin fuerzas para seguir adelante".to_string(),
        ]
    } else {
        vec![query_tokens.join(" ")]
    };

    for q in queries {
        let t0 = Instant::now();
        // Llamada concurrente e inmutable (&engine)
        let hits = engine.search(&q, 3)?;
        let elapsed_ms = t0.elapsed().as_secs_f64() * 1000.0;

        println!("\nConsulta: '{}' ({:.2} ms)", q, elapsed_ms);
        for hit in hits {
            println!(
                "  [{:.4}] {} ({} {}:{}): {}",
                hit.score,
                hit.verse.canonical_id,
                hit.verse.book_name,
                hit.verse.chapter,
                hit.verse.verse,
                hit.verse.text
            );
        }
    }

    Ok(())
}
