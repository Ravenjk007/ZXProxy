#!/bin/bash
ZXPROXY="/opt/zxproxy/proxy"
PID_FILE="/tmp/zxproxy_"

show_menu() {
    clear
    echo "====================================="
    echo "          ZXProxy Menu              "
    echo "====================================="
    echo ""
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
    if [ -n "$ACTIVE_PORTS" ]; then
        echo "Porta(s) aberta(s):$ACTIVE_PORTS"
    else
        echo "Porta(s): nenhuma"
    fi
    echo ""
    echo " 1 - Abrir Porta"
    echo " 2 - Fechar Porta"
    echo " 3 - Status do Proxy"
    echo " 4 - Ver Logs"
    echo " 5 - Sair"
    echo ""
    echo -n "--> Selecione uma opção: "
}

open_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    
    # Matar processo na porta se existir
    sudo fuser -k $PORT/tcp 2>/dev/null
    
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    
    echo "🔓 Abrindo porta ${PORT}..."
    if [ ! -f "$ZXPROXY" ]; then
        echo "❌ ZXProxy não encontrado!"
        sleep 3
        return
    fi
    
    # Iniciar com keep-alive
    if [ "$PORT" -lt 1024 ]; then
        nohup sudo ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    else
        nohup ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    fi
    
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 3
    
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo "✅ Porta ${PORT} aberta com Keep-Alive!"
        echo "📝 Log: /tmp/zxproxy_${PORT}.log"
        echo "💓 Conexão mantida viva para VPN/HTTP Inject"
    else
        echo "❌ Falha ao abrir porta ${PORT}!"
        rm -f "${PID_FILE}${PORT}.pid"
        echo "📝 Verifique o log:"
        tail -n 10 "/tmp/zxproxy_${PORT}.log" 2>/dev/null
    fi
    sleep 2
}

close_port() {
    read -p "Digite o número da porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Porta inválida!"
        sleep 2
        return
    fi
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        sudo kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo "✅ Porta ${PORT} fechada!"
    else
        echo "❌ Porta ${PORT} não está aberta!"
    fi
    sleep 2
}

show_status() {
    echo "📊 Status do ZXProxy:"
    echo "===================="
    echo ""
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            PID=$(cat "$pidfile")
            if ps -p $PID > /dev/null 2>&1; then
                echo "✅ Porta $PORT: ativa (PID: $PID)"
                echo "   Log: /tmp/zxproxy_${PORT}.log"
                echo "   Keep-Alive: Ativo"
            else
                echo "❌ Porta $PORT: processo morto"
                rm -f "$pidfile"
            fi
        fi
    done
    
    echo ""
    echo "🔍 Portas em uso:"
    sudo ss -tlnp | grep zxproxy || echo "   Nenhuma porta ativa"
    echo ""
    read -p "Pressione Enter para continuar..."
}

show_logs() {
    echo "📝 Logs do ZXProxy:"
    echo "==================="
    echo ""
    ls -la /tmp/zxproxy_*.log 2>/dev/null || echo "Nenhum log encontrado"
    echo ""
    read -p "Digite a porta para ver o log (ou Enter para sair): " PORT
    if [ -n "$PORT" ] && [ -f "/tmp/zxproxy_${PORT}.log" ]; then
        echo ""
        echo "=== Últimas 30 linhas do log da porta ${PORT} ==="
        echo ""
        tail -n 30 "/tmp/zxproxy_${PORT}.log"
        echo ""
        read -p "Pressione Enter para continuar..."
    fi
}

while true; do
    show_menu
    read OPTION
    case $OPTION in
        1) open_port ;;
        2) close_port ;;
        3) show_status ;;
        4) show_logs ;;
        5) echo "👋 Saindo..."; exit 0 ;;
        *) echo "❌ Opção inválida!"; sleep 2 ;;
    esac
done
