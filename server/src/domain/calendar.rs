use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Meeting {
    pub id: String,
    pub season: i64,
    pub round: Option<i64>,
    #[serde(skip)]
    pub jolpica_round_id: Option<String>,
    pub name: String,
    pub country: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country_code: Option<String>,
    pub location: String,
    pub start_date: String,
    pub end_date: String,
    pub status: MeetingStatus,
    pub sessions: Vec<Session>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fetched_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_updated_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub revision: Option<i64>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MeetingStatus {
    Scheduled,
    Postponed,
    Cancelled,
}

impl MeetingStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Scheduled => "scheduled",
            Self::Postponed => "postponed",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn parse(value: &str) -> Self {
        match value {
            "postponed" => Self::Postponed,
            "cancelled" => Self::Cancelled,
            _ => Self::Scheduled,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub id: String,
    pub meeting_id: String,
    pub session_type: SessionType,
    pub start_time: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub end_time: Option<String>,
    pub status: SessionStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jolpica_session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub openf1_session_key: Option<i64>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum SessionType {
    Fp1,
    Fp2,
    Fp3,
    SprintQualifying,
    Sprint,
    Qualifying,
    Race,
}

impl SessionType {
    pub const ALL: [Self; 7] = [
        Self::Fp1,
        Self::Fp2,
        Self::Fp3,
        Self::SprintQualifying,
        Self::Sprint,
        Self::Qualifying,
        Self::Race,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Fp1 => "fp1",
            Self::Fp2 => "fp2",
            Self::Fp3 => "fp3",
            Self::SprintQualifying => "sprintQualifying",
            Self::Sprint => "sprint",
            Self::Qualifying => "qualifying",
            Self::Race => "race",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|item| item.as_str() == value)
    }

    pub fn from_provider(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "fp1" | "firstpractice" | "practice 1" | "practice1" => Some(Self::Fp1),
            "fp2" | "secondpractice" | "practice 2" | "practice2" => Some(Self::Fp2),
            "fp3" | "thirdpractice" | "practice 3" | "practice3" => Some(Self::Fp3),
            "sq" | "sprintqualifying" | "sprint qualifying" | "sprintshootout" => {
                Some(Self::SprintQualifying)
            }
            "sr" | "sprint" | "sprint race" => Some(Self::Sprint),
            "q" | "qualifying" => Some(Self::Qualifying),
            "r" | "race" => Some(Self::Race),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Scheduled,
    Live,
    Finished,
    Postponed,
    Cancelled,
}

impl SessionStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Scheduled => "scheduled",
            Self::Live => "live",
            Self::Finished => "finished",
            Self::Postponed => "postponed",
            Self::Cancelled => "cancelled",
        }
    }

    pub fn parse(value: &str) -> Self {
        match value {
            "live" => Self::Live,
            "finished" => Self::Finished,
            "postponed" => Self::Postponed,
            "cancelled" => Self::Cancelled,
            _ => Self::Scheduled,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct ProviderMapping {
    pub provider: String,
    pub provider_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub meeting_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
}

pub fn meeting_id(season: i64, round: Option<i64>, provider_id: &str) -> String {
    match round {
        Some(round) => format!("{season}:{round}"),
        None => format!("{season}:cancelled:{provider_id}"),
    }
}

pub fn session_id(meeting_id: &str, session_type: SessionType) -> String {
    format!("{meeting_id}:{}", session_type.as_str())
}
