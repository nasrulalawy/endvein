use actix_web::{web, App, HttpResponse, HttpServer, Responder};

async fn json_handler() -> impl Responder {
    HttpResponse::Ok()
        .content_type("application/json; charset=utf-8")
        .body(r#"{"message":"Hello from Actix","status":"ok"}"#)
}

async fn plaintext_handler() -> impl Responder {
    HttpResponse::Ok()
        .content_type("text/plain; charset=utf-8")
        .body("Hello World")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .route("/json", web::get().to(json_handler))
            .route("/plaintext", web::get().to(plaintext_handler))
    })
    .bind(("127.0.0.1", 8095))?
    .run()
    .await
}
