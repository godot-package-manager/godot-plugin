use crate::npm::*;
use flate2::read::GzDecoder;
use regex::{Captures, Regex};
use serde::de::{self, Deserializer, MapAccess, SeqAccess, Visitor};
use serde::Deserialize;
use std::fs::{create_dir_all, read_dir, read_to_string, remove_dir_all, write};
use std::io;
use std::path::{Component::Normal, Path, PathBuf};
use std::{collections::HashMap, fmt};
use tar::Archive;

const REGISTRY: &str = "https://registry.npmjs.org";

#[derive(Clone)]
pub struct Package {
    pub name: String,
    pub version: String,
    pub meta: PackageMeta,
}

#[derive(Clone)]
pub struct PackageMeta {
    pub npm_manifest: NpmManifest,
    pub dependencies: Vec<Package>,
    pub indirect: bool,
}

impl Package {
    pub fn new(name: String, version: String) -> Package {
        Package {
            meta: PackageMeta {
                indirect: false,
                npm_manifest: Self::get_manifest(&name, &version),
                dependencies: vec![],
            },
            name,
            version,
        }
    }

    pub fn to_string(&self) -> String {
        format!("{}@{}", self.name, self.version)
    }

    pub fn is_installed(&self) -> bool {
        Path::new(&self.download_dir()).exists()
    }

