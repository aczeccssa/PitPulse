use pitpulse_server::storage::sqlite::Database;
use tempfile::TempDir;

#[tokio::test]
async fn test_database_migrates_and_answers_health_query() {
    let temp = TempDir::new().unwrap();
    let database = Database::open(&temp.path().join("pitpulse.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    database.health_check().await.unwrap();
}
