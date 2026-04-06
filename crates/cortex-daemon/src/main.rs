//! CORTEX Bridge Daemon — standalone process for Corti ↔ ChatGPT Browser communication.
//!
//! Runs independently of Flutter/FluxForge. Two servers:
//!   - WebSocket on port 9742 — Chrome extension connects here
//!   - HTTP API on port 9743 — CLI/scripts send queries here
//!
//! Usage:
//!   cortex-daemon                    # Start daemon (foreground)
//!   cortex-daemon --port 9742        # Custom WS port
//!   cortex-daemon send "question"    # Send query via HTTP API (daemon must be running)
//!   cortex-daemon status             # Check daemon + browser status

mod protocol;
mod server;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "cortex-daemon", about = "CORTEX ↔ ChatGPT Browser Bridge Daemon")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// WebSocket port for browser extension
    #[arg(long, default_value_t = 9742)]
    port: u16,

    /// HTTP API port for queries
    #[arg(long, default_value_t = 9743)]
    api_port: u16,
}

#[derive(Subcommand)]
enum Commands {
    /// Send a query to ChatGPT via the running daemon
    Send {
        /// The message to send to ChatGPT
        message: String,
        /// Intent: analysis, architecture, debugging, code_review, insight, user_query, creative
        #[arg(short, long, default_value = "user_query")]
        intent: String,
    },
    /// Check daemon and browser connection status
    Status,
}

#[tokio::main]
async fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_millis()
        .init();

    let cli = Cli::parse();

    match cli.command {
        None => {
            // Start daemon mode
            server::run_daemon(cli.port, cli.api_port).await;
        }
        Some(Commands::Send { message, intent }) => {
            // Send query to running daemon via HTTP
            match send_query(cli.api_port, &message, &intent).await {
                Ok(response) => {
                    println!("{}", response);
                }
                Err(e) => {
                    eprintln!("Error: {}", e);
                    std::process::exit(1);
                }
            }
        }
        Some(Commands::Status) => {
            match get_status(cli.api_port).await {
                Ok(status) => println!("{}", status),
                Err(e) => {
                    eprintln!("Daemon not running or unreachable: {}", e);
                    std::process::exit(1);
                }
            }
        }
    }
}

async fn send_query(api_port: u16, message: &str, intent: &str) -> Result<String, String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let body = serde_json::json!({
        "content": message,
        "intent": intent,
    });
    let body_str = body.to_string();
    let request = format!(
        "POST /query HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        api_port,
        body_str.len(),
        body_str,
    );

    let mut stream = tokio::net::TcpStream::connect(format!("127.0.0.1:{}", api_port))
        .await
        .map_err(|e| format!("Cannot connect to daemon on port {}: {}", api_port, e))?;

    stream.write_all(request.as_bytes()).await.map_err(|e| e.to_string())?;
    stream.shutdown().await.ok();

    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.map_err(|e| e.to_string())?;
    let response = String::from_utf8_lossy(&buf);

    // Extract body after \r\n\r\n
    if let Some(pos) = response.find("\r\n\r\n") {
        Ok(response[pos + 4..].to_string())
    } else {
        Ok(response.to_string())
    }
}

async fn get_status(api_port: u16) -> Result<String, String> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let request = format!(
        "GET /status HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nConnection: close\r\n\r\n",
        api_port,
    );

    let mut stream = tokio::net::TcpStream::connect(format!("127.0.0.1:{}", api_port))
        .await
        .map_err(|e| format!("Cannot connect to daemon on port {}: {}", api_port, e))?;

    stream.write_all(request.as_bytes()).await.map_err(|e| e.to_string())?;
    stream.shutdown().await.ok();

    let mut buf = Vec::new();
    stream.read_to_end(&mut buf).await.map_err(|e| e.to_string())?;
    let response = String::from_utf8_lossy(&buf);

    if let Some(pos) = response.find("\r\n\r\n") {
        Ok(response[pos + 4..].to_string())
    } else {
        Ok(response.to_string())
    }
}
