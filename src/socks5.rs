use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::Result;
use log::info;

pub async fn handle(mut socket: TcpStream) -> Result<()> {
    let mut buf = [0u8; 2];
    socket.read_exact(&mut buf).await?;
    if buf[0] != 0x05 { anyhow::bail!("Invalid SOCKS"); }
    socket.write_all(&[0x05, 0x00]).await?;
    let mut req = [0u8; 4];
    socket.read_exact(&mut req).await?;
    if req[0] != 0x05 { anyhow::bail!("Invalid SOCKS request"); }
    match req[1] {
        0x01 => handle_connect(socket).await,
        _ => anyhow::bail!("Unsupported SOCKS command"),
    }
}

async fn handle_connect(mut socket: TcpStream) -> Result<()> {
    let mut addr_type = [0u8; 1];
    socket.read_exact(&mut addr_type).await?;
    let target = match addr_type[0] {
        0x01 => {
            let mut ip = [0u8; 4];
            socket.read_exact(&mut ip).await?;
            let mut port = [0u8; 2];
            socket.read_exact(&mut port).await?;
            format!("{}:{}", 
                ip.iter().map(|b| b.to_string()).collect::<Vec<_>>().join("."),
                u16::from_be_bytes(port)
            )
        }
        0x03 => {
            let mut len = [0u8; 1];
            socket.read_exact(&mut len).await?;
            let mut domain = vec![0u8; len[0] as usize];
            socket.read_exact(&mut domain).await?;
            let mut port = [0u8; 2];
            socket.read_exact(&mut port).await?;
            format!("{}:{}", String::from_utf8_lossy(&domain), u16::from_be_bytes(port))
        }
        _ => anyhow::bail!("Unsupported address type"),
    };
    info!("SOCKS5 -> {}", target);
    match TcpStream::connect(&target).await {
        Ok(target_stream) => {
            socket.write_all(&[0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
            let (mut reader, mut writer) = socket.into_split();
            let (mut target_reader, mut target_writer) = target_stream.into_split();
            tokio::try_join!(
                tokio::io::copy(&mut reader, &mut target_writer),
                tokio::io::copy(&mut target_reader, &mut writer)
            )?;
            Ok(())
        }
        Err(_) => {
            socket.write_all(&[0x05, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).await?;
            anyhow::bail!("Connection failed")
        }
    }
}
