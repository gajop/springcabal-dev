extern crate alloc;

mod catalog;
mod entry;
#[cfg(target_arch = "wasm32")]
mod model;
mod navigation;
#[cfg(target_arch = "wasm32")]
mod ui;
