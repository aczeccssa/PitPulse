use std::{collections::BTreeSet, time::Duration};

use pitpulse_server::providers::f1_live::client::{F1LiveClient, F1LiveUpdate, topic_names};
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    let token = std::env::var("F1_LIVE_ACCESS_TOKEN").ok();
    let client = F1LiveClient::new(
        true,
        "https://livetiming.formula1.com/signalrcore".to_string(),
    );
    let (updates_tx, mut updates_rx) = mpsc::channel(256);
    let (stop_tx, stop_rx) = tokio::sync::oneshot::channel();
    let connection = tokio::spawn(async move { client.run(token, updates_tx, stop_rx).await });
    println!(
        "probe=started auth_configured={}",
        std::env::var_os("F1_LIVE_ACCESS_TOKEN").is_some()
    );

    let mut observed = BTreeSet::new();
    let mut initial = false;
    let result = tokio::time::timeout(Duration::from_secs(30), async {
        loop {
            tokio::select! {
                update = updates_rx.recv() => match update {
                    Some(F1LiveUpdate::InitialSnapshot(value)) => {
                        initial = true;
                        observed.extend(topic_names(&value));
                        println!("subscribe=ok initial_topics={}", observed.iter().cloned().collect::<Vec<_>>().join(","));
                    }
                    Some(F1LiveUpdate::Feed(value)) => {
                        let topics = topic_names(&value);
                        observed.extend(topics.iter().cloned());
                        println!("feed=received topics={}", topics.join(","));
                    }
                    Some(F1LiveUpdate::TransportHeartbeat) => println!("transport=heartbeat"),
                    None => break,
                },
                signal = tokio::signal::ctrl_c() => {
                    if signal.is_ok() { break; }
                }
            }
        }
    }).await;
    let _ = stop_tx.send(());
    match connection.await {
        Ok(Ok(())) => println!("connection_end=closed"),
        Ok(Err(error)) => println!("connection_end={}", error.reason()),
        Err(error) => println!("connection_task=failed task_error={}", error.is_cancelled()),
    }
    println!(
        "probe=finished initial_snapshot={initial} observed_topics={}",
        observed.iter().cloned().collect::<Vec<_>>().join(",")
    );
    if result.is_err() {
        println!("observation_window=30s");
    }
}