    pub fn download(&self) {
        println!("Downloading {self}");
        if self.is_installed() {
            remove_dir_all(self.download_dir()).expect("Should be able to remove download dir");
        }

        let bytes = reqwest::blocking::get(&self.meta.npm_manifest.tarball)
            .expect("Tarball download should work")
            .bytes()
            .expect("Tarball should be bytes")
            .to_vec();

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

    pub fn modify(&self) {
        lazy_static::lazy_static! {
            static ref SCRIPT_LOAD_R: Regex = Regex::new("(pre)?load\\([\"']([^)]+)['\"]\\)").unwrap();
            static ref TRES_LOAD_R: Regex = Regex::new("[ext_resource path=\"([^\"]+)\"").unwrap();
        }
        // this fn took a hour of battling with the compiler
        fn modify_load(
            deps: &Vec<Package>,
            path: String,
            relative_allowed: bool,
            cwd: &String,
        ) -> String {
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
            let path_p = Path::new(&path);
            if path_p.exists() || Path::new(cwd).join(path_p).exists() {
                if relative_allowed {
                    let rel = absolute_to_relative(&path, cwd);
                    if path.len() > rel.len() {
                        return rel;
                    }
                }
                return format!("res://path");
            }
            if let Some(c) = path_p.components().nth(1) {
                let mut cfg = HashMap::<String, String>::new();
                for pkg in deps {
                    cfg.insert(pkg.name.clone(), pkg.download_dir());
                    if let Some(s) = pkg.name.split_once("/") {
                        cfg.insert(String::from(s.1), pkg.download_dir()); // unscoped (@ben/cli => cli) (for compat)
                    }
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
        fn modify_script_loads(deps: &Vec<Package>, t: &String, cwd: &String) -> String {
            SCRIPT_LOAD_R
                .replace_all(&t, |c: &Captures| {
                    format!(
                        "{}load('{}')",
                        if c.get(1).is_some() { "pre" } else { "" },
                        modify_load(
                            deps,
                            String::from(c.get(2).unwrap().as_str().trim_start_matches("res://")),
                            c.get(1).is_some(),
                            cwd
                        )
                    )
                })
                .to_string()
        }
        fn modify_tres_loads(deps: &Vec<Package>, t: &String, cwd: &String) -> String {
            TRES_LOAD_R
                .replace_all(&t, |c: &Captures| {
                    format!(
                        "[ext_resource path=\"{}\"",
                        modify_load(
                            deps,
                            String::from(c.get(1).unwrap().as_str().trim_start_matches("res://")),
                            false,
                            cwd
                        )
                    )
                })
                .to_string()
        }
        if self.is_installed() == false {
            panic!("Attempting to modify a package that is not installed");
        }
        if let Err(e) = recurse(self.download_dir(), &self.meta.dependencies) {
            println!("Modification of {self} yielded error {e}");
        }

        fn recurse(dir: String, deps: &Vec<Package>) -> io::Result<()> {
            for entry in read_dir(&dir)? {
                let p = entry?;
                if p.path().is_dir() {
                    recurse(
                        format!("{dir}/{}", p.file_name().into_string().unwrap()),
                        deps,
                    )?;
                    continue;
                }

                #[derive(PartialEq, Debug)]
                enum Type {
                    TextResource,
                    GDScript,
                    None,
                }
                if let Some(e) = p.path().extension() {
                    let t = if e == "tres" || e == "tscn" {
                        Type::TextResource
                    } else if e == "gd" || e == "gdscript" {
                        Type::GDScript
                    } else {
                        Type::None
                    };
                    if t == Type::None {
                        continue;
                    }
                    let text = read_to_string(p.path())?;
                    write(
                        p.path(),
                        match t {
                            Type::TextResource => modify_tres_loads(deps, &text, &dir),
                            Type::GDScript => modify_script_loads(deps, &text, &dir),
                            Type::None => text, // this should never occur
                        },
                    )?;
                }
            }
            Ok(())
        }
    }

    pub fn get_config_file(&self) -> NpmConfig {
        NpmConfig::from_json(
            &reqwest::blocking::get(&format!(
                "https://cdn.jsdelivr.net/npm/{}@{}/package.json",
                self.name, self.version,
            ))
            .expect("Getting the package config file should not fail")
            .text()
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

        let resp = reqwest::blocking::get(&format!("{}/{}/{}", REGISTRY, name, version))
            .expect("Getting the package manifest file should not fail")
            .text()
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

impl<'de> Deserialize<'de> for Package {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        enum Field {
            Name,
            Version,
        }

        impl<'de> Deserialize<'de> for Field {
            fn deserialize<D>(deserializer: D) -> Result<Field, D::Error>
            where
                D: Deserializer<'de>,
            {
                struct FieldVisitor;

                impl<'de> Visitor<'de> for FieldVisitor {
                    type Value = Field;

                    fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                        formatter.write_str("`name` or `version`")
                    }

                    fn visit_str<E>(self, value: &str) -> Result<Field, E>
                    where
                        E: de::Error,
                    {
                        match value {
                            "name" => Ok(Field::Name),
                            "version" => Ok(Field::Version),
                            _ => Err(de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }

                deserializer.deserialize_identifier(FieldVisitor)
            }
        }

        struct PackageVisitor;

        impl<'de> Visitor<'de> for PackageVisitor {
            type Value = Package;

            fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
                formatter.write_str("struct Package")
            }

            fn visit_seq<V>(self, mut seq: V) -> Result<Package, V::Error>
            where
                V: SeqAccess<'de>,
            {
                let name = seq
                    .next_element()?
                    .ok_or_else(|| de::Error::invalid_length(0, &self))?;
                let version = seq
                    .next_element()?
                    .ok_or_else(|| de::Error::invalid_length(1, &self))?;
                Ok(Package::new(name, version))
            }

            fn visit_map<V>(self, mut map: V) -> Result<Package, V::Error>
            where
                V: MapAccess<'de>,
            {
                let mut name = None;
                let mut version = None;
                while let Some(key) = map.next_key()? {
                    match key {
                        Field::Name => {
                            if name.is_some() {
                                return Err(de::Error::duplicate_field("name"));
                            }
                            name = Some(map.next_value()?);
                        }
                        Field::Version => {
                            if version.is_some() {
                                return Err(de::Error::duplicate_field("version"));
                            }
                            version = Some(map.next_value()?);
                        }
                    }
                }
                let name = name.ok_or_else(|| de::Error::missing_field("name"))?;
                let version = version.ok_or_else(|| de::Error::missing_field("version"))?;
                Ok(Package::new(name, version))
            }
        }

        const FIELDS: &'static [&'static str] = &["name", "version"];
        deserializer.deserialize_struct("Package", FIELDS, PackageVisitor)
    }
}
