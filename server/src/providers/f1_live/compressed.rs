use base64::{Engine, engine::general_purpose::STANDARD};
use serde_json::Value;

pub const MAX_BYTES: usize = 2 * 1024 * 1024;

pub fn decode(value: &Value) -> Option<Value> {
    let encoded = value.as_str()?;
    if encoded.len() > MAX_BYTES {
        return None;
    }
    let bytes = STANDARD.decode(encoded).ok()?;
    let mut output = Vec::with_capacity(MAX_BYTES + 1);
    let mut decoder = flate2::Decompress::new(false);
    let status = decoder
        .decompress_vec(&bytes, &mut output, flate2::FlushDecompress::Finish)
        .ok()?;
    if status != flate2::Status::StreamEnd
        || decoder.total_in() != bytes.len() as u64
        || output.len() > MAX_BYTES
    {
        return None;
    }
    serde_json::from_slice(&output).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    pub fn encode(raw: &[u8]) -> Value {
        let mut encoder =
            flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::fast());
        encoder.write_all(raw).unwrap();
        Value::String(STANDARD.encode(encoder.finish().unwrap()))
    }
    #[test]
    fn test_corrupt_and_inflation_limit() {
        assert!(decode(&Value::String("invalid".into())).is_none());
        let encoded = encode(br#"{"Entries":[]}"#);
        let mut bytes = STANDARD.decode(encoded.as_str().unwrap()).unwrap();
        bytes.pop();
        assert!(decode(&Value::String(STANDARD.encode(&bytes))).is_none());
        let mut bytes = STANDARD.decode(encoded.as_str().unwrap()).unwrap();
        bytes.push(0);
        assert!(decode(&Value::String(STANDARD.encode(&bytes))).is_none());
        assert!(decode(&encode(&vec![b' '; MAX_BYTES + 1])).is_none());
        assert_eq!(
            decode(&encode(br#"{"Entries":[]}"#)).unwrap()["Entries"],
            serde_json::json!([])
        );
    }
}
