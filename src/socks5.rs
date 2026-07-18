use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle(mut client: TcpStream) -> Result<()> {
    info!("🔐 SOCKS5");
    client.write_all(b"SOCKS5 OK\n").await?;
    Ok(())
}
