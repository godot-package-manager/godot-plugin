mod config_file;
mod npm;
mod package;

use config_file::ConfigFile;
use std::fs::create_dir;
use std::path::Path;

use clap::{ArgGroup, Parser};

#[derive(Parser, Debug)]
#[command(name = "gpm")]
#[command(about = "A package manager for godot", long_about = None)]
#[clap(group(
    ArgGroup::new("actions")
        .required(true)
        .args(&["update", "purge"]),
    ))]
struct Args {
    #[clap(long, short, action)]
    update: bool,
    #[clap(long, short, action)]
    purge: bool,
}

fn main() {
    update();
}

fn update() {
    let args = Args::parse();
    if args.update {
        if !Path::new("./addons/").exists() {
            create_dir("./addons/").expect("Failed to create ./addons/");
        }
        let cfg = ConfigFile::new();
        println!("Update {} packages", cfg.packages.len());
        for package in cfg.packages.iter() {
            package.download();
        }
        cfg.lock();
        return;
    }
    if args.purge {}
}
