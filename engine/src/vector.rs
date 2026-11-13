use memmap2::Mmap;
use std::cmp::{Ordering, Reverse};
use std::collections::BinaryHeap;
use std::fs::File;
use std::io;
use std::path::Path;

pub const DEFAULT_EMBEDDING_DIM: usize = 384;

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
    embedding_dim: usize,
}

impl VectorIndex {
    /// Carga la matriz binaria usando la dimensión por defecto (384).
    pub fn from_file<P: AsRef<Path>>(path: P) -> io::Result<Self> {
        Self::from_file_with_dim(path, DEFAULT_EMBEDDING_DIM)
    }

    /// Carga e indexa la matriz binaria mapeándola en memoria virtual (Zero-Copy)
    /// para cualquier dimensión de embedding positiva.
    ///
    /// Valida que:
    /// 1. `embedding_dim > 0`.
    /// 2. El puntero base cumpla la alineación estricta de `f32` (4 bytes).
    /// 3. La longitud del archivo sea múltiplo exacto de `embedding_dim * sizeof(f32)`.
    pub fn from_file_with_dim<P: AsRef<Path>>(path: P, embedding_dim: usize) -> io::Result<Self> {
        if embedding_dim == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "La dimensión de embeddings debe ser mayor que 0",
            ));
        }

        let file = File::open(path)?;
        // SAFETY: Mapeo de solo lectura respaldado por el descriptor del archivo.
        let mmap = unsafe { memmap2::MmapOptions::new().map(&file)? };
        let byte_len = mmap.len();

        let float_size = std::mem::size_of::<f32>();
        let float_align = std::mem::align_of::<f32>();

        // Verificación de alineación a 4 bytes requerida para interpretar como &[f32].
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

        let row_bytes = embedding_dim
            .checked_mul(float_size)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "Dimensión fuera de rango"))?;

        if byte_len % row_bytes != 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "El tamaño del binario ({} bytes) no es múltiplo exacto de una fila de {} floats ({} bytes)",
                    byte_len, embedding_dim, row_bytes
                ),
            ));
        }

        let num_floats = byte_len / float_size;
        let num_rows = num_floats / embedding_dim;

        Ok(Self {
            mmap,
            num_rows,
            embedding_dim,
        })
    }

    /// Retorna una vista de slice inmutable &[f32] con tiempo de vida ligado a la estructura.
    #[inline]
    pub fn as_slice(&self) -> &[f32] {
        let num_floats = self.num_rows * self.embedding_dim;
        // SAFETY:
        // - mmap garantiza memoria válida y continua durante el tiempo de vida de `self`.
        // - Se verificó la alineación a 4 bytes y la longitud exacta en `from_file_with_dim`.
        unsafe { std::slice::from_raw_parts(self.mmap.as_ptr() as *const f32, num_floats) }
    }

    #[inline]
    pub fn embedding_dim(&self) -> usize {
        self.embedding_dim
    }

    /// Búsqueda de los K vectores con mayor similitud de coseno (producto escalar L2-normalizado).
    pub fn search_top_k(&self, query: &[f32], k: usize) -> Vec<ScoredRow> {
        assert_eq!(
            query.len(),
            self.embedding_dim,
            "La dimensión de la consulta ({}) debe ser {}",
            query.len(),
            self.embedding_dim
        );

        if k == 0 || self.num_rows == 0 {
            return Vec::new();
        }

        let data = self.as_slice();
        let cap = k.min(self.num_rows).saturating_add(1);
        let mut heap: BinaryHeap<Reverse<ScoredRow>> = BinaryHeap::with_capacity(cap);

        for (row_id, row_slice) in data.chunks_exact(self.embedding_dim).enumerate() {
            let score = dot_product(row_slice, query);

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

/// Producto escalar con 4 acumuladores desacoplados para auto-vectorización SIMD
/// y soporte para dimensiones arbitrarias.
#[inline(always)]
fn dot_product(a: &[f32], b: &[f32]) -> f32 {
    let mut acc0 = 0.0f32;
    let mut acc1 = 0.0f32;
    let mut acc2 = 0.0f32;
    let mut acc3 = 0.0f32;

    let a_chunks = a.chunks_exact(4);
    let b_chunks = b.chunks_exact(4);
    let a_rem = a_chunks.remainder();
    let b_rem = b_chunks.remainder();

    for (ca, cb) in a_chunks.zip(b_chunks) {
        acc0 = ca[0].mul_add(cb[0], acc0);
        acc1 = ca[1].mul_add(cb[1], acc1);
        acc2 = ca[2].mul_add(cb[2], acc2);
        acc3 = ca[3].mul_add(cb[3], acc3);
    }

    let mut rem = 0.0f32;
    for (&x, &y) in a_rem.iter().zip(b_rem.iter()) {
        rem = x.mul_add(y, rem);
    }

    ((acc0 + acc1) + (acc2 + acc3)) + rem
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dot_product_supports_384_and_non_multiple_of_4() {
        let a = vec![1.0f32; 384];
        let b = vec![0.5f32; 384];
        assert!((dot_product(&a, &b) - 192.0).abs() < 1e-5);

        let c = [1.0f32, 2.0, 3.0, 4.0, 5.0];
        let d = [2.0f32, 0.5, 1.0, 0.25, 3.0];
        // 2 + 1 + 3 + 1 + 15 = 22
        assert!((dot_product(&c, &d) - 22.0).abs() < 1e-6);
    }
}
