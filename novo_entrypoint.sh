#!/bin/bash

echo "🚀 Iniciando infraestrutura Zato Clean (Ubuntu 24.04)..."
echo "🛠️ Aplicando bypass definitivo para os bugs do Zato CLI..."

# ==========================================
# 1. SERVIÇOS ROOT
# ==========================================
echo "📦 Subindo Redis e Broker MQTT..."
service redis-server start
/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto.conf &
sleep 2

# ==========================================
# 2. SCRIPT DE INICIALIZAÇÃO BLINDADO
# Criamos um script exclusivo para o usuário 'zato' rodar sem perder a memória
# ==========================================
cat << 'EOF' > /opt/zato/run_zato.sh
#!/bin/bash

# A) Força os caminhos absolutos (Resolve o erro do 'paste')
export PATH=$PATH:/opt/zato/current/bin
export PYTHONPATH=$PYTHONPATH:/opt/zato/current/extlib
export Zato_Is_Docker=True
ZATO_ENV="/opt/zato/env/qs-1"

# B) Tradutor Nativo de env.ini (Resolve o erro do Zato_Broker_Protocol)
if [ -f "/opt/hot-deploy/enmasse/env.ini" ]; then
    echo "📥 Injetando variáveis na memória do container..."
    # Limpa as linhas [env] e carrega nativamente no Linux
    grep -E -v '^[[:space:]]*$|^\[.*\]' "/opt/hot-deploy/enmasse/env.ini" > /tmp/clean.env
    set -a
    source /tmp/clean.env
    set +a
fi

# C) Criação do Cluster (Se for a primeira vez)
if [ ! -d "$ZATO_ENV/server1" ]; then
    echo "⚙️ Criando cluster Zato..."
    zato quickstart $ZATO_ENV --odb-type sqlite --cluster-name 'cluster1'
    zato update password $ZATO_ENV/web-admin admin --password 'admin123'
fi

# D) Ligando os componentes (SEM o --env-file para não acionar o bug do Zato)
echo "🟢 Ligando componentes..."
zato start $ZATO_ENV/scheduler --fg &
sleep 3
zato start $ZATO_ENV/server1 --fg &
sleep 5
zato start $ZATO_ENV/web-admin --fg &
sleep 3

# E) Custom Scheduler
echo "⏰ Iniciando Custom Scheduler Externo..."
/opt/zato/current/bin/python /home/ubuntu/mapping_archives/custom_scheduler.py &

# F) Mantém o container vivo
while [ ! -f $ZATO_ENV/server1/logs/server.log ]; do sleep 1; done
tail -F $ZATO_ENV/server1/logs/server.log
EOF

chmod +x /opt/zato/run_zato.sh

# ==========================================
# 3. EXECUÇÃO FINAL
# Usamos sudo -E para preservar TODAS as variáveis de ambiente e não quebrar nada
# ==========================================
exec sudo -E -u zato bash /opt/zato/run_zato.sh