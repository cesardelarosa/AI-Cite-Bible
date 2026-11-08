use engine::SearchEngine;
use std::env;
use std::path::PathBuf;
use std::time::Instant;

// Ejecutable de linea de comandos para validacion de latencia y resultados
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let root_dir = manifest_dir.parent().expect("Directorio raiz no encontrado");

    let db_path = root_dir.join("data/canon.db");
    let bin_path = root_dir.join("data/embeddings_384_f32.bin");
    let onnx_path = root_dir.join("models/encoder_int8.onnx");
    let tokenizer_path = root_dir.join("models/tokenizer.json");

    let t_init = Instant::now();
    let mut engine = SearchEngine::new(&db_path, &bin_path, &onnx_path, &tokenizer_path)?;
    let init_ms = t_init.elapsed().as_secs_f64() * 1000.0; // [ms]
    println!("Motor inicializado en {:.2} ms", init_ms);

    let args: Vec<String> = env::args().skip(1).collect();
    let queries: Vec<String> = if args.is_empty() {
        vec![
            "siento mucha ansiedad por el futuro y no puedo dormir".to_string(),
            "me cuesta perdonar a alguien que me ha traicionado".to_string(),
            "me siento solo y sin fuerzas para seguir adelante".to_string(),
        ]
    } else {
        vec![args.join(" ")]
    };

    for q in queries {
        let t0 = Instant::now();
        let hits = engine.search(&q, 3)?;
        let elapsed_ms = t0.elapsed().as_secs_f64() * 1000.0; // [ms]

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
