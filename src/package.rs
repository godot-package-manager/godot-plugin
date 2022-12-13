use crate::npm_manifest::NpmManifest;
use serde::de::{self, Deserializer, MapAccess, SeqAccess, Visitor};
use serde::Deserialize;

use std::fmt;

const REGISTRY: &str = "https://registry.npmjs.org";

pub struct Package {
    npm_manifest: NpmManifest,
    pub name: String,
    pub version: String,
}

impl Package {
    pub fn new(name: String, version: String) -> Package {
        Package {
            npm_manifest: Self::get_manifest(&name, &version),
            name,
            version,
        }
    }

    pub fn to_string(&self) -> String {
        format!("P({}@{})", self.name, self.version)
    }

    pub fn get_manifest(name: &String, version: &String) -> NpmManifest {
        #[derive(Debug, Deserialize)]
        struct NpmManifestWrapper {
            pub dist: NpmManifest,
        }

        let resp = crate::utils::send_get_request(format!("{}/{}/{}", REGISTRY, name, version));
        let npm_manifest = serde_json::from_str::<NpmManifestWrapper>(&resp)
            .unwrap()
            .dist;
        npm_manifest
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
