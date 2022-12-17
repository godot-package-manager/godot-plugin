use crate::npm::*;
use core::cmp::Ordering;
use flate2::read::GzDecoder;
use regex::{Captures, Regex};
use serde::Deserialize;
use std::fs::{create_dir_all, read_dir, read_to_string, remove_dir_all, write};
use std::io;
use std::path::{Component::Normal, Path, PathBuf};
use std::{collections::HashMap, fmt};
use tar::Archive;

const REGISTRY: &str = "https://registry.npmjs.org";

#[derive(Clone, Eq, PartialEq, Ord)]
pub struct Package {
    pub name: String,
    pub version: String,
    pub meta: PackageMeta,
}

#[derive(Clone, Eq, PartialEq, Ord)]
pub struct PackageMeta {
    pub npm_manifest: NpmManifest,
    pub dependencies: Vec<Package>,
    pub indirect: bool,
}

impl PartialOrd for Package {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        return Some(self.name.cmp(&other.name));
    }
}
impl PartialOrd for PackageMeta {
    fn partial_cmp(&self, _other: &Self) -> Option<Ordering> {
        return Some(Ordering::Equal);
    }
}

impl Package {
    pub fn has_deps(&self) -> bool {
        !self.meta.dependencies.is_empty()
    }

    pub fn new(name: String, version: String) -> Package {
        let mut p = Package {
            meta: PackageMeta {
                indirect: false,
                npm_manifest: Self::get_manifest(&name, &version),
                dependencies: vec![],
            },
            name,
            version,
        };
        p.get_deps();
        p
    }

    pub fn to_string(&self) -> String {
        format!("{}@{}", self.name, self.version)
    }

    pub fn is_installed(&self) -> bool {
        Path::new(&self.download_dir()).exists()
    }

    pub fn purge(&self) {
        if self.is_installed() {
            remove_dir_all(self.download_dir()).expect("Should be able to remove download dir");
        }
    }

    pub fn download(&self) {
        println!("Downloading {self}");
        self.purge();
        let resp = ureq::get(&self.meta.npm_manifest.tarball)
            .call()
            .expect("Tarball download should work");

        let len = resp
            .header("Content-Length")
            .expect("Tarball should specify content length")
            .parse()
            .expect("Tarball content length should be a number");

        let mut bytes: Vec<u8> = Vec::with_capacity(len);
        resp.into_reader()
            .read_to_end(&mut bytes)
            .expect("Tarball should be bytes");

        /// tar xzf archive --strip-components=1 --directory=P
        pub fn unpack<P, R>(mut archive: Archive<R>, dst: P) -> io::Result<()>
        where
            P: AsRef<Path>,
            R: io::Read,
        {
            if dst.as_ref().symlink_metadata().is_err() {
                create_dir_all(&dst)?;
            }

            for entry in archive.entries()? {
                let mut entry = entry?;
                let path: PathBuf = entry
                    .path()?
                    .components()
                    .skip(1) // strip top-level directory
                    .filter(|c| matches!(c, Normal(_))) // prevent traversal attacks
                    .collect();
                entry.unpack(dst.as_ref().join(path))?;
            }
            Ok(())
        }

        unpack(
            Archive::new(GzDecoder::new(&bytes[..])),
            Path::new(&self.download_dir()),
        )
        .expect("Tarball should unpack");

        self.modify();
    }

    pub fn get_config_file(&self) -> NpmConfig {
        NpmConfig::from_json(
            &ureq::get(&format!(
                "https://cdn.jsdelivr.net/npm/{}@{}/package.json",
                self.name, self.version,
            ))
            .call()
            .expect("Getting the package config file should not fail")
            .into_string()
            .expect("The package config file should be valid text"),
        )
        .expect("The package config file should be correct/valid JSON")
    }
}

impl Package {
    fn get_manifest(name: &String, version: &String) -> NpmManifest {
        #[derive(Debug, Deserialize)]
        struct NpmManifestWrapper {
            pub dist: NpmManifest,
        }
        let resp = ureq::get(&format!("{}/{}/{}", REGISTRY, name, version))
            .call()
            .expect("Getting the package manifest file should not fail")
            .into_string()
            .expect("The package manifest file should be valid text");
        if resp == "\"Not Found\"" {
            panic!("The package {name}@{version} was not found")
        } else if resp == format!("\"version not found: {version}\"") {
            panic!("The package {name} exists, but version '{version}' was not found")
        }
        let npm_manifest = serde_json::from_str::<NpmManifestWrapper>(&resp)
            .expect("The package manifest file should be correct/valid JSON")
            .dist;
        npm_manifest
    }

    fn download_dir(&self) -> String {
        if self.meta.indirect {
            format!("./addons/__gpm_deps/{}/{}", self.name, self.version)
        } else {
            format!("./addons/{}", self.name)
        }
    }
}

