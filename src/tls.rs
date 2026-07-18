use tokio::net::TcpStream;
use tokio_rustls::TlsAcceptor;
use rustls::{ServerConfig, Certificate, PrivateKey};
use std::sync::Arc;
use std::fs;
use anyhow::Result;
use log::{info, warn};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub async fn handle_tls(socket: TcpStream) -> Result<()> {
    info!("🔒 TLS/SECURITY handshake...");
    
    // Tenta carregar certificado REAL (se existir)
    let (cert, key) = match load_certificates() {
        Ok((c, k)) => {
            info!("✅ Certificado SSL carregado com sucesso!");
            (c, k)
        }
        Err(e) => {
            warn!("⚠️ Certificado real não encontrado: {}", e);
            info!("📦 Usando certificado self-signed (apenas para teste)");
            generate_self_signed_cert()?
        }
    };
    
    let config = ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(vec![cert], key)?;
    
    let acceptor = TlsAcceptor::from(Arc::new(config));
    let mut tls_stream = acceptor.accept(socket).await?;
    
    info!("🔒 TLS handshake complete!");
    
    // Encaminhar para SSH (se disponível) ou fazer eco
    let target = "127.0.0.1:22";
    
    match tokio::net::TcpStream::connect(target).await {
        Ok(remote) => {
            info!("✅ Conectado ao SSH na porta 22");
            let (mut client_reader, mut client_writer) = tls_stream.into_split();
            let (mut remote_reader, mut remote_writer) = remote.into_split();
            
            tokio::try_join!(
                tokio::io::copy(&mut client_reader, &mut remote_writer),
                tokio::io::copy(&mut remote_reader, &mut client_writer)
            )?;
            
            info!("🔚 Conexão TLS->SSH encerrada");
            Ok(())
        }
        Err(_) => {
            info!("📦 SSH não disponível, usando modo echo");
            // Fallback para eco
            let mut buf = [0u8; 1024];
            loop {
                match tls_stream.read(&mut buf).await {
                    Ok(0) => break,
                    Ok(n) => {
                        let msg = String::from_utf8_lossy(&buf[..n]);
                        let response = format!("SECURE: {}", msg);
                        tls_stream.write_all(response.as_bytes()).await?;
                    }
                    Err(e) => anyhow::bail!("TLS error: {}", e),
                }
            }
            Ok(())
        }
    }
}

fn load_certificates() -> Result<(Certificate, PrivateKey)> {
    // Caminhos possíveis para os certificados
    let cert_paths = [
        "/opt/bsproxy/cert.pem",
        "/etc/letsencrypt/live/localhost/fullchain.pem",
        "./cert.pem",
        "./fullchain.pem",
    ];
    
    let key_paths = [
        "/opt/bsproxy/cert.key",
        "/etc/letsencrypt/live/localhost/privkey.pem",
        "./cert.key",
        "./privkey.pem",
    ];
    
    for (cert_path, key_path) in cert_paths.iter().zip(key_paths.iter()) {
        if std::path::Path::new(cert_path).exists() && std::path::Path::new(key_path).exists() {
            info!("📂 Certificado encontrado em: {}", cert_path);
            let cert_data = fs::read(cert_path)?;
            let key_data = fs::read(key_path)?;
            return Ok((Certificate(cert_data), PrivateKey(key_data)));
        }
    }
    
    anyhow::bail!("Nenhum certificado encontrado")
}

fn generate_self_signed_cert() -> Result<(Certificate, PrivateKey)> {
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".to_string()])?;
    let cert_der = cert.serialize_der()?;
    let key_der = cert.serialize_private_key_der();
    Ok((Certificate(cert_der), PrivateKey(key_der)))
}
