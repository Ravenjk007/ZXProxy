use tokio::io::{copy_bidirectional, AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use anyhow::Result;
use log::info;

/// Handshake SECURITY personalizado (igual wssecury)
/// Detecta conexões que começam com "SECURITY" ou "AUTH"
pub async fn handle_security(mut socket: TcpStream) -> Result<()> {
    info!("🔐 SECURITY handshake...");
    
    // Ler o cabeçalho SECURITY
    let mut buf = [0u8; 256];
    let n = socket.read(&mut buf).await?;
    let data = String::from_utf8_lossy(&buf[..n]);
    
    info!("📩 SECURITY payload: {}", data);
    
    // Responder com handshake SECURITY (igual wssecury)
    let response = "HTTP/1.1 200 OK\r\n\
                    Connection: Upgrade\r\n\
                    Upgrade: security\r\n\
                    Sec-Security-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\
                    \r\n";
    
    socket.write_all(response.as_bytes()).await?;
    info!("🔐 SECURITY handshake complete! Encaminhando para SSH...");
    
    // Encaminhar para SSH (ou destino configurado)
    let target = "127.0.0.1:22";
    
    match TcpStream::connect(target).await {
        Ok(remote) => {
            info!("✅ Conectado ao SSH na porta 22");
            
            let (mut client_reader, mut client_writer) = socket.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
            
            info!("🔚 Conexão SECURITY->SSH encerrada");
            Ok(())
        }
        Err(e) => {
            info!("❌ Falha ao conectar ao SSH: {}", e);
            anyhow::bail!("SSH connection failed: {}", e)
        }
    }
}
