use rusqlite::{params, Connection, Result as SqlResult};
use std::path::Path;

#[derive(Debug, Clone)]
pub struct VerseRecord {
    pub row_id: usize,
    pub canonical_id: String,
    pub book_name: String,
    pub testament: String,
    pub chapter: i32,
    pub verse: i32,
    pub text: String,
}

pub struct CorpusDb {
    conn: Connection,
}

impl CorpusDb {
    // Apertura de base de datos SQLite en modo solo lectura
    pub fn open<P: AsRef<Path>>(path: P) -> SqlResult<Self> {
        let conn = Connection::open(path)?;
        Ok(Self { conn })
    }

    // Recuperacion O(1) de versiculo por clave primaria entera
    pub fn get_by_row_id(&self, row_id: usize) -> SqlResult<VerseRecord> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT row_id, canonical_id, book_name, testament, chapter, verse, text
             FROM verses WHERE row_id = ?1",
        )?;

        stmt.query_row(params![row_id as i64], |row| {
            Ok(VerseRecord {
                row_id: row.get::<_, i64>(0)? as usize,
                canonical_id: row.get(1)?,
                book_name: row.get(2)?,
                testament: row.get(3)?,
                chapter: row.get(4)?,
                verse: row.get(5)?,
                text: row.get(6)?,
            })
        })
    }
}
