use serde_json::Value;

/// Recursively merge SignalR-style JSON patches.
///
/// Objects are merged key-by-key; arrays and scalar values replace the old value.
/// This is intentionally conservative until real topic schemas are fixture-tested.
pub fn deep_merge(current: &mut Value, patch: &Value) {
    match (current, patch) {
        (Value::Object(current), Value::Object(patch)) => {
            for (key, value) in patch {
                match current.get_mut(key) {
                    Some(existing) => deep_merge(existing, value),
                    None => {
                        current.insert(key.clone(), value.clone());
                    }
                }
            }
        }
        (current, patch) => *current = patch.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_deep_merge_nested_maps_are_merged() {
        let mut current = json!({"TimingData": {"Lines": {"44": {"Gap": "1.2"}}}});
        let patch = json!({"TimingData": {"Lines": {"44": {"Interval": "0.4"}}}});
        deep_merge(&mut current, &patch);
        assert_eq!(
            current,
            json!({"TimingData": {"Lines": {"44": {"Gap": "1.2", "Interval": "0.4"}}}})
        );
    }

    #[test]
    fn test_deep_merge_scalars_are_replaced() {
        let mut current = json!({"LapCount": {"TotalLaps": 52}});
        let patch = json!({"LapCount": {"TotalLaps": 53}});
        deep_merge(&mut current, &patch);
        assert_eq!(current, json!({"LapCount": {"TotalLaps": 53}}));
    }
}
