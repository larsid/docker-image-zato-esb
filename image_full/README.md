

# 🚀 Zato ESB Custom Image for Soft-IoT

Este repositório contém a infraestrutura como código para construir, configurar e orquestrar uma imagem Docker personalizada do **Zato ESB 4.1**. 

Esta solução foi projetada especificamente para atuar como um Gateway para sistemas de **Internet of Things (IoT)**, integrando nativamente um broker MQTT (Mosquitto), schedulers customizados em Python e comunicação offline (Air-Gapped).

---

## 🏗️ A Arquitetura de Duas Imagens

Para garantir estabilidade absoluta, zero quebras por atualizações surpresas na internet e inicialização rápida, o fluxo de infraestrutura deste projeto é dividido em **duas imagens distintas** hospedadas no Docker Hub.

### 1. A Imagem Base (Digest)
* **Repositório:** `rhianpablo11/esb-zato-soft-iot`
* **Objetivo:** Servir como base do projeto.
* **Como funciona:** Ela é construída a partir da imagem oficial do Zato, travada por um hash criptográfico (Digest SHA256) para garantir que seja imutável e não sofra com as atualizações da imagem oficial. Durante o build, os scripts oficiais do Zato são limitados: removemos o Git, desativamos o `pip install` automático e apagamos cronjobs de atualização.
* **Uso:** É usada para instalar pacotes pesados do zero. Quando executada, ela realiza a construção inicial do Cluster Zato e do banco de dados SQLite.

### 2. A Imagem Congelada
* **Repositório:** `rhianpablo11/zato-base-congelada`
* **Objetivo:** Inicialização rápida e prevenção contra atualizações.
* **Como funciona:** É um *Snapshot* (foto) tirado de um container rodando a Imagem Base após ele ter construído todo o banco de dados e as tabelas internas do Zato.
* **Uso:** Como o banco já está pronto na imagem, ela pula a fase de "Quickstart" pesada, apenas injeta as variáveis de ambiente atuais (senhas, portas) e liga o sistema.

---

## 🛠️ Guia de Operações e Comandos

Aqui estão os comandos fundamentais para operar a infraestrutura do repositório.

### 🔨 1. Construindo a Imagem Base (Digest)
Se você modificou o `Dockerfile` principal e precisa gerar uma nova imagem "do zero", execute:
```bash
# Compila a imagem localmente usando a tag desejada
docker build -f Dockerfile -t esb-zato-soft-iot:latest .

```

### ❄️ 2. Gerando a Imagem Congelada

Para gerar a imagem de inicialização rápida a partir de um container recém-criado:

```bash
# 1. Suba um container usando a Imagem Base e espere o Zato iniciar completamente.
# 1.1 Para isso utilize a pasta de blueprint que esta no repositorio
# 2. Identifique o nome do container rodando (ex: zato-node-1)
docker ps

# 3. Congele o estado do container em uma nova imagem
docker commit zato-node-1 zato-base-congelada:v1

```

### 🔄 3. Como Evoluir a Imagem Congelada (Adicionar Bibliotecas)

Você não precisa recriar todo o cluster para adicionar um pacote novo. Basta usar a estratégia de camadas (*Layering*). Crie um `Dockerfile` simples apontando para a sua imagem congelada:

```dockerfile
# Usa a imagem congelada como base
FROM zato-base-congelada:v1

# Instala a nova biblioteca (Ex: pandas) direto no ambiente do Zato
USER root
RUN su - zato -c "/opt/zato/current/bin/pip install pandas"

# O Entrypoint continua o mesmo
ENTRYPOINT ["/usr/local/bin/start_wrapper.sh"]

```


---

## 🧰 Comandos Úteis

Comandos rápidos para o dia a dia da administração dos containers:

| Comando | Para que serve |
| --- | --- |
| `./run-container.sh 1` | Script principal (Blueprint). Sobe o container isolado de forma idempotente, injetando o código, arquivos e variáveis do host. O `1` define o ID das portas (offset). |
| `docker logs -f zato-node-1` | Exibe os logs do container em tempo real (modo *follow*). Excelente para debugar o Python Scheduler e o MQTT. Pressione `Ctrl+C` para sair. |
| `docker exec -it zato-node-1 bash` | Abre um terminal interativo dentro do container rodando (como usuário *root*). |
| `docker exec -it -u zato zato-node-1 bash` | Abre um terminal interativo logado diretamente como o usuário `zato`. |
| `docker rm -f zato-node-1` | Força a parada e a exclusão do container. Como os dados não persistentes são efêmeros, isso "reseta" o ambiente. |
| `docker images` | Lista todas as imagens baixadas ou construídas na sua máquina, com seus respectivos tamanhos e tags. |
| `docker system prune` | **Cuidado!** Limpa containers parados, redes não usadas e imagens soltas, liberando espaço no HD do servidor. |

---

## 🔒 Variáveis de Ambiente e Segurança

O script de inicialização `start_wrapper.sh` (e o `entrypoint.sh` modificado) possui inteligência de **Idempotência**.
Mesmo utilizando a Imagem Congelada, senhas como `Zato_Dashboard_Password` informadas no `run-container.sh` são **dinâmicas**. O sistema atualiza as credenciais no SQLite a cada boot, mantendo a flexibilidade da configuração sem sacrificar a velocidade de inicialização.

