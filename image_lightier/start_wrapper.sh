#!/bin/bash

# ==========================================================
# 1. CONFIGURAR E INICIAR MOSQUITTO (DYNAMIC AUTH)
# ==========================================================
echo "[WRAPPER] Iniciando Mosquitto Broker..."

# Executa o broker apontando para a config que copiamos no Dockerfile.
CONF_FILE="/etc/mosquitto/mosquitto.conf"
PASSWD_FILE="/etc/mosquitto/passwd"

# 🔐 Se o usuário passar credenciais via ambiente, injetamos a segurança dinamicamente
if [ -n "$Zato_MQTT_USER" ] && [ -n "$Zato_MQTT_PASS" ]; then
    echo "[MOSQUITTO] Configurando autenticação obrigatória para o usuário: '$Zato_MQTT_USER'..."
    
    # Garante que o arquivo existe antes de aplicar permissões
    touch "$PASSWD_FILE"
    
    # Cria/Reseta o arquivo de senhas do Mosquitto de forma segura (-b = via linha de comando, -c = limpa arquivo antigo)
    mosquitto_passwd -b -c "$PASSWD_FILE" "$Zato_MQTT_USER" "$Zato_MQTT_PASS"
    
    # 🔓 O PULO DO GATO: Libera a leitura para o usuário 'mosquitto' do sistema
    chmod 644 "$PASSWD_FILE"
    
    # Altera a configuração para proibir conexões sem senha
    sed -i 's/allow_anonymous true/allow_anonymous false/g' "$CONF_FILE"
    
    # Adiciona o caminho do arquivo de senhas se ele já não estiver configurado
    if ! grep -q "password_file" "$CONF_FILE"; then
        echo "password_file $PASSWD_FILE" >> "$CONF_FILE"
    fi
else
    echo "[MOSQUITTO] Nenhuma credencial informada. Rodando em modo aberto (allow_anonymous true)..."
    # Garante o estado padrão caso a imagem venha modificada
    sed -i 's/allow_anonymous false/allow_anonymous true/g' "$CONF_FILE"
    sed -i '/password_file/d' "$CONF_FILE"
fi

# Executa o broker apontando para a config atualizada em background
/usr/sbin/mosquitto -c "$CONF_FILE" &

# Uma pequena pausa de segurança para garantir que a porta 1883 abra
# antes que os outros serviços tentem conectar.
sleep 2


# ==========================================================
# 2. INICIAR SCHEDULER (SEU CÓDIGO ORIGINAL)
# ==========================================================
# Inicia o nosso scheduler customizado em background
# O output vai para o log do docker (stdout)
echo "[WRAPPER] Iniciando Scheduler Externo..."
/opt/zato/current/bin/python /home/ubuntu/mapping_archives/custom_scheduler.py &

echo "LIBERANDO ACESSO AO ZATO"
sudo chmod -R 777 /home/ubuntu/mapping_archives/


# ==========================================================
# 3. INICIAR ZATO (SEU CÓDIGO ORIGINAL)
# ==========================================================
# Inicia o processo original do Zato
# O "$@" garante que qualquer argumento passado no docker run seja respeitado
echo "[WRAPPER] Iniciando Zato..."
exec /entrypoint.sh "$@"