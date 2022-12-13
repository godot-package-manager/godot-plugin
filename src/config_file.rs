use crate::package::Package;

use serde::Deserialize;
#[derive(Debug, Deserialize)]
pub struct ConfigFile {
    pub packages: Vec<Package>,
    // hooks: there are no hooks now
}

impl ConfigFile {
    pub fn parse_from_json() -> ConfigFile {
        serde_json::from_str::<ConfigFile>(&std::fs::read_to_string("godot.package").unwrap())
            .unwrap()
    }
}
