use crate::package::Package;
use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug)]
pub struct ConfigFile {
    pub packages: Vec<Package>,
    // hooks: there are no hooks now
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
struct ConfigFileWrapper {
    packages: HashMap<String, String>,
}

impl ConfigFile {
    pub fn new() -> Self {
        Self::from(
            serde_json::from_str::<ConfigFileWrapper>(
                &std::fs::read_to_string("godot.package").unwrap(),
            )
            .unwrap(),
        )
    }

    fn add(&mut self, mut p: Package) {
        let cfg = p.get_config_file();
        if !cfg.dependencies.is_empty() {
            for mut dep in cfg.dependencies {
                dep.meta.indirect = true;
                self.add(dep.clone());
                p.meta.dependencies.push(dep);
            }
        }
        self.packages.push(p);
    }

    pub fn lock(&self) {}
}

impl From<ConfigFileWrapper> for ConfigFile {
    fn from(from: ConfigFileWrapper) -> Self {
        let mut cfg_file = ConfigFile { packages: vec![] };
        for (package, version) in from.packages {
            cfg_file.add(Package::new(package, version))
        }
        cfg_file
    }
}
