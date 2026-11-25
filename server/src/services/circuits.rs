use crate::domain::live::LiveLocation;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const GEOMETRY: &str = include_str!("../../resources/circuits/f1-circuits.geojson");
pub const CALIBRATIONS: &str = include_str!("../../resources/circuits/calibrations.json");
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Anchor {
    pub x: f64,
    pub y: f64,
    pub longitude: f64,
    pub latitude: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Calibration {
    pub circuit_key: String,
    pub season: i64,
    pub layout: String,
    pub geometry_id: String,
    pub anchors: [Anchor; 3],
    pub validation: Vec<Anchor>,
    pub source: String,
}
impl Calibration {
    pub fn transform(&self, x: f64, y: f64) -> Option<(f64, f64)> {
        let [a, b, c] = &self.anchors;
        if [x, y, a.x, a.y, b.x, b.y, c.x, c.y]
            .iter()
            .any(|n| !n.is_finite())
        {
            return None;
        }
        let determinant = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
        if determinant.abs() < 1e-6 {
            return None;
        }
        let u = ((x - a.x) * (c.y - a.y) - (c.x - a.x) * (y - a.y)) / determinant;
        let v = ((b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y)) / determinant;
        let lon = a.longitude + u * (b.longitude - a.longitude) + v * (c.longitude - a.longitude);
        let lat = a.latitude + u * (b.latitude - a.latitude) + v * (c.latitude - a.latitude);
        ((-180.0..=180.0).contains(&lon) && (-90.0..=90.0).contains(&lat)).then_some((lon, lat))
    }
    pub fn validated(&self) -> bool {
        !self.source.is_empty()
            && !self.layout.is_empty()
            && !self.validation.is_empty()
            && self.validation.iter().all(|a| {
                self.anchors
                    .iter()
                    .all(|p| (p.x - a.x).hypot(p.y - a.y) > 1.0)
                    && self.transform(a.x, a.y).is_some_and(|(lon, lat)| {
                        distance(lon, lat, a.longitude, a.latitude) <= 20.0
                    })
            })
    }
}
pub fn distance(lon: f64, lat: f64, other_lon: f64, other_lat: f64) -> f64 {
    let dy = (lat - other_lat).to_radians();
    let dx = (lon - other_lon).to_radians() * ((lat + other_lat) / 2.0).to_radians().cos();
    dx.hypot(dy) * 6_371_000.0
}
fn calibrations() -> &'static [Calibration] {
    static VALUES: std::sync::OnceLock<Vec<Calibration>> = std::sync::OnceLock::new();
    VALUES.get_or_init(|| serde_json::from_str(CALIBRATIONS).expect("calibration registry"))
}
pub fn calibration(key: &str, season: i64) -> Option<Calibration> {
    calibrations()
        .iter()
        .find(|c| c.circuit_key == key && c.season == season && c.validated())
        .cloned()
}
pub fn locate(key: Option<&str>, utc: &str, location: &mut LiveLocation) {
    let Some(season) = utc.get(..4).and_then(|s| s.parse().ok()) else {
        return;
    };
    if let Some(c) = key.and_then(|k| calibration(k, season))
        && let Some((lon, lat)) = c.transform(location.x, location.y)
    {
        location.longitude = Some(lon);
        location.latitude = Some(lat);
    }
}

fn features() -> &'static [Value] {
    static COLLECTION: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    COLLECTION.get_or_init(|| serde_json::from_str(GEOMETRY).expect("bundled GeoJSON"))["features"]
        .as_array()
        .expect("bundled circuit features")
}

// Official event slug, venue name from the F1 calendar, and geometry dataset ID.
const PUBLISHED_VENUES: &[(&str, &str, &str)] = &[
    ("pre-season-testing", "Sakhir", "bh-2002"),
    ("bahrain", "Bahrain", "bh-2002"),
    ("saudi-arabia", "Jeddah", "sa-2021"),
    ("australia", "Melbourne", "au-1953"),
    ("japan", "Suzuka", "jp-1962"),
    ("china", "Shanghai", "cn-2004"),
    ("miami", "Miami Gardens", "us-2022"),
    ("canada", "Montréal", "ca-1978"),
    ("monaco", "Monte Carlo", "mc-1929"),
    ("portugal", "Portimão", "pt-2008"),
    ("great-britain", "Silverstone", "gb-1948"),
    ("austria", "Spielberg", "at-1969"),
    ("belgium", "Spa-Francorchamps", "be-1925"),
    ("hungary", "Budapest", "hu-1986"),
    ("italy", "Monza", "it-1922"),
    ("spain", "Madrid", "es-2026"),
    ("spain", "Barcelona", "es-1991"),
    ("azerbaijan", "Baku", "az-2016"),
    ("turkey", "Istanbul", "tr-2005"),
    ("singapore", "Marina Bay", "sg-2008"),
    ("united-states", "Austin", "us-2012"),
    ("mexico", "Mexico City", "mx-1962"),
    ("brazil", "São Paulo", "br-1940"),
    ("las-vegas", "Las Vegas", "us-2023"),
    ("qatar", "Lusail", "qa-2004"),
    ("united-arab-emirates", "Yas Marina", "ae-2009"),
];

