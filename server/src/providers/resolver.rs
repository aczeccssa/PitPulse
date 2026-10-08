use crate::config::ProvidersConfig;

#[derive(Debug, Clone)]
pub struct SourceResolver {
    pub jolpica_enabled: bool,
    pub openf1_enabled: bool,
}

impl SourceResolver {
    pub const fn new(config: &ProvidersConfig) -> Self {
        Self {
            jolpica_enabled: config.jolpica_enabled,
            openf1_enabled: config.openf1_enabled,
        }
    }

    pub const fn calendar_source(&self) -> &'static str {
        if self.jolpica_enabled {
            "jolpica"
        } else {
            "openf1"
        }
    }
}
