# ==============================================================================
# 1. CONGELAMENTO DA IMAGEM BASE (DIGEST)
# ==============================================================================
# !!! ATENÇÃO: Substitua o "COLOQUE_SEU_HASH_AQUI" pelo hash real da sua imagem.
# Para descobrir o hash da imagem que você já tem na máquina e sabe que funciona, 
# rode no seu terminal: docker images --digests zatosource/zato-4.1
FROM zatosource/zato-4.1@sha256:929dd84fac14bbc274813221a1ff85f712e4eac6c01f64e0cacaf75e4e1ee719

#VARIAVEIS DE AMBIENTE
ENV Zato_Log_Env_Details=True

#MAPEAMENTO DE PORTAS
# Adicionei 1883 (MQTT TCP) e 9001 (MQTT Websocket)
EXPOSE 22 8183 11223 17010 1883 9001

#RODAR COMANDOS DENTRO DO CONTAINER
# Adicionei 'mosquitto' na lista de instalação do apt-get
RUN apt-get update && apt-get install -y git mosquitto net-tools iproute2 iputils-ping ethtool && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# 2. INJEÇÃO DA VACINA (ENTRYPOINT MODIFICADO E REMOÇÃO DO UPDATE.SH)
# ==============================================================================
# !!! Aqui nós copiamos o seu entrypoint.sh "castrado" por cima do original
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# !!! Aqui nós deletamos o script original de atualização do Zato por segurança
RUN rm -f /opt/zato/current/update.sh

# === INSTALAÇÃO DE DEPENDÊNCIAS PYTHON ===
# 1. Copia o arquivo requirements.txt para uma pasta temporária no container
COPY requirements.txt /tmp/requirements.txt

# 2. Instala os pacotes listados no arquivo usando o pip do Zato
RUN /opt/zato/current/bin/pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Instalação do pacote Tatu Wrapper
# !!! DICA EXTRA DE BLINDAGEM: Se possível, adicione um 'git checkout <hash>' 
# logo após o clone para travar a versão do Tatu Wrapper também!
RUN git clone https://github.com/larsid/extended-tatu-wrapper.git /tmp/meu-pacote \
    && /opt/zato/current/bin/pip install /tmp/meu-pacote/python-version \
    && rm -rf /tmp/meu-pacote


# ==============================================================================
# TIRO DE MISERICÓRDIA: DELETAR O GIT DA IMAGEM
# ==============================================================================
# Isso garante que nenhum script futuro do Zato (ou qualquer outra coisa)
# consiga atualizar código usando git.
RUN rm -f /usr/bin/git



# === CONFIGURAÇÃO DO MOSQUITTO ===
# Criamos a pasta se não existir e copiamos seu arquivo conf
RUN mkdir -p /etc/mosquitto/
COPY mosquitto.conf /etc/mosquitto/mosquitto.conf

#COPIA DE ARQUIVOS DO PROJETO
COPY custom_scheduler.py /home/ubuntu/mapping_archives/
COPY start_wrapper.sh /usr/local/bin/start_wrapper.sh

# Dar permissão de execução no wrapper
RUN chmod +x /usr/local/bin/start_wrapper.sh

ENTRYPOINT ["/usr/local/bin/start_wrapper.sh"]