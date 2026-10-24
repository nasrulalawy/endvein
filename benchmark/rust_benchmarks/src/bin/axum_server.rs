use axum::{
    http::header,
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use std::net::SocketAddr;

async fn json_handler() -> Response {
    (
        [(header::CONTENT_TYPE, "application/json; charset=utf-8")],
        r#"{"message":"Hello from Axum","status":"ok"}"#,
    )
        .into_response()
}

async fn plaintext_handler() -> Response {
    (
        [(header::CONTENT_TYPE, "text/plain; charset=utf-8")],
        "Hello World",
    )
        .into_response()
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/json", get(json_handler))
        .route("/plaintext", get(plaintext_handler));

    let addr = SocketAddr::from(([127, 0, 0, 1], 8096));
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
