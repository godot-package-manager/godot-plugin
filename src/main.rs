mod config_file;
mod npm_manifest;
mod package;
mod utils;

use config_file::ConfigFile;

fn main() {
    let cfg = ConfigFile::parse_from_json();
    println!("{cfg:#?}");
}
