pub mod db;
pub mod encoder;
pub mod vector;

use db::{CorpusDb, VerseRecord};
use encoder::OnnxEncoder;
use std::error::Error;
use std::path::Path;
use vector::VectorIndex;

#[derive(Debug, Clone)]
pub struct SearchHit {
    pub score: f32,
    pub verse: VerseRecord,
}

pub struct SearchEngine {
    encoder: OnnxEncoder,
    index: VectorIndex,
    db: CorpusDb,
}

impl SearchEngine {
    // Carga de los 4 artefactos del motor offline
    pub fn new<P: AsRef<Path>>(
        db_path: P,
        bin_path: P,
        onnx_path: P,
        tokenizer_path: P,
    ) -> Result<Self, Box<dyn Error>> {
        let db = CorpusDb::open(db_path)?;
        let index = VectorIndex::from_file(bin_path)?;
        let encoder = OnnxEncoder::new(onnx_path, tokenizer_path)?;

        Ok(Self { encoder, index, db })
    }

    // Ejecucion del pipeline completo de consulta semantica
    pub fn search(&mut self, query: &str, top_k: usize) -> Result<Vec<SearchHit>, Box<dyn Error>> {
        let q_vec = self.encoder.encode(query)?;
        let top_rows = self.index.search_top_k(&q_vec, top_k);

        let mut hits = Vec::with_capacity(top_rows.len());
        for item in top_rows {
            let verse = self.db.get_by_row_id(item.row_id)?;
            hits.push(SearchHit {
                score: item.score,
                verse,
            });
        }

        Ok(hits)
    }
}
