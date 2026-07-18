use tokio::net::TcpStream;
use anyhow::Result;
use log::info;
use tokio::io::AsyncWriteExt;

pub async fn handle(mut socket: TcpStream) -> Result<()> {
    info!("🔒 TLS");
    socket.write_all(b"TLS OK\n").await?;
    Ok(())
}
