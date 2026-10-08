use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopicPatch {
    pub topic: String,
    pub patch: serde_json::Value,
    pub received_at: String,
}