// package modification block
fn absolute_to_relative(path: &String, cwd: &String) -> String {
    let mut common = cwd.clone();
    let mut result = String::from("");
    while path.trim_start_matches(&common) == path {
        common = Path::new(&common)
            .parent()
            .unwrap()
            .as_os_str()
            .to_string_lossy()
            .to_string();
        result = if result.is_empty() {
            String::from("..")
        } else {
            format!("../{result}")
        };
    }
    let uncommon = path.trim_start_matches(&common);
    if !(result.is_empty() && uncommon.is_empty()) {
        result.push_str(uncommon);
    } else if !uncommon.is_empty() {
        result = uncommon[1..].into();
    }
    result
}

impl Package {
    fn get_deps(&mut self) -> &Vec<Package> {
        let cfg = self.get_config_file();
        cfg.dependencies.into_iter().for_each(|mut dep| {
            dep.meta.indirect = true;
            self.meta.dependencies.push(dep);
        });
        &self.meta.dependencies
    }

    fn modify_script_loads(&self, t: &String, cwd: &String) -> String {
        lazy_static::lazy_static! {
            static ref SCRIPT_LOAD_R: Regex = Regex::new("(pre)?load\\([\"']([^)]+)['\"]\\)").unwrap();
        }
        SCRIPT_LOAD_R
            .replace_all(&t, |c: &Captures| {
                format!(
                    "{}load('{}')",
                    if c.get(1).is_some() { "pre" } else { "" },
                    self.modify_load(
                        String::from(c.get(2).unwrap().as_str().trim_start_matches("res://")),
                        c.get(1).is_some(),
                        cwd
                    )
                )
            })
            .to_string()
    }
    fn modify_tres_loads(&self, t: &String, cwd: &String) -> String {
        lazy_static::lazy_static! {
            static ref TRES_LOAD_R: Regex = Regex::new("[ext_resource path=\"([^\"]+)\"").unwrap();
        }
        TRES_LOAD_R
            .replace_all(&t, |c: &Captures| {
                format!(
                    "[ext_resource path=\"{}\"",
                    self.modify_load(
                        String::from(c.get(1).unwrap().as_str().trim_start_matches("res://")),
                        false,
                        cwd
                    )
                )
            })
            .to_string()
    }

    fn modify_load(&self, path: String, relative_allowed: bool, cwd: &String) -> String {
        let path_p = Path::new(&path);
        if path_p.exists() || Path::new(cwd).join(path_p).exists() {
            if relative_allowed {
                let rel = absolute_to_relative(&path, cwd);
                if path.len() > rel.len() {
                    return rel;
                }
            }
            return format!("res://{path}");
        }
        if let Some(c) = path_p.components().nth(1) {
            let mut cfg = HashMap::<String, String>::new();
            for pkg in &self.meta.dependencies {
                cfg.insert(pkg.name.clone(), pkg.download_dir());
                if let Some((_, s)) = pkg.name.split_once("/") {
                    cfg.insert(String::from(s), pkg.download_dir()); // unscoped (@ben/cli => cli) (for compat)
                }
            }
            cfg.insert(self.name.clone(), self.download_dir());
            if let Some((_, s)) = self.name.split_once("/") {
                cfg.insert(String::from(s), self.download_dir());
            }
            if let Some(path) = cfg.get(&String::from(c.as_os_str().to_str().unwrap())) {
                let p = format!("res://{path}");
                if relative_allowed {
                    let rel = absolute_to_relative(path, cwd);
                    if p.len() > rel.len() {
                        return rel;
                    }
                }
                return p;
            }
        };
        println!("Could not find path for {}", path);
        return format!("res://{path}");
    }

    fn recursive_modify(&self, dir: String, deps: &Vec<Package>) -> io::Result<()> {
        for entry in read_dir(&dir)? {
            let p = entry?;
            if p.path().is_dir() {
                self.recursive_modify(
                    format!("{dir}/{}", p.file_name().into_string().unwrap()),
                    deps,
                )?;
                continue;
            }

            #[derive(PartialEq, Debug)]
            enum Type {
                TextResource,
                GDScript,
            }
            if let Some(e) = p.path().extension() {
                let t = if e == "tres" || e == "tscn" {
                    Type::TextResource
                } else if e == "gd" || e == "gdscript" {
                    Type::GDScript
                } else {
                    continue;
                };
                let text = read_to_string(p.path())?;
                write(
                    p.path(),
                    match t {
                        Type::TextResource => self.modify_tres_loads(&text, &dir),
                        Type::GDScript => self.modify_script_loads(&text, &dir),
                    },
                )?;
            }
        }
        Ok(())
    }

    pub fn modify(&self) {
        if self.is_installed() == false {
            panic!("Attempting to modify a package that is not installed");
        }
        if let Err(e) = self.recursive_modify(self.download_dir(), &self.meta.dependencies) {
            println!("Modification of {self} yielded error {e}");
        }
    }
}

impl fmt::Display for Package {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.to_string())
    }
}

impl fmt::Debug for Package {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.to_string())
    }
}
