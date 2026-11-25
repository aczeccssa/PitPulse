use std::collections::BTreeSet;

use anyhow::{Context, Result, ensure};
use base64::{Engine, engine::general_purpose::STANDARD};
use scraper::{ElementRef, Html, Selector};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleEvent {
    pub id: String,
    pub round: Option<usize>,
    pub name: String,
    pub location: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub track: Option<String>,
    pub start_date: String,
    pub end_date: String,
}

pub fn source_url(season: i64) -> String {
    format!("https://www.formula1.com/en/racing/{season}")
}

pub async fn fetch(client: &reqwest::Client, url: &str, season: i64) -> Result<Vec<ScheduleEvent>> {
    let mut response = client.get(url).send().await?.error_for_status()?;
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        ensure!(
            body.len() + chunk.len() <= 2 * 1024 * 1024,
            "F1 calendar response too large"
        );
        body.extend_from_slice(&chunk);
    }
    parse(std::str::from_utf8(&body)?, season)
}

fn parse(html: &str, season: i64) -> Result<Vec<ScheduleEvent>> {
    let page = Html::parse_document(html);
    let cards = Selector::parse("a[data-f1rd-a7s-click=event_tile_click]").unwrap();
    let round = Selector::parse("span[class*=body-2-xs-bold]").unwrap();
    let location = Selector::parse("p").unwrap();
    let name = Selector::parse("span[class*=body-xs-semibold]").unwrap();
    let dates = Selector::parse("span[class*=technical-m-bold]").unwrap();
    let prefix = format!("/en/racing/{season}/");
    let mut ids = BTreeSet::new();
    let mut events = Vec::new();
    for card in page.select(&cards) {
        let Some(id) = card
            .attr("href")
            .and_then(|href| href.strip_prefix(&prefix))
        else {
            continue;
        };
        ensure!(
            !id.is_empty()
                && id
                    .bytes()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-'),
            "invalid F1 schedule event id"
        );
        ensure!(ids.insert(id), "duplicate F1 schedule event {id}");
        let number = match card_text(card, &round)?.as_str() {
            "TESTING" => None,
            label => Some(
                label
                    .strip_prefix("ROUND ")
                    .context("unknown calendar card")?
                    .parse()?,
            ),
        };
        let (start_date, end_date) = date_range(season, &card_text(card, &dates)?)?;
        let track = card
            .attr("data-f1rd-a7s-context")
            .and_then(|context| STANDARD.decode(context).ok())
            .and_then(|bytes| serde_json::from_slice::<serde_json::Value>(&bytes).ok())
            .and_then(|data| {
                data["trackName"]
                    .as_str()
                    .filter(|name| !name.is_empty())
                    .map(str::to_owned)
            });
        events.push(ScheduleEvent {
            id: id.to_owned(),
            round: number,
            name: card_text(card, &name)?,
            location: card_text(card, &location)?,
            track,
            start_date,
            end_date,
        });
    }
    // A damaged or partially rendered page must never replace the last good calendar.
    let mut rounds: Vec<_> = events.iter().filter_map(|event| event.round).collect();
    rounds.sort_unstable();
    ensure!(
        rounds.len() >= 10 && rounds.iter().copied().eq(1..=rounds.len()),
        "incomplete F1 calendar for {season}"
    );
    events.sort_by(|a, b| (a.round, &a.start_date, &a.id).cmp(&(b.round, &b.start_date, &b.id)));
    Ok(events)
}

fn card_text(card: ElementRef<'_>, selector: &Selector) -> Result<String> {
    let value = card
        .select(selector)
        .next()
        .context("missing F1 calendar card field")?
        .text()
        .flat_map(str::split_whitespace)
        .collect::<Vec<_>>()
        .join(" ");
    ensure!(!value.is_empty(), "empty F1 calendar card field");
    Ok(value)
}

fn date_range(season: i64, range: &str) -> Result<(String, String)> {
    let (start, end) = range
        .split_once(['-', '–', '—'])
        .context("invalid F1 date range")?;
    let parse_day = |text: &str| -> Result<(u32, Option<&'static str>)> {
        let mut parts = text.split_whitespace();
        let day = parts.next().context("missing F1 calendar day")?.parse()?;
        let month = parts
            .next()
            .map(|month| {
                MONTHS
                    .iter()
                    .find(|(label, _)| *label == month)
                    .map(|(label, _)| *label)
                    .context("invalid F1 calendar month")
            })
            .transpose()?;
        ensure!(parts.next().is_none(), "unexpected F1 date tokens");
        Ok((day, month))
    };
    let (last_day, end_month) = parse_day(end)?;
    let end_month = end_month.context("missing F1 calendar month")?;
    let (first_day, start_month) = parse_day(start)?;
    let start = iso_date(season, start_month.unwrap_or(end_month), first_day)?;
    let end = iso_date(season, end_month, last_day)?;
    ensure!(start <= end, "reversed F1 date range");
    Ok((start, end))
}

const MONTHS: [(&str, u32); 12] = [
    ("Jan", 31),
    ("Feb", 28),
    ("Mar", 31),
    ("Apr", 30),
    ("May", 31),
    ("Jun", 30),
    ("Jul", 31),
    ("Aug", 31),
    ("Sep", 30),
    ("Oct", 31),
    ("Nov", 30),
    ("Dec", 31),
];

fn iso_date(season: i64, month: &str, day: u32) -> Result<String> {
    let (index, (_, days)) = MONTHS
        .iter()
        .enumerate()
        .find(|(_, (label, _))| *label == month)
        .context("invalid F1 calendar month")?;
    let leap_day = index == 1 && season % 4 == 0 && (season % 100 != 0 || season % 400 == 0);
    ensure!(
        (1..=days + u32::from(leap_day)).contains(&day),
        "invalid F1 calendar day"
    );
    Ok(format!("{season:04}-{:02}-{day:02}", index + 1))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub(crate) fn calendar(first_dates: &str) -> String {
        (1..=10).map(|round| {
            let dates = if round == 1 { first_dates } else { "08 - 10 May" };
            format!(r#"<a data-f1rd-a7s-click="event_tile_click" href="/en/racing/2027/race-{round}">
                <span class="typography_body-2-xs-bold">ROUND {round}</span>
                <p>Race Location {round}</p>
                <span class="typography_body-xs-semibold">Formula 1 Race &amp; Weekend {round}</span>
                <span class="typography_technical-m-bold">{dates}</span>
            </a>"#)
        }).collect()
    }

    #[test]
    fn parses_weekends_across_months_and_rejects_incomplete_calendars() {
        let html = calendar("30 Apr - 02 May");
        let events = parse(&html, 2027).unwrap();
        assert_eq!(events.len(), 10);
        assert_eq!(events[0].start_date, "2027-04-30");
        assert_eq!(events[0].end_date, "2027-05-02");
        assert_eq!(events[0].name, "Formula 1 Race & Weekend 1");
        assert!(parse(&html.replace("ROUND 9", "ROUND 10"), 2027).is_err());
        assert!(parse(&calendar("31 Apr - 02 May"), 2027).is_err());
        assert!(parse(&html, 2028).is_err());
    }
}
