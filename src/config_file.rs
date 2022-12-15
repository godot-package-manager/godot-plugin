use crate::package::Package;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::write;

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

#[derive(Debug, Serialize)]
struct PackageLock {
    version: String,
    integrity: String,
}

impl ConfigFile {
    pub fn new() -> Self {
        Self::from(
            serde_json::from_str::<ConfigFileWrapper>(
                &std::fs::read_to_string("godot.package").expect("The config file should exist"),
            )
            .expect("The config file should be correct/valid JSON"),
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
        p.meta.dependencies.push(p.clone()); // i depend on myself
        self.packages.push(p);
    }

    pub fn lock(&self) {
        let mut lock = HashMap::<String, PackageLock>::new();
        for p in self.packages.iter() {
            if p.is_installed() {
                lock.insert(
                    p.name.clone(),
                    PackageLock::new(p.version.clone(), p.meta.npm_manifest.integrity.clone()),
                );
            };
        }
        let json = serde_json::to_string(&lock).unwrap();
        write("./godot.lock", json).expect("Writing lock file should work");
    }
}

impl PackageLock {
    fn new(v: String, i: String) -> Self {
        Self {
            version: v,
            integrity: i,
        }
    }
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
