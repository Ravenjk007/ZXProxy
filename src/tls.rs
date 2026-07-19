use tokio::net::TcpStream;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use anyhow::{Result, anyhow};
use log::{info, debug, error};
use native_tls::TlsConnector;
use tokio_native_tls::TlsStream;

pub async fn handle_tls(socket: TcpStream, vpn_enabled: bool) -> Result<()> {
    info!("🔒 Handling TLS connection...");
    
    // Conecta ao destino via TLS
    let connector = TlsConnector::builder()
        .danger_accept_invalid_certs(true) // Para testes
        .build()?;
    
    // Leitura inicial para identificar destino (SNI)
    let mut buf = [0u8; 1024];
    let n = socket.peek(&mut buf).await?;
    
    if n == 0 {
        return Err(anyhow!("No TLS data received"));
    }
    
    // Extrai SNI se possível (simplificado)
    let sni = extract_sni(&buf, n);
    
    if let Some(hostname) = sni {
        debug!("TLS SNI: {}", hostname);
        
        // Conecta via TLS ao destino
        let stream = TcpStream::connect(format!("{}:443", hostname)).await?;
        let mut tls_stream = connector.connect(&hostname, stream).await?;
        
        info!("✅ TLS connection established to {}", hostname);
        
        // Faz proxy bidirecional
        let (mut reader, mut writer) = socket.into_split();
        let (mut tls_reader, mut tls_writer) = tokio::io::split(&mut tls_stream);
        
        // Envia dados iniciais
        let initial_data = &buf[..n];
        tls_writer.write_all(initial_data).await?;
        
        // Proxy bidirecional com TLS
        tokio::select! {
            _ = tokio::io::copy(&mut reader, &mut tls_writer) => {},
            _ = tokio::io::copy(&mut tls_reader, &mut writer) => {},
        }
    } else {
        // Fallback para conexão direta
        info!("TLS connection without SNI, using fallback");
        tcp_fallback::handle_tcp(socket, vpn_enabled).await?;
    }
    
    Ok(())
}

fn extract_sni(data: &[u8], len: usize) -> Option<String> {
    // Implementação simplificada para extrair SNI do Client Hello
    if len < 43 {
        return None;
    }
    
    // Procura por extensão SNI
    let mut pos = 43; // Posição após handshake header
    while pos + 2 < len {
        let ext_type = u16::from_be_bytes([data[pos], data[pos + 1]]);
        let ext_len = u16::from_be_bytes([data[pos + 2], data[pos + 3]]) as usize;
        
        if ext_type == 0x0000 { // SNI
            pos += 4;
            if pos + 2 < len {
                let sni_len = u16::from_be_bytes([data[pos], data[pos + 1]]) as usize;
                pos += 2;
                if pos + sni_len <= len {
                    let sni = String::from_utf8_lossy(&data[pos..pos + sni_len]).to_string();
                    return Some(sni);
                }
            }
            return None;
        }
        pos += 4 + ext_len;
    }
    
    None
}
