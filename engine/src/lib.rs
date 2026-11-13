pub mod db;
pub mod encoder;
pub mod ffi;
pub mod vector;

use db::{CorpusDb, CorpusInfo, PassageRecord};
use encoder::OnnxEncoder;
use serde::Serialize;
use std::error::Error;
use std::path::Path;
use vector::VectorIndex;

#[derive(Debug, Clone, Serialize)]
pub struct SearchHit {
    pub score: f32,
    pub passage: PassageRecord,
}

pub struct SearchEngine {
    encoder: OnnxEncoder,
    index: VectorIndex,
    db: CorpusDb,
}

impl SearchEngine {
    /// Carga de los 4 artefactos del motor offline validando coherencia dimensional y de filas.
    pub fn new<P: AsRef<Path>>(
        db_path: P,
        bin_path: P,
        onnx_path: P,
        tokenizer_path: P,
    ) -> Result<Self, Box<dyn Error>> {
        let db = CorpusDb::open(db_path)?;
        let expected_dim = db.info().embedding_dim;
        let expected_rows = db.info().row_count;

        let index = VectorIndex::from_file_with_dim(bin_path, expected_dim)?;
        if index.len() != expected_rows {
            return Err(format!(
                "Desajuste entre índice vectorial ({} filas) y base de datos ({} filas)",
                index.len(),
                expected_rows
            )
            .into());
        }

        let encoder = OnnxEncoder::new(onnx_path, tokenizer_path)?;

        Ok(Self { encoder, index, db })
    }

    pub fn corpus_info(&self) -> &CorpusInfo {
        self.db.info()
    }

    /// Ejecución inmutable del pipeline completo de consulta semántica.
    pub fn search(&self, query: &str, top_k: usize) -> Result<Vec<SearchHit>, Box<dyn Error>> {
        let q_vec = self.encoder.encode(query)?;
        let expected_dim = self.index.embedding_dim();
        if q_vec.len() != expected_dim {
            return Err(format!(
                "Dimensión del encoder ({}) incompatible con el índice vectorial ({})",
                q_vec.len(),
                expected_dim
            )
            .into());
        }

        let top_rows = self.index.search_top_k(&q_vec, top_k);

        let mut hits = Vec::with_capacity(top_rows.len());
        for item in top_rows {
            let passage = self.db.get_by_row_id(item.row_id)?;
            hits.push(SearchHit {
                score: item.score,
                passage,
            });
        }

        Ok(hits)
    }
}
