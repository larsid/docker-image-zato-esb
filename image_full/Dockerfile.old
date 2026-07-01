#IMAGEM BASE
FROM zatosource/zato-4.1

#VARIAVEIS DE AMBIENTE
ENV Zato_Log_Env_Details=True

#MAPEAMENTO DE PORTAS
# Adicionei 1883 (MQTT TCP) e 9001 (MQTT Websocket)
EXPOSE 22 8183 11223 17010 1883 9001

#RODAR COMANDOS DENTRO DO CONTAINER
# Adicionei 'mosquitto' na lista de instalação do apt-get
RUN apt-get update && apt-get install -y git mosquitto net-tools iproute2 iputils-ping ethtool && rm -rf /var/lib/apt/lists/*

# === INSTALAÇÃO DE DEPENDÊNCIAS PYTHON ===
# 1. Copia o arquivo requirements.txt para uma pasta temporária no container
COPY requirements.txt /tmp/requirements.txt

# 2. Instala os pacotes listados no arquivo usando o pip do Zato
RUN /opt/zato/current/bin/pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Instalação do pacote Tatu Wrapper (mantido via git clone)
RUN git clone https://github.com/larsid/extended-tatu-wrapper.git /tmp/meu-pacote \
    && /opt/zato/current/bin/pip install /tmp/meu-pacote/python-version \
    && rm -rf /tmp/meu-pacote

# === CONFIGURAÇÃO DO MOSQUITTO ===
# Criamos a pasta se não existir e copiamos seu arquivo conf
RUN mkdir -p /etc/mosquitto/
COPY mosquitto.conf /etc/mosquitto/mosquitto.conf

#COPIA DE ARQUIVOS DO PROJETO
#COPY ./devices.json /home/ubuntu/mapping_archives/
COPY custom_scheduler.py /home/ubuntu/mapping_archives/
COPY start_wrapper.sh /usr/local/bin/start_wrapper.sh

# Dar permissão de execução no wrapper
RUN chmod +x /usr/local/bin/start_wrapper.sh

ENTRYPOINT ["/usr/local/bin/start_wrapper.sh"]