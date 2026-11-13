use crate::vector::DEFAULT_EMBEDDING_DIM;
use rusqlite::{params, Connection, OpenFlags, Result as SqlResult};
use serde::Serialize;
use serde_json::{Map, Value as JsonValue};
use std::collections::HashMap;
use std::path::Path;

/// Metadatos descriptivos del corpus cargado desde `corpus_meta`.
#[derive(Debug, Clone, Serialize)]
pub struct CorpusInfo {
    pub corpus_id: String,
    pub title: String,
    pub subtitle: String,
    pub search_hint: String,
    pub version: String,
    pub language: String,
    pub model_name: String,
    pub embedding_dim: usize,
    pub row_count: usize,
    pub sample_queries: Vec<String>,
}

/// Unidad textual genérica recuperada por `row_id`.
#[derive(Debug, Clone, Serialize)]
pub struct PassageRecord {
    pub row_id: usize,
    pub source_id: String,
    pub title: String,
    pub collection: String,
    pub group_name: String,
    pub text: String,
    pub metadata: JsonValue,
}

pub struct CorpusDb {
    conn: Connection,
    info: CorpusInfo,
}

impl CorpusDb {
    /// Apertura de la base de datos SQLite en modo solo lectura sobre el esquema
    /// universal (`passages` + `corpus_meta`).
    pub fn open<P: AsRef<Path>>(path: P) -> SqlResult<Self> {
        let conn = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;

        if !table_exists(&conn, "passages")? {
            return Err(rusqlite::Error::InvalidQuery);
        }

        let row_count: usize = conn.query_row("SELECT COUNT(*) FROM passages", [], |row| {
            let count: i64 = row.get(0)?;
            Ok(count.max(0) as usize)
        })?;

        let meta_map = load_meta_map(&conn)?;
        let info = build_corpus_info(&meta_map, row_count);

        Ok(Self { conn, info })
    }

    pub fn info(&self) -> &CorpusInfo {
        &self.info
    }

    /// Recuperación O(1) del pasaje por clave primaria entera.
    pub fn get_by_row_id(&self, row_id: usize) -> SqlResult<PassageRecord> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT row_id, source_id, title, collection, group_name, text, metadata_json
             FROM passages WHERE row_id = ?1",
        )?;

        stmt.query_row(params![row_id as i64], |row| {
            let raw_meta: String = row.get(6)?;
            let metadata = serde_json::from_str::<JsonValue>(&raw_meta)
                .unwrap_or_else(|_| JsonValue::Object(Map::new()));

            Ok(PassageRecord {
                row_id: row.get::<_, i64>(0)? as usize,
                source_id: row.get(1)?,
                title: row.get(2)?,
                collection: row.get(3)?,
                group_name: row.get(4)?,
                text: row.get(5)?,
                metadata,
            })
        })
    }
}

fn table_exists(conn: &Connection, table_name: &str) -> SqlResult<bool> {
    let exists: i64 = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)",
        params![table_name],
        |row| row.get(0),
    )?;
    Ok(exists != 0)
}

fn load_meta_map(conn: &Connection) -> SqlResult<HashMap<String, String>> {
    let mut map = HashMap::new();
    if !table_exists(conn, "corpus_meta")? {
        return Ok(map);
    }

    let mut stmt = conn.prepare("SELECT key, value FROM corpus_meta")?;
    let rows = stmt.query_map([], |row| {
        let key: String = row.get(0)?;
        let val: String = row.get(1)?;
        Ok((key, val))
    })?;

    for item in rows {
        let (k, v) = item?;
        map.insert(k, v);
    }
    Ok(map)
}

fn build_corpus_info(meta: &HashMap<String, String>, row_count: usize) -> CorpusInfo {
    let embedding_dim = meta
        .get("embedding_dim")
        .and_then(|v| v.trim().parse::<usize>().ok())
        .filter(|&d| d > 0)
        .unwrap_or(DEFAULT_EMBEDDING_DIM);

    let sample_queries = meta
        .get("sample_queries_json")
        .and_then(|raw| serde_json::from_str::<Vec<String>>(raw).ok())
        .unwrap_or_default();

    let get_or = |key: &str, default: &str| -> String {
        meta.get(key)
            .filter(|s| !s.trim().is_empty())
            .cloned()
            .unwrap_or_else(|| default.to_string())
    };

    CorpusInfo {
        corpus_id: get_or("corpus_id", "default"),
        title: get_or("title", "CITADOR SEMÁNTICO"),
        subtitle: get_or("subtitle", "¿Qué pasaje o idea deseas consultar?"),
        search_hint: get_or("search_hint", "Escribe una situación, concepto o pregunta..."),
        version: get_or("version", "1.0.0"),
        language: get_or("language", "es"),
        model_name: get_or(
            "model_name",
            "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        ),
        embedding_dim,
        row_count,
        sample_queries,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn corpus_info_falls_back_cleanly_for_empty_meta() {
        let empty = HashMap::new();
        let generic = build_corpus_info(&empty, 100);
        assert_eq!(generic.corpus_id, "default");
        assert_eq!(generic.embedding_dim, DEFAULT_EMBEDDING_DIM);
        assert_eq!(generic.row_count, 100);
        assert!(generic.sample_queries.is_empty());
    }
}
