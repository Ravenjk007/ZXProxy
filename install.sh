cat > install.sh << 'EOF'
#!/bin/bash

echo "🔧 Instalando BSProxy Multiprotocol..."
echo "📡 Protocols: SOCKS5 + TLS/SECURITY + TCP Fallback"
echo ""

# Instalar Rust se não tiver
if ! command -v cargo &> /dev/null; then
    echo "📦 Instalando Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
fi

# Compilar o projeto
echo "📦 Compilando BSProxy..."
cargo build --release

# Copiar para /usr/local/bin
if [ -f "./target/release/bsproxy" ]; then
    echo "📦 Instalando bsproxy no sistema..."
    sudo cp ./target/release/bsproxy /usr/local/bin/
    sudo chmod +x /usr/local/bin/bsproxy
    echo "✅ bsproxy instalado globalmente!"
fi

# Tornar scripts executáveis
if [ -f "./menu.sh" ]; then
    chmod +x menu.sh
fi

echo ""
echo "✅ Instalação concluída!"
echo ""
echo "🚀 Para usar:"
echo "   bsproxy -p 80"
echo ""
echo "📋 Ou com menu:"
echo "   ./menu.sh"
echo ""
echo "🧪 Testes:"
echo "   curl --socks5 localhost:80 http://example.com"
echo "   openssl s_client -connect localhost:80"
echo ""
EOF

chmod +x install.sh
