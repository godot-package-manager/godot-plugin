mod config_file;
mod npm;
mod package;

use crate::package::Package;
use clap::{ArgGroup, Parser};
use config_file::ConfigFile;
use std::fs::{create_dir, read_dir, remove_dir};
use std::io::Result;
use std::panic;
use std::path::Path;

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
    panic::set_hook(Box::new(|panic_info| {
        const RED: &str = "\x1b[1;31m";
        const RESET: &str = "\x1b[0m";
        match panic_info.location() {
            Some(s) => print!("{RED}err{RESET}@{}:{}:{}: ", s.file(), s.line(), s.column()),
            None => print!("{RED}err{RESET}: "),
        }
        match panic_info.payload().downcast_ref::<&str>() {
            Some(s) => println!("{s}"),
            None => match panic_info.payload().downcast_ref::<String>() {
                Some(s) => println!("{s}"),
                None => println!("unknown"),
            },
        }
    }));
    let args = Args::parse();
    if args.update {
        update();
    } else if args.purge {
        purge();
    }
}

fn update() {
    if !Path::new("./addons/").exists() {
        create_dir("./addons/").expect("Should be able to create addons folder");
    }
    let cfg = ConfigFile::new();
    if cfg.packages.is_empty() {
        println!("No packages to update (modify the \"godot.package\" file to add packages)");
        return;
    }
    println!("Update {} packages", cfg.packages.len());
    cfg.packages.iter().for_each(|p| p.download());
    cfg.lock();
}

fn recursive_delete_empty(dir: String) -> Result<()> {
    if read_dir(&dir)?.next().is_none() {
        return remove_dir(dir);
    }
    for p in read_dir(&dir)?.into_iter().filter_map(|e| {
        if let Ok(e) = e {
            if let Ok(t) = e.file_type() {
                if t.is_dir() {
                    return Some(e);
                };
            };
        };
        None
    }) {
        recursive_delete_empty(format!("{dir}/{}", p.file_name().to_string_lossy()))?;
    }
    Ok(())
}

fn purge() {
    let cfg = ConfigFile::new();
    let packages = cfg
        .packages
        .iter()
        .filter(|p| p.is_installed())
        .collect::<Vec<&Package>>();
    if packages.is_empty() {
        return if cfg.packages.is_empty() {
            println!("No packages to update (modify the \"godot.package\" file to add packages)")
        } else {
            println!("No packages installed(use \"gpm --update\" to install packages)")
        };
    }
    println!("Purge {} packages", packages.len());
    packages.into_iter().for_each(|p| p.purge());

    // run multiple times because the algorithm goes from top to bottom, stupidly.
    for _ in 0..3 {
        if let Err(e) = recursive_delete_empty("./addons".to_string()) {
            print!("Unable to remove empty directorys: {e}")
        }
    }
    cfg.lock();
}
