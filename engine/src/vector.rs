use memmap2::Mmap;
use std::cmp::{Ordering, Reverse};
use std::collections::BinaryHeap;
use std::fs::File;
use std::io;
use std::path::Path;

pub const EMBEDDING_DIM: usize = 384;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ScoredRow {
    pub row_id: usize,
    pub score: f32,
}

impl Eq for ScoredRow {}

impl PartialOrd for ScoredRow {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        self.score.partial_cmp(&other.score)
    }
}

impl Ord for ScoredRow {
    fn cmp(&self, other: &Self) -> Ordering {
        self.partial_cmp(other).unwrap_or(Ordering::Equal)
    }
}

pub struct VectorIndex {
    mmap: Mmap,
    num_rows: usize,
}

impl VectorIndex {
    /// Carga e indexa la matriz binaria mapeándola en memoria virtual (Zero-Copy).
    ///
    /// Valida que:
    /// 1. El puntero base cumpla la alineación estricta de `f32` (4 bytes).
    /// 2. La longitud del archivo sea múltiplo exacto de `EMBEDDING_DIM * sizeof(f32)`.
    pub fn from_file<P: AsRef<Path>>(path: P) -> io::Result<Self> {
        let file = File::open(path)?;
        // SAFETY: Mapeo de solo lectura respaldado por el archivo.
        let mmap = unsafe { memmap2::MmapOptions::new().map(&file)? };
        let byte_len = mmap.len();

        let float_size = std::mem::size_of::<f32>();
        let float_align = std::mem::align_of::<f32>();

        // Verificación de alineación a 4 bytes requerida para castear a &[f32]
        let base_ptr = mmap.as_ptr() as usize;
        if base_ptr % float_align != 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "El puntero base de mmap ({:#x}) no cumple la alineación requerida de {} bytes para f32",
                    base_ptr, float_align
                ),
            ));
        }

        let row_bytes = EMBEDDING_DIM * float_size;
        if byte_len % row_bytes != 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "El tamaño del binario ({} bytes) no es múltiplo exacto de una fila de {} floats ({} bytes)",
                    byte_len, EMBEDDING_DIM, row_bytes
                ),
            ));
        }

        let num_floats = byte_len / float_size;
        let num_rows = num_floats / EMBEDDING_DIM;

        Ok(Self { mmap, num_rows })
    }

    /// Retorna una vista de slice inmutable &[f32] con tiempo de vida ligado a la estructura.
    #[inline]
    pub fn as_slice(&self) -> &[f32] {
        let num_floats = self.num_rows * EMBEDDING_DIM;
        // SAFETY:
        // - mmap garantiza memoria válida y continua durante el tiempo de vida de `self`.
        // - Se verificó la alineación a 4 bytes y la longitud en `from_file`.
        unsafe {
            std::slice::from_raw_parts(self.mmap.as_ptr() as *const f32, num_floats)
        }
    }

    // Busqueda de los K vectores con mayor similitud de coseno
    pub fn search_top_k(&self, query: &[f32], k: usize) -> Vec<ScoredRow> {
        assert_eq!(
            query.len(),
            EMBEDDING_DIM,
            "La dimensión de la consulta ({}) debe ser {}",
            query.len(),
            EMBEDDING_DIM
        );

        if k == 0 || self.num_rows == 0 {
            return Vec::new();
        }

        let data = self.as_slice();
        let mut heap: BinaryHeap<Reverse<ScoredRow>> = BinaryHeap::with_capacity(k + 1);

        for (row_id, row_slice) in data.chunks_exact(EMBEDDING_DIM).enumerate() {
            let score = dot_product_384(row_slice, query);

            if heap.len() < k {
                heap.push(Reverse(ScoredRow { row_id, score }));
            } else if let Some(&Reverse(min_item)) = heap.peek() {
                if score > min_item.score {
                    heap.pop();
                    heap.push(Reverse(ScoredRow { row_id, score }));
                }
            }
        }

        let mut results: Vec<ScoredRow> = heap.into_iter().map(|Reverse(item)| item).collect();
        results.sort_by(|a, b| b.cmp(a));
        results
    }

    pub fn len(&self) -> usize {
        self.num_rows
    }

    pub fn is_empty(&self) -> bool {
        self.num_rows == 0
    }
}

// Producto escalar de 384 dimensiones con acumuladores desacoplados para SIMD
#[inline(always)]
fn dot_product_384(a: &[f32], b: &[f32]) -> f32 {
    let mut acc0 = 0.0f32;
    let mut acc1 = 0.0f32;
    let mut acc2 = 0.0f32;
    let mut acc3 = 0.0f32;

    let a_chunks = a.chunks_exact(4);
    let b_chunks = b.chunks_exact(4);

    for (ca, cb) in a_chunks.zip(b_chunks) {
        acc0 = ca[0].mul_add(cb[0], acc0);
        acc1 = ca[1].mul_add(cb[1], acc1);
        acc2 = ca[2].mul_add(cb[2], acc2);
        acc3 = ca[3].mul_add(cb[3], acc3);
    }

    (acc0 + acc1) + (acc2 + acc3)
}
