use std::collections::BTreeMap;

use serde::Serialize;
use serde_json::{Value, json};

use super::media::Group;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MediaRef {
    group: &'static str,
    file: &'static str,
    sha256: String,
    url: String,
    is_placeholder: bool,
}

#[derive(Default, Serialize)]
pub(crate) struct Bindings {
    assets: BTreeMap<String, MediaRef>,
    placeholders: BTreeMap<&'static str, MediaRef>,
}

const KINDS: [&str; 4] = ["helmet", "driver-photo", "car-side", "team-logo"];

const ALIASES: &[(&str, &str)] = &[
    ("verstappen", "max_verstappen"),
    ("magnussen", "kevin_magnussen"),
    ("lindblad", "arvid_lindblad"),
    ("camara", "rafael_camara"),
    ("hirakawa", "ryo_hirakawa"),
    ("kimi_antonelli", "antonelli"),
    ("andrea_kimi_antonelli", "antonelli"),
    ("checo_perez", "perez"),
    ("guanyu_zhou", "zhou"),
    ("racing_bulls", "rb"),
    ("visa_cash_app_rb", "rb"),
    ("rb_f1_team", "rb"),
    ("red_bull_racing", "red_bull"),
    ("oracle_red_bull_racing", "red_bull"),
    ("haas_f1_team", "haas"),
    ("kick_sauber", "sauber"),
    ("stake_f1_team_kick_sauber", "sauber"),
];

impl Bindings {
    pub(super) fn build(groups: &BTreeMap<&'static str, Group>, native: bool) -> Self {
        let mut bindings = Self::default();
        for (&group, entry) in groups {
            // Native-only artwork extends the same public bindings used by result rows.
            if !native && group.starts_with("native-") {
                continue;
            }
            for (&file, digest) in &entry.files {
                let prefix = if native {
                    "/api/v1/media/blob/"
                } else {
                    "/media/blob/"
                };
                let reference = MediaRef {
                    group,
                    file,
                    sha256: digest.clone(),
                    url: format!("{prefix}{digest}"),
                    is_placeholder: group == "placeholders",
                };
                let stem = file.rsplit_once('.').map_or(file, |(stem, _)| stem);
                if group == "placeholders" {
                    bindings.placeholders.insert(stem, reference);
                    continue;
                }
                let key = match group.split_once('/') {
                    Some((year, kind)) if !group.starts_with("native-") => {
                        let (id, variant) = stem
                            .strip_suffix("-dark")
                            .map(|id| (id, "-dark"))
                            .or_else(|| stem.strip_suffix("-contrast").map(|id| (id, "-contrast")))
                            .unwrap_or((stem, ""));
                        format!("{kind}-{id}-{year}{variant}")
                    }
                    _ => stem.to_owned(),
                };
                bindings.assets.entry(key).or_insert(reference);
            }
        }
        let identities: Vec<_> = bindings.assets.keys().cloned().collect();
        for key in identities {
            for kind in KINDS {
                let Some(id_and_year) = key.strip_prefix(&format!("{kind}-")) else {
                    continue;
                };
                let (base, suffix) = id_and_year
                    .strip_suffix("-dark")
                    .map(|base| (base, "-dark"))
                    .or_else(|| {
                        id_and_year
                            .strip_suffix("-contrast")
                            .map(|base| (base, "-contrast"))
                    })
                    .unwrap_or((id_and_year, ""));
                let Some((id, year)) = base.rsplit_once('-') else {
                    continue;
                };
                if year.parse::<i64>().is_err() {
                    continue;
                }
                for (alias, canonical) in ALIASES {
                    if *canonical == id {
                        let media = bindings.assets[&key].clone();
                        bindings
                            .assets
                            .entry(format!("{kind}-{alias}-{year}{suffix}"))
                            .or_insert(media);
                    }
                }
            }
        }
        for kind in ["helmet-", "driver-photo-"] {
            let avatars: Vec<_> = bindings
                .assets
                .iter()
                .filter_map(|(key, media)| {
                    key.strip_prefix(kind)
                        .map(|id_and_year| (format!("avatar-helmet-{id_and_year}"), media.clone()))
                })
                .collect();
            for (key, media) in avatars {
                bindings.assets.entry(key).or_insert(media);
            }
        }
        bindings
    }

    fn get(&self, kind: &str, season: i64, id: &str) -> Option<&MediaRef> {
        let normalized = id.trim().to_ascii_lowercase().replace([' ', '-'], "_");
        self.assets
            .get(&format!("{kind}-{id}-{season}"))
            .or_else(|| self.assets.get(&format!("{kind}-{normalized}-{season}")))
            .or_else(|| self.placeholders.get(kind))
    }

    pub fn driver(&self, season: i64, id: &str) -> Value {
        json!({
            "avatar": self.get("avatar-helmet", season, id).or_else(|| self.placeholders.get("driver-photo")),
            "helmet": self.get("helmet", season, id),
            "driverPhoto": self.get("driver-photo", season, id),
        })
    }

    pub fn team(&self, season: i64, id: &str) -> Value {
        json!({
            "teamLogo": self.get("team-logo", season, id),
            "carSide": self.get("car-side", season, id),
        })
    }

    pub fn add_result_media(&self, row: &mut Value, season: i64) {
        let driver = row["driverId"].as_str().unwrap_or_default();
        let team = row["constructorId"].as_str().unwrap_or_default();
        row["media"] = json!({
            "driver": self.driver(season, driver),
            "constructor": self.team(season, team),
        });
    }
}
