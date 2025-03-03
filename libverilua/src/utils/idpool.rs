use libc::{c_int, c_void};
use rand::prelude::SliceRandom;

#[repr(C)]
pub struct IDPoolForLua {
    pool: Vec<c_int>,
    top: usize,
}

#[unsafe(no_mangle)]
pub extern "C" fn idpool_init(size: c_int, shuffle: c_int) -> *mut c_void {
    let mut idpool = Box::new(IDPoolForLua {
        pool: (1..=size).rev().collect(),
        top: (size - 1) as usize,
    });

    if shuffle >= 1 {
        idpool.pool.shuffle(&mut rand::rng());
    }

    Box::into_raw(idpool) as *mut c_void
}

#[unsafe(no_mangle)]
pub extern "C" fn idpool_alloc(idpool_void: *mut c_void) -> c_int {
    let idpool = unsafe { &mut *(idpool_void as *mut IDPoolForLua) };
    if idpool.top < idpool.pool.len() {
        let id = idpool.pool[idpool.top];
        idpool.top += 1;
        id
    } else {
        panic!("IDPool is empty! size => {}", idpool.pool.len());
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn idpool_release(idpool_void: *mut c_void, id: c_int) {
    let idpool = unsafe { &mut *(idpool_void as *mut IDPoolForLua) };
    if id > idpool.pool.len() as c_int {
        panic!(
            "The released id is out of range! id => {}, size => {}",
            id,
            idpool.pool.len()
        );
    }
    idpool.top -= 1;
    idpool.pool[idpool.top] = id;
}

#[unsafe(no_mangle)]
pub extern "C" fn idpool_pool_size(idpool_void: *mut c_void) -> c_int {
    let idpool = unsafe { &*(idpool_void as *mut IDPoolForLua) };
    (idpool.pool.len() - idpool.top) as c_int
}

#[unsafe(no_mangle)]
pub extern "C" fn idpool_free(idpool_void: *mut c_void) {
    let _idpool = unsafe { Box::from_raw(idpool_void as *mut IDPoolForLua) };
}
