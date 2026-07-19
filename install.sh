#!/bin/bash
# ZXProxy Menu Manager
ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"

show_banner() {
    clear
    echo "╔══════════════════════════════════════════════╗"
    echo "║         🚀 ZXProxy Manager v2.0             ║"
    echo "║    Multiprotocol Proxy with VPN Support     ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
}

show_menu() {
    show_banner
    
    # Mostra portas ativas
    ACTIVE_PORTS=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                ACTIVE_PORTS="$ACTIVE_PORTS $PORT"
            else
                rm -f "$pidfile"
            fi
        fi
    done
    
    echo "📊 Status:"
    if [ -n "$ACTIVE_PORTS" ]; then
        echo "   ✅ Porta(s) aberta(s):$ACTIVE_PORTS"
    else
        echo "   ⚠️  Nenhuma porta ativa"
    fi
    echo ""
    
    echo "📋 Opções disponíveis:"
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │  1 - Abrir Porta                        │"
    echo "  │  2 - Fechar Porta                      │"
    echo "  │  3 - Status do Proxy                   │"
    echo "  │  4 - Ver Logs                         │"
    echo "  │  5 - Testar Proxy                     │"
    echo "  │  6 - Sair                             │"
    echo "  └─────────────────────────────────────────┘"
    echo ""
    echo -n "👉 Selecione uma opção: "
}

open_port() {
    show_banner
    echo "🔓 ABRIR PORTA"
    echo "════════════════"
    echo ""
    read -p "Digite o número da porta: " PORT
    
    # Valida porta
    if [[ -z "$PORT" ]] || ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo "❌ Porta inválida! Use um número entre 1 e 65535."
        sleep 2
        return
    fi
    
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        echo "❌ Porta ${PORT} já está aberta!"
        sleep 2
        return
    fi
    
    echo "🔓 Abrindo porta ${PORT}..."
    
    if [ ! -f "$ZXPROXY" ]; then
        echo "❌ ZXProxy não encontrado em ${ZXPROXY}!"
        echo "📦 Execute o instalador novamente."
        sleep 3
        return
    fi
    
    # Inicia o proxy
    nohup ${ZXPROXY} -p ${PORT} -d > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    echo $! > "${PID_FILE}${PORT}.pid"
    
    sleep 2
    
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo "✅ Porta ${PORT} aberta com sucesso!"
        echo ""
        echo "📡 Proxy rodando em: 0.0.0.0:${PORT}"
        echo "🔒 Modo VPN: Ativado"
        echo "📋 Logs: /tmp/zxproxy_${PORT}.log"
        echo ""
        echo "🌐 Teste rápido:"
        echo "   curl -x http://localhost:${PORT} https://example.com"
    else
        echo "❌ Falha ao abrir a porta ${PORT}!"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    
    echo ""
    read -p "Pressione ENTER para continuar..."
}

close_port() {
    show_banner
    echo "🔒 FECHAR PORTA"
    echo "═══════════════"
    echo ""
    read -p "Digite o número da porta: " PORT
    
    if [[ -z "$PORT" ]] || ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo "✅ Porta ${PORT} fechada com sucesso!"
        echo "🗑️  Processo ${PID} terminado."
    else
        echo "❌ Porta ${PORT} não está aberta!"
    fi
    
    echo ""
    read -p "Pressione ENTER para continuar..."
}

