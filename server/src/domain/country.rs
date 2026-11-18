const COUNTRIES: &[(&str, &str)] = &[
    ("ae", "AE"),
    ("are", "AE"),
    ("au", "AU"),
    ("aus", "AU"),
    ("australia", "AU"),
    ("gb", "GB"),
    ("gbr", "GB"),
    ("uk", "GB"),
    ("united kingdom", "GB"),
    ("great britain", "GB"),
    ("jp", "JP"),
    ("jpn", "JP"),
    ("japan", "JP"),
    ("us", "US"),
    ("usa", "US"),
    ("united states", "US"),
    ("united states of america", "US"),
    ("uae", "AE"),
    ("united arab emirates", "AE"),
    ("at", "AT"),
    ("aut", "AT"),
    ("austria", "AT"),
    ("az", "AZ"),
    ("aze", "AZ"),
    ("azerbaijan", "AZ"),
    ("bh", "BH"),
    ("brn", "BH"),
    ("bahrain", "BH"),
    ("be", "BE"),
    ("bel", "BE"),
    ("belgium", "BE"),
    ("br", "BR"),
    ("bra", "BR"),
    ("brazil", "BR"),
    ("ca", "CA"),
    ("can", "CA"),
    ("canada", "CA"),
    ("cn", "CN"),
    ("chn", "CN"),
    ("china", "CN"),
    ("es", "ES"),
    ("esp", "ES"),
    ("spain", "ES"),
    ("hu", "HU"),
    ("hun", "HU"),
    ("hungary", "HU"),
    ("it", "IT"),
    ("ita", "IT"),
    ("italy", "IT"),
    ("my", "MY"),
    ("mys", "MY"),
    ("malaysia", "MY"),
    ("mx", "MX"),
    ("mex", "MX"),
    ("mexico", "MX"),
    ("mc", "MC"),
    ("mco", "MC"),
    ("mon", "MC"),
    ("monaco", "MC"),
    ("nl", "NL"),
    ("nld", "NL"),
    ("ned", "NL"),
    ("netherlands", "NL"),
    ("qa", "QA"),
    ("qat", "QA"),
    ("qatar", "QA"),
    ("sa", "SA"),
    ("sau", "SA"),
    ("ksa", "SA"),
    ("saudi arabia", "SA"),
    ("sg", "SG"),
    ("sgp", "SG"),
    ("singapore", "SG"),
];

/// Every alpha-2 code the table can return. The dashboard ships one flag per
/// code, so a new venue needs a new entry here and a matching flag file.
pub const ALPHA2_CODES: &[&str] = &[
    "AE", "AT", "AU", "AZ", "BE", "BH", "BR", "CA", "CN", "ES", "GB", "HU", "IT", "JP", "MC", "MX",
    "MY", "NL", "QA", "SA", "SG", "US",
];

pub fn country_code(value: &str) -> Option<String> {
    let normalized = value.trim().to_ascii_lowercase();
    if normalized.is_empty() {
        return None;
    }
    COUNTRIES
        .iter()
        .find(|(alias, _)| *alias == normalized)
        .map(|(_, code)| (*code).to_string())
        .or_else(|| {
            let compact = normalized.replace([' ', '-', '_'], "");
            COUNTRIES
                .iter()
                .find(|(alias, _)| alias.replace(' ', "") == compact)
                .map(|(_, code)| (*code).to_string())
        })
}

#[cfg(test)]
mod tests {
    use super::country_code;

    #[test]
    fn test_required_country_aliases_map_to_alpha2() {
        for (input, expected) in [
            ("Australia", "AU"),
            ("UK", "GB"),
            ("United Kingdom", "GB"),
            ("USA", "US"),
            ("United States", "US"),
            ("UAE", "AE"),
            ("Japan", "JP"),
            ("AUS", "AU"),
            ("GBR", "GB"),
        ] {
            assert_eq!(country_code(input).as_deref(), Some(expected), "{input}");
        }
    }

    #[test]
    fn test_every_modern_venue_has_a_code() {
        // Every country the 2021-2026 calendars visit must resolve, otherwise
        // the dashboard requests /motorsport/flag-.png and renders no flag.
        for (input, expected) in [
            ("Australia", "AU"),
            ("Austria", "AT"),
            ("Azerbaijan", "AZ"),
            ("Bahrain", "BH"),
            ("Belgium", "BE"),
            ("Brazil", "BR"),
            ("Canada", "CA"),
            ("China", "CN"),
            ("Hungary", "HU"),
            ("Italy", "IT"),
            ("Japan", "JP"),
            ("Malaysia", "MY"),
            ("Mexico", "MX"),
            ("Monaco", "MC"),
            ("Netherlands", "NL"),
            ("Qatar", "QA"),
            ("Saudi Arabia", "SA"),
            ("Singapore", "SG"),
            ("Spain", "ES"),
            ("UAE", "AE"),
            ("UK", "GB"),
            ("USA", "US"),
        ] {
            assert_eq!(country_code(input).as_deref(), Some(expected), "{input}");
        }
    }

    #[test]
    fn test_every_alias_returns_a_declared_code() {
        for (alias, code) in super::COUNTRIES {
            assert!(
                super::ALPHA2_CODES.contains(code),
                "{alias} maps to undeclared code {code}"
            );
        }
    }

    #[test]
    fn test_unknown_country_does_not_invent_code() {
        assert_eq!(country_code("Atlantis"), None);
        assert_eq!(country_code(""), None);
    }
}
