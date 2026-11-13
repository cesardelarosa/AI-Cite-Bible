use crate::SearchEngine;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

/// Convierte un puntero C `*const c_char` a `&str`, devolviendo `None` si es nulo o UTF-8 inválido.
///
/// # Safety
/// Si `ptr` no es nulo, debe apuntar a una cadena terminada en byte nulo válida durante `'a`.
unsafe fn cstr_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok()
}

/// Inicializa una instancia de `SearchEngine` y transfiere la propiedad al llamador C/FFI.
///
/// Retorna `NULL` si algún puntero es nulo, contiene UTF-8 inválido o falla la carga de artefactos.
/// La instancia devuelta debe liberarse con [`engine_destroy`].
///
/// # Safety
/// Todos los punteros no nulos deben apuntar a cadenas C válidas terminadas en `\0`.
#[no_mangle]
pub unsafe extern "C" fn engine_init(
    db_path: *const c_char,
    bin_path: *const c_char,
    onnx_path: *const c_char,
    tokenizer_path: *const c_char,
) -> *mut SearchEngine {
    let (Some(db), Some(bin), Some(onnx), Some(tok)) = (
        cstr_to_str(db_path),
        cstr_to_str(bin_path),
        cstr_to_str(onnx_path),
        cstr_to_str(tokenizer_path),
    ) else {
        return ptr::null_mut();
    };

    let result = catch_unwind(AssertUnwindSafe(|| SearchEngine::new(db, bin, onnx, tok)));

    match result {
        Ok(Ok(engine)) => Box::into_raw(Box::new(engine)),
        Ok(Err(_)) | Err(_) => ptr::null_mut(),
    }
}

/// Devuelve los metadatos del corpus activo (`CorpusInfo`) serializados en JSON.
///
/// El puntero `*mut c_char` devuelto debe liberarse con [`engine_free_string`].
/// Retorna `NULL` si `engine` es nulo o falla la serialización.
///
/// # Safety
/// `engine` debe ser nulo o un puntero válido devuelto por [`engine_init`] y no destruido.
#[no_mangle]
pub unsafe extern "C" fn engine_corpus_info(engine: *const SearchEngine) -> *mut c_char {
    if engine.is_null() {
        return ptr::null_mut();
    }

    let engine_ref = &*engine;
    let result = catch_unwind(AssertUnwindSafe(|| {
        let json = serde_json::to_string(engine_ref.corpus_info()).ok()?;
        CString::new(json).ok()
    }));

    match result {
        Ok(Some(c_str)) => c_str.into_raw(),
        Ok(None) | Err(_) => ptr::null_mut(),
    }
}

/// Ejecuta una búsqueda semántica inmutable sobre `&(*engine)` y serializa el resultado a JSON.
///
/// Retorna un puntero `*mut c_char` terminado en `\0` que debe liberarse con [`engine_free_string`],
/// o `NULL` si algún puntero es nulo, la consulta es UTF-8 inválida o falla la búsqueda/serialización.
///
/// # Safety
/// - `engine` debe ser nulo o un puntero válido devuelto por [`engine_init`] y no destruido.
/// - El llamador debe evitar llamadas concurrentes sobre el mismo `engine` mientras `CorpusDb` no sea `Sync`.
/// - `query` debe ser nulo o apuntar a una cadena C válida terminada en `\0`.
#[no_mangle]
pub unsafe extern "C" fn engine_search(
    engine: *const SearchEngine,
    query: *const c_char,
    top_k: usize,
) -> *mut c_char {
    if engine.is_null() {
        return ptr::null_mut();
    }

    let Some(query_str) = cstr_to_str(query) else {
        return ptr::null_mut();
    };

    let engine_ref = &*engine;
    let safe_top_k = top_k.min(100_000);

    let result = catch_unwind(AssertUnwindSafe(|| {
        let hits = engine_ref.search(query_str, safe_top_k).ok()?;
        let json = serde_json::to_string(&hits).ok()?;
        CString::new(json).ok()
    }));

    match result {
        Ok(Some(c_str)) => c_str.into_raw(),
        Ok(None) | Err(_) => ptr::null_mut(),
    }
}

