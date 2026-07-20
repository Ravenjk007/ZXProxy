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
    echo " 3 - Status"
    echo " 4 - Ver Logs"
    echo " 5 - Sair"
    echo ""
    echo -n "--> "
}

open_port() {
    read -p "Digite a porta: " PORT
    if [[ -z "$PORT" ]]; then
        echo "❌ Inválida!"
        sleep 2
        return
    fi
    sudo fuser -k $PORT/tcp 2>/dev/null
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    echo "🔓 Abrindo porta ${PORT}..."
    if [ "$PORT" -lt 1024 ]; then
        nohup sudo ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    else
        nohup ${ZXPROXY} -p ${PORT} > "/tmp/zxproxy_${PORT}.log" 2>&1 &
    fi
    echo $! > "${PID_FILE}${PORT}.pid"
    sleep 2
    if ps -p $(cat "${PID_FILE}${PORT}.pid") > /dev/null 2>&1; then
        echo "✅ Porta ${PORT} aberta!"
    else
        echo "❌ Falha!"
        rm -f "${PID_FILE}${PORT}.pid"
    fi
    sleep 2
}

close_port() {
    read -p "Digite a porta: " PORT
    if [[ -f "${PID_FILE}${PORT}.pid" ]]; then
        PID=$(cat "${PID_FILE}${PORT}.pid")
        sudo kill -9 $PID 2>/dev/null
        rm -f "${PID_FILE}${PORT}.pid"
        echo "✅ Porta ${PORT} fechada!"
    else
        echo "❌ Porta não está aberta!"
    fi
    sleep 2
}

show_status() {
    echo "📊 Status:"
    for pidfile in ${PID_FILE}*.pid; do
        if [ -f "$pidfile" ]; then
            PORT=$(basename "$pidfile" .pid | sed 's/zxproxy_//')
            PID=$(cat "$pidfile")
            if ps -p $PID > /dev/null 2>&1; then
                echo "✅ Porta $PORT: ativa (PID: $PID)"
            fi
        fi
    done
    echo ""
    read -p "Enter..."
}

show_logs() {
    echo "📝 Logs:"
    tail -n 30 /tmp/zxproxy_*.log 2>/dev/null || echo "Nenhum log"
    echo ""
    read -p "Enter..."
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
        *) echo "❌ Inválido!"; sleep 2 ;;
    esac
done
