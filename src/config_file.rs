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
        let contents =
            &std::fs::read_to_string("godot.package").expect("The config file should exist");
        #[rustfmt::skip]
        let cfg: W = if let Ok(w) = deser_hjson::from_str(contents) { w }
                     else if let Ok(w) = serde_yaml::from_str(contents) { w }
                     else if let Ok(w) = toml::from_str(contents) { w }
                     else { panic!("Failed to parse the config file") };
        let mut cfg_file = ConfigFile::default();
        cfg_file.packages = cfg
            .packages
            .into_iter()
            .map(|(name, version)| Package::new(name, version))
            .collect();
        cfg_file.packages.sort();
        cfg_file
    }

    pub fn lock(&self) {
        write(
            "./godot.lock",
            serde_json::to_string(
                &self
                    .collect()
                    .into_iter()
                    .filter_map(|p| {
                        p.is_installed()
                            .then_some((p.name.clone(), PackageLock::new(p)))
                    })
                    .collect::<HashMap<String, PackageLock>>(),
            )
            .unwrap(),
        )
        .expect("Writing lock file should work");
    }

    fn _for_each(pkgs: &[Package], mut cb: impl FnMut(&Package)) {
        fn inner(pkgs: &[Package], cb: &mut impl FnMut(&Package)) {
            for p in pkgs {
                cb(p);
                if p.has_deps() {
                    inner(&p.meta.dependencies, cb);
                }
            }
        }
        inner(pkgs, &mut cb);
    }

    pub fn for_each(&self, cb: impl FnMut(&Package)) {
        Self::_for_each(&self.packages, cb)
    }

    pub fn collect(&self) -> Vec<Package> {
        let mut pkgs: Vec<Package> = vec![];
        self.for_each(|p: &Package| pkgs.push(p.clone()));
        pkgs
    }
}

impl PackageLock {
    fn new(pkg: Package) -> Self {
        Self {
            version: pkg.version,
            integrity: pkg.meta.npm_manifest.integrity,
        }
    }
}
