mod config_file;
mod npm_manifest;
mod package;
mod utils;

use config_file::ConfigFile;
use std::fs::create_dir;
use std::path::Path;

fn main() {
    update();
}

fn update() {
    if !Path::new("./addons/").exists() {
        create_dir("./addons/").expect("Failed to create ./addons/");
    }
    let cfg = ConfigFile::parse_from_json();
    println!("Update {} packages", cfg.packages.len());
    for package in cfg.packages.iter() {
        println!("{package:#?}");
        package.download();
    }
    cfg.lock();
}
