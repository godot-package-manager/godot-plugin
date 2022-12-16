use crate::package::Package;
use serde::Deserialize;
use serde_json::Error;
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
    pub fn from_json(json: &String) -> Result<NpmConfig, Error> {
        let res = serde_json::from_str::<NpmConfigWrapper>(json);
        match res {
            Ok(wrap) => Ok(Self::from(wrap)),
            Err(err) => {
                let e: Result<NpmConfig, Error> = Result::Err(err);
                return e; // idk how to inline cast errors
            }
        }
    }

    pub fn new(dependencies: Vec<Package>) -> Self {
        Self { dependencies }
    }
}

impl From<NpmConfigWrapper> for NpmConfig {
    fn from(from: NpmConfigWrapper) -> Self {
        NpmConfig::new(
            from.dependencies
                .into_iter()
                .map(|(package, version)| Package::new(package, version))
                .collect(),
        )
    }
}
