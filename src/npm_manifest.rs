use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct NpmManifest {
    pub tarball: String,
    pub integrity: String,
}
