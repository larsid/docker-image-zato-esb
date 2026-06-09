#!/bin/bash

echo "🚀 Iniciando Arquitetura Limpa (Total Control via SiteCustomize)..."

service redis-server start
/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto.conf -d
sleep 2

cat << 'EOF' > /opt/zato/start_zato.sh
#!/bin/bash

ZATO_ENV="/opt/zato/env/qs-1"

if [ ! -d "$ZATO_ENV/server1" ]; then
    echo "⚙️ Construindo cluster do zero..."
    zato quickstart $ZATO_ENV --odb-type sqlite --cluster-name 'cluster1'
    zato update password $ZATO_ENV/web-admin admin --password 'admin123'
fi

# Ligamos o Zato do jeito que os desenvolvedores planejaram, 
# sabendo que a nossa vacina no Python vai proteger a memória.
echo "🟢 Start Nativo Zato Componentes..."
bash $ZATO_ENV/zato-qs-start.sh

echo "⏰ Iniciando Custom Scheduler Externo..."
/opt/zato/current/bin/python /home/ubuntu/mapping_archives/custom_scheduler.py &

echo "✅ Sistema Online. Monitorando Logs..."
while [ ! -f $ZATO_ENV/server1/logs/server.log ]; do sleep 1; done
tail -F $ZATO_ENV/server1/logs/server.log
EOF

chmod +x /opt/zato/start_zato.sh

exec sudo -u zato bash /opt/zato/start_zato.sh