use ort::session::{builder::GraphOptimizationLevel, Session};
use ort::value::Value;
use std::env;
use std::error::Error;
use std::path::Path;
use std::sync::Mutex;
use tokenizers::Tokenizer;

pub struct OnnxEncoder {
    tokenizer: Tokenizer,
    session: Mutex<Session>,
}

impl OnnxEncoder {
    /// Inicialización del tokenizador y sesión ONNX Runtime.
    pub fn new<P: AsRef<Path>>(onnx_path: P, tokenizer_path: P) -> Result<Self, Box<dyn Error>> {
        let tokenizer = Tokenizer::from_file(tokenizer_path)
            .map_err(|e| format!("Error cargando tokenizer: {e}"))?;

        let intra_threads = env::var("ORT_INTRA_THREADS")
            .ok()
            .and_then(|v| v.trim().parse::<usize>().ok())
            .filter(|&n| n > 0)
            .unwrap_or(4);

        #[cfg(target_os = "android")]
        let env = {
            let dylib =
                env::var("ORT_DYLIB_PATH").unwrap_or_else(|_| "libonnxruntime.so".to_string());
            ort::init_from(dylib)?.with_name("engine").build()?
        };

        #[cfg(not(target_os = "android"))]
        let env = ort::init().with_name("engine").build()?;

        let session = Session::builder(&env)?
            .with_optimization_level(GraphOptimizationLevel::Level3)?
            .with_intra_threads(intra_threads)?
            .commit_from_file(onnx_path)?;

        Ok(Self {
            tokenizer,
            session: Mutex::new(session),
        })
    }

    /// Inferencia inmutable y thread-safe del modelo con extracción del vector f32.
    pub fn encode(&self, text: &str) -> Result<Vec<f32>, Box<dyn Error>> {
        let encoding = self
            .tokenizer
            .encode(text, true)
            .map_err(|e| format!("Error al tokenizar: {e}"))?;

        let seq_len = encoding.get_ids().len();
        let input_ids: Vec<i64> = encoding.get_ids().iter().map(|&x| x as i64).collect();
        let attention_mask: Vec<i64> = encoding
            .get_attention_mask()
            .iter()
            .map(|&x| x as i64)
            .collect();

        let ids_tensor = Value::from_array(([1usize, seq_len], input_ids))?;
        let mask_tensor = Value::from_array(([1usize, seq_len], attention_mask))?;

        let mut session = self
            .session
            .lock()
            .map_err(|e| format!("Error bloqueando sesión ONNX: {e}"))?;

        let outputs = session.run(ort::inputs![
            "input_ids" => ids_tensor,
            "attention_mask" => mask_tensor,
        ])?;

        let (_shape, data) = outputs["sentence_embedding"].try_extract_tensor::<f32>()?;
        Ok(data.to_vec())
    }
}
