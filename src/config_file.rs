use crate::package::Package;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::write;

#[derive(Debug, Default)]
pub struct ConfigFile {
    pub packages: Vec<Package>,
    // hooks: there are no hooks now
}
#[derive(Debug, Serialize)]
struct PackageLock {
    version: String,
    integrity: String,
}

impl ConfigFile {
    pub fn new() -> Self {
        #[derive(Debug, Deserialize, Default)]
        #[serde(default)]
        struct W {
            packages: HashMap<String, String>,
        }
        let mut cfg_file = ConfigFile::default();
        serde_json::from_str::<W>(
            &std::fs::read_to_string("godot.package").expect("The config file should exist"),
        )
        .expect("The config file should be correct/valid JSON")
        .packages
        .into_iter()
        .for_each(|(name, version)| cfg_file.add(Package::new(name, version)));
        cfg_file
    }

    fn add(&mut self, mut p: Package) {
        let cfg = p.get_config_file();
        cfg.dependencies.into_iter().for_each(|mut dep| {
            dep.meta.indirect = true;
            self.add(dep.clone());
            p.meta.dependencies.push(dep);
        });
        p.meta.dependencies.push(p.clone()); // i depend on myself
        self.packages.push(p);
    }

    pub fn lock(&self) {
        write(
            "./godot.lock",
            serde_json::to_string(
                &self
                    .packages
                    .iter()
                    .filter_map(|p| {
                        if p.is_installed() {
                            Some((p.name.clone(), PackageLock::new(p)))
                        } else {
                            None
                        }
                    })
                    .collect::<HashMap<String, PackageLock>>(),
            )
            .unwrap(),
        )
        .expect("Writing lock file should work");
    }
}

impl PackageLock {
    fn new(pkg: &Package) -> Self {
        Self {
            version: pkg.version.clone(),
            integrity: pkg.meta.npm_manifest.integrity.clone(),
        }
    }
}
