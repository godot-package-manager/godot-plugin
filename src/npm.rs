use crate::package::Package;
use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Deserialize, Clone)]
pub struct NpmManifest {
    pub tarball: String,
    pub integrity: String,
}

#[derive(Debug)]
pub struct NpmConfig {
    pub dependencies: Vec<Package>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct NpmConfigWrapper {
    dependencies: HashMap<String, String>,
}

impl NpmConfig {
    pub fn from_json(json: &String) -> NpmConfig {
        Self::from(serde_json::from_str::<NpmConfigWrapper>(json).unwrap())
    }
}

impl From<NpmConfigWrapper> for NpmConfig {
    fn from(from: NpmConfigWrapper) -> Self {
        let mut cfg_file = NpmConfig {
            dependencies: vec![],
        };
        for (package, version) in from.dependencies {
            cfg_file.dependencies.push(Package::new(package, version));
        }
        cfg_file
    }
}
