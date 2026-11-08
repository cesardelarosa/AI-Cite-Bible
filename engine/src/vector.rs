use std::cmp::{Ordering, Reverse};
use std::collections::BinaryHeap;
use std::fs::File;
use std::io::{self, Read};
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
    data: Vec<f32>,
    num_rows: usize,
}

impl VectorIndex {
    // Carga de la matriz binaria f32 en memoria contigua
    pub fn from_file<P: AsRef<Path>>(path: P) -> io::Result<Self> {
        let mut file = File::open(path)?;
        let byte_len = file.metadata()?.len() as usize;

        if byte_len % (EMBEDDING_DIM * std::mem::size_of::<f32>()) != 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "El tamano del binario no es multiplo exacto de 384 floats",
            ));
        }

        let num_floats = byte_len / std::mem::size_of::<f32>();
        let num_rows = num_floats / EMBEDDING_DIM;
        let mut data = vec![0.0f32; num_floats];

        let raw_slice = unsafe {
            std::slice::from_raw_parts_mut(data.as_mut_ptr() as *mut u8, byte_len)
        };
        file.read_exact(raw_slice)?;

        Ok(Self { data, num_rows })
    }

    // Busqueda de los K vectores con mayor similitud de coseno
    pub fn search_top_k(&self, query: &[f32], k: usize) -> Vec<ScoredRow> {
        assert_eq!(query.len(), EMBEDDING_DIM);
        if k == 0 || self.num_rows == 0 {
            return Vec::new();
        }

        let mut heap: BinaryHeap<Reverse<ScoredRow>> = BinaryHeap::with_capacity(k + 1);

        for (row_id, row_slice) in self.data.chunks_exact(EMBEDDING_DIM).enumerate() {
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