show_status() {
    show_banner
    echo "📊 STATUS DO ZXPROXY"
    echo "════════════════════"
    echo ""
    
    # Verifica instalação
    if [ -f "$ZXPROXY" ]; then
        echo "✅ ZXProxy instalado: $ZXPROXY"
        VERSION=$(${ZXPROXY} --version 2>/dev/null || echo "v2.0.0")
        echo "📦 Versão: $VERSION"
        echo "📏 Tamanho: $(du -h $ZXPROXY | cut -f1)"
    else
        echo "❌ ZXProxy NÃO instalado!"
    fi
    echo ""
    
    # Lista portas ativas
    echo "📡 Portas Ativas:"
    FOUND=false
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                PID=$(cat "$pidfile")
                echo "   🔹 Porta ${PORT} - PID: ${PID}"
                if command -v ps &> /dev/null; then
                    CPU=$(ps -p $PID -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    MEM=$(ps -p $PID -o %mem --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    TIME=$(ps -p $PID -o time --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                    echo "      CPU: ${CPU}% | MEM: ${MEM}% | Tempo: ${TIME}"
                fi
                FOUND=true
            else
                rm -f "$pidfile"
            fi
        fi
    done
    if [ "$FOUND" = false ]; then
        echo "   Nenhuma porta ativa"
    fi
    echo ""
    
    # Mostra logs recentes
    echo "📋 Últimos logs:"
    LATEST_LOG=$(ls -t /tmp/zxproxy_*.log 2>/dev/null | head -1)
    if [ -f "$LATEST_LOG" ]; then
        echo "   📄 Arquivo: $(basename $LATEST_LOG)"
        echo "   ─────────────────────────────"
        tail -5 "$LATEST_LOG" 2>/dev/null | while read line; do
            echo "   $line"
        done
    else
        echo "   Nenhum log disponível"
    fi
    echo ""
    
    read -p "Pressione ENTER para continuar..."
}

show_logs() {
    show_banner
    echo "📋 LOGS DO ZXPROXY"
    echo "══════════════════"
    echo ""
    
    # Lista arquivos de log
    LOGS=$(ls -t /tmp/zxproxy_*.log 2>/dev/null)
    if [ -z "$LOGS" ]; then
        echo "❌ Nenhum log encontrado"
        echo ""
        read -p "Pressione ENTER para continuar..."
        return
    fi
    
    echo "Arquivos de log disponíveis:"
    i=1
    declare -a LOG_FILES
    for log in $LOGS; do
        echo "  $i - $(basename $log) ($(du -h $log | cut -f1))"
        LOG_FILES[$i]=$log
        i=$((i+1))
    done
    echo "  0 - Voltar"
    echo ""
    read -p "Selecione um log para visualizar: " choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        return
    fi
    
    if [ -n "${LOG_FILES[$choice]}" ] && [ -f "${LOG_FILES[$choice]}" ]; then
        clear
        echo "📄 Visualizando: $(basename ${LOG_FILES[$choice]})"
        echo "═══════════════════════════════════════════════"
        echo ""
        tail -50 "${LOG_FILES[$choice]}"
        echo ""
        echo "═══════════════════════════════════════════════"
        echo "Pressione ENTER para voltar..."
        read
    else
        echo "❌ Opção inválida!"
        sleep 2
    fi
}

test_proxy() {
    show_banner
    echo "🧪 TESTANDO ZXPROXY"
    echo "═══════════════════"
    echo ""
    
    # Verifica se há portas ativas
    ACTIVE_PORTS=""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            if ps -p $(cat "$pidfile") > /dev/null 2>&1; then
                ACTIVE_PORTS="$ACTIVE_PORTS $PORT"
            fi
        fi
    done
    
    if [ -z "$ACTIVE_PORTS" ]; then
        echo "❌ Nenhuma porta ativa. Abra uma porta primeiro."
        echo ""
        read -p "Pressione ENTER para continuar..."
        return
    fi
    
    # Usa a primeira porta ativa
    PORT=$(echo $ACTIVE_PORTS | awk '{print $1}')
    PROXY_URL="http://localhost:${PORT}"
    
    echo "🔍 Testando proxy em localhost:${PORT}"
    echo ""
    
    # Teste HTTP
    echo -n "   HTTP Proxy... "
    if curl -s -x ${PROXY_URL} -I https://example.com --connect-timeout 5 > /dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ FALHA"
    fi
    
    # Teste HTTPS
    echo -n "   HTTPS CONNECT... "
    if curl -s -x ${PROXY_URL} -I https://example.com --connect-timeout 5 > /dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ FALHA"
    fi
    
    # Teste SOCKS5
    echo -n "   SOCKS5... "
    if curl -s --socks5 localhost:${PORT} https://example.com --connect-timeout 5 > /dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ FALHA"
    fi
    
    echo ""
    echo "✅ Testes concluídos!"
    echo ""
    read -p "Pressione ENTER para continuar..."
}

# Loop principal
while true; do
    show_menu
    read OPTION
    case $OPTION in
        1) open_port ;;
        2) close_port ;;
        3) show_status ;;
        4) show_logs ;;
        5) test_proxy ;;
        6) 
            echo ""
            echo "👋 Saindo do ZXProxy Manager..."
            echo "Até logo!"
            exit 0 
            ;;
        *) 
            echo "❌ Opção inválida!" 
            sleep 2 
            ;;
    esac
done
