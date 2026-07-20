use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

pub async fn handle_ssh_tunnel(mut socket: TcpStream) -> Result<()> {
    info!("🔑 SSH Tunnel connection");
    
    // Read SSH banner
    let mut banner = [0u8; 256];
    let n = socket.peek(&mut banner).await?;
    let banner_str = String::from_utf8_lossy(&banner[..n]);
    info!("📩 SSH banner: {}", banner_str.lines().next().unwrap_or(""));
    
    // Forward to SSH server (port 22) or local SSH tunnel
    let target = "127.0.0.1:22";
    
    match TcpStream::connect(target).await {
        Ok(mut remote) => {
            info!("✅ Connected to SSH server on port 22");
            
            // Send SSH banner from remote
            let mut remote_banner = [0u8; 256];
            let n = remote.read(&mut remote_banner).await?;
            socket.write_all(&remote_banner[..n]).await?;
            
            // Bidirectional tunnel
            let (mut client_reader, mut client_writer) = socket.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
            
            info!("🔑 SSH tunnel closed");
            Ok(())
        }
        Err(e) => {
            info!("❌ Failed to connect to SSH: {}", e);
            socket.write_all(b"SSH-2.0-ZXProxy\r\n").await?;
            Ok(())
        }
    }
}