/// Libera una cadena JSON asignada previamente por [`engine_search`] o [`engine_corpus_info`]
/// mediante `CString::from_raw`.
///
/// No realiza ninguna operación si `ptr` es `NULL`.
///
/// # Safety
/// Si `ptr` no es nulo, debe haber sido devuelto por Rust vía `CString::into_raw`
/// y no haberse liberado previamente.
#[no_mangle]
pub unsafe extern "C" fn engine_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

/// Destruye una instancia de `SearchEngine` asignada previamente por [`engine_init`] mediante `Box::from_raw`.
///
/// No realiza ninguna operación si `engine` es `NULL`.
///
/// # Safety
/// Si `engine` no es nulo, debe haber sido devuelto por [`engine_init`], no debe haber llamadas activas
/// sobre él y no debe haber sido destruido previamente.
#[no_mangle]
pub unsafe extern "C" fn engine_destroy(engine: *mut SearchEngine) {
    if engine.is_null() {
        return;
    }
    drop(Box::from_raw(engine));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::PassageRecord;
    use crate::SearchHit;
    use serde_json::json;

    #[test]
    fn null_pointers_are_handled_safely() {
        unsafe {
            let valid = CString::new("consulta").unwrap();

            assert!(
                engine_init(ptr::null(), valid.as_ptr(), valid.as_ptr(), valid.as_ptr()).is_null()
            );
            assert!(
                engine_init(valid.as_ptr(), ptr::null(), valid.as_ptr(), valid.as_ptr()).is_null()
            );
            assert!(
                engine_init(valid.as_ptr(), valid.as_ptr(), ptr::null(), valid.as_ptr()).is_null()
            );
            assert!(
                engine_init(valid.as_ptr(), valid.as_ptr(), valid.as_ptr(), ptr::null()).is_null()
            );

            assert!(engine_corpus_info(ptr::null()).is_null());
            assert!(engine_search(ptr::null(), valid.as_ptr(), 5).is_null());
            assert!(engine_search(ptr::null(), ptr::null(), 5).is_null());

            engine_free_string(ptr::null_mut());
            engine_destroy(ptr::null_mut());
        }
    }

    #[test]
    fn invalid_utf8_query_or_paths_return_null() {
        unsafe {
            const BAD_UTF8: &[u8] = b"\xFF\xFE\0";
            let bad_ptr = BAD_UTF8.as_ptr().cast::<c_char>();
            let valid = CString::new("ruta").unwrap();

            assert!(
                engine_init(bad_ptr, valid.as_ptr(), valid.as_ptr(), valid.as_ptr()).is_null()
            );
            assert!(cstr_to_str(bad_ptr).is_none());
        }
    }

    #[test]
    fn search_hit_serializes_to_expected_json_and_frees_string() {
        let hits = vec![SearchHit {
            score: 0.95,
            passage: PassageRecord {
                row_id: 42,
                source_id: "Sal 23:1".to_string(),
                title: "Salmos 23:1".to_string(),
                collection: "Salmos".to_string(),
                group_name: "Antiguo Testamento".to_string(),
                text: "Jehová es mi pastor; nada me faltará.".to_string(),
                metadata: json!({"chapter": 23, "verse": 1}),
            },
        }];

        let json_str = serde_json::to_string(&hits).expect("serialization should succeed");
        let parsed: serde_json::Value = serde_json::from_str(&json_str).expect("valid JSON");
        assert_eq!(parsed[0]["passage"]["source_id"], "Sal 23:1");
        assert_eq!(parsed[0]["passage"]["title"], "Salmos 23:1");
        assert_eq!(parsed[0]["passage"]["metadata"]["chapter"], 23);

        let raw = CString::new(json_str).unwrap().into_raw();
        unsafe {
            engine_free_string(raw);
        }
    }
}