pub fn published_venue(slug: &str, track: Option<&str>) -> Option<Value> {
    let (_, _, id) = PUBLISHED_VENUES.iter().find(|(event, name, _)| {
        *event == slug && track.is_none_or(|track| name.eq_ignore_ascii_case(track))
    })?;
    let feature = features().iter().find(|f| f["properties"]["id"] == *id)?;
    let coordinates = feature.pointer("/geometry/coordinates/0")?;
    let properties = &feature["properties"];
    Some(json!({
        "id": id,
        "geometryId": id,
        "name": properties["Name"],
        "longitude": coordinates[0],
        "latitude": coordinates[1],
        "lengthKm": properties["length"].as_f64().map(|meters| meters / 1000.0)
    }))
}

pub fn geometry(circuit: &Value, season: i64) -> Value {
    let (Some(lon), Some(lat)) = (circuit["longitude"].as_f64(), circuit["latitude"].as_f64())
    else {
        return json!({"geometry":null,"status":"location_unavailable"});
    };
    let feature = if let Some(id) = circuit["geometryId"].as_str() {
        features()
            .iter()
            .find(|feature| feature["properties"]["id"] == id)
    } else {
        features()
            .iter()
            .filter_map(|f| {
                let points = f.pointer("/geometry/coordinates")?.as_array()?;
                let nearest = points
                    .iter()
                    .filter_map(|p| Some(distance(lon, lat, p[0].as_f64()?, p[1].as_f64()?)))
                    .fold(f64::INFINITY, f64::min);
                (nearest < 5000.0).then_some((nearest, f))
            })
            .min_by(|a, b| a.0.total_cmp(&b.0))
            .map(|(_, f)| f)
    };
    let id = feature
        .and_then(|f| f.pointer("/properties/id"))
        .and_then(Value::as_str);
    let verified = calibrations()
        .iter()
        .find(|c| c.season == season && c.validated() && Some(c.geometry_id.as_str()) == id);
    json!({"geometry":feature,"status":if feature.is_some() { "available" } else { "geometry_unavailable" },"source":"bacinger/f1-circuits","calibrated":verified.is_some(),"layoutVerified":verified.is_some(),"layout":verified.map(|c| &c.layout)})
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn published_circuit_outlines_use_venue_and_never_guess_relocations() {
        for &(slug, track, id) in PUBLISHED_VENUES {
            let circuit = published_venue(slug, Some(track)).unwrap();
            let result = geometry(&circuit, 2028);
            assert_eq!(result["geometry"]["properties"]["id"], id);
            assert_eq!(result["calibrated"], false);
        }
        assert!(published_venue("spain", Some("unrecognized location")).is_none());
    }

    #[test]
    fn test_bundled_calibrations_pass_and_unverified_seasons_have_no_positions() {
        let values: Vec<Calibration> = serde_json::from_str(CALIBRATIONS).unwrap();
        assert!(!values.is_empty());
        for c in &values {
            assert!(c.validated(), "{} {}", c.circuit_key, c.season);
        }
        assert!(calibration("61", 2026).is_some());
        assert!(calibration("9", 2026).is_none());
        let mut location = LiveLocation {
            x: 0.,
            y: 0.,
            utc: "2026-10-11T00:00:00Z".into(),
            source: None,
            cached: false,
            received_at: None,
            status: None,
            longitude: None,
            latitude: None,
        };
        locate(Some("9"), "2026-10-11T00:00:00Z", &mut location);
        assert!(location.longitude.is_none() && location.latitude.is_none());
        assert_eq!(
            geometry(&json!({"longitude":103.864,"latitude":1.292}), 2026)["calibrated"],
            true
        );
        assert_eq!(
            geometry(&json!({"longitude":-97.641,"latitude":30.132}), 2026)["calibrated"],
            false
        );
    }
    #[test]
    fn test_independent_anchor_gate_and_non_collinear_requirement() {
        let mut c = Calibration {
            circuit_key: "x".into(),
            season: 2026,
            layout: "test".into(),
            geometry_id: "test".into(),
            source: "synthetic test only".into(),
            anchors: [
                Anchor {
                    x: 0.,
                    y: 0.,
                    longitude: 103.,
                    latitude: 1.,
                },
                Anchor {
                    x: 100.,
                    y: 0.,
                    longitude: 103.001,
                    latitude: 1.,
                },
                Anchor {
                    x: 0.,
                    y: 100.,
                    longitude: 103.,
                    latitude: 1.001,
                },
            ],
            validation: vec![Anchor {
                x: 50.,
                y: 50.,
                longitude: 103.0005,
                latitude: 1.0005,
            }],
        };
        assert!(c.validated());
        c.validation[0].latitude += 0.01;
        assert!(!c.validated());
        c.anchors[2] = c.anchors[1].clone();
        assert!(c.transform(50., 50.).is_none());
    }
}
