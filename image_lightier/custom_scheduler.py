import os
import time
import logging
import threading
import schedule  # pip install schedule
import requests
import yaml

# Configuração de Log
logging.basicConfig(level=logging.INFO, format='%(asctime)s - [EXTERNAL_SCHEDULER] - %(levelname)s - %(message)s')
logger = logging.getLogger()

# ========================================================================
# ROTEAMENTO DINÂMICO DE PORTAS 
# ========================================================================
# Verifica se o Load Balancer está ativo no ambiente
IS_LB_ENABLED = os.getenv("Zato_Start_Load_Balancer", "True").lower() in ("true", "1")

# Define a porta correta: 11223 se houver LB, ou 17010 se o Server1 estiver direto
ZATO_PORT = os.getenv("Zato_Port_Load_Balancer", "11223") if IS_LB_ENABLED else os.getenv("Zato_Port_Server", "17010")

ZATO_PING_URL = f"http://localhost:{ZATO_PORT}/zato/ping"
ENMASSE_FILE = "/opt/hot-deploy/enmasse/enmasse.yaml"

ZATO_USER = os.getenv("Zato_Dashboard_Password", "admin") 
ZATO_PASS = os.getenv("Zato_Dashboard_Password", "123456")

def wait_for_zato():
    """Loop que trava o script até o Zato responder ao Ping na porta ativa."""
    logger.info(f"Router: Detectada a porta ativa [{ZATO_PORT}]")
    logger.info(f"Aguardando Zato iniciar em {ZATO_PING_URL}...")
    
    while True:
        try:
            response = requests.get(ZATO_PING_URL, timeout=10)
            if response.status_code == 200:
                logger.info("Zato está ONLINE! Iniciando agendamento...")
                time.sleep(2) 
                return
        except requests.exceptions.RequestException:
            pass
        time.sleep(5)

def perform_request(job_name, url):
    """Executa o GET na URL configurada."""
    logger.info(f"Executando Job: '{job_name}' -> GET {url}")
    try:
        response = requests.get(url, timeout=10)
        if response.status_code < 400:
            logger.info(f"Sucesso [{response.status_code}]: '{job_name}'")
        else:
            logger.error(f"Erro [{response.status_code}]: '{job_name}' - {response.text[:100]}")
    except Exception as e:
        logger.error(f"Falha na requisição de '{job_name}': {e}")

def load_and_schedule():
    if not os.path.exists(ENMASSE_FILE):
        logger.error(f"Arquivo {ENMASSE_FILE} não encontrado!")
        return

    with open(ENMASSE_FILE, 'r') as f:
        config = yaml.safe_load(f)

    jobs = config.get('external_scheduler', [])
    if not jobs:
        logger.info("Nenhum job externo configurado.")
        return
    logger.info(f"Carregados {len(jobs)} jobs externos.")

    for job in jobs:
        name = job.get('name', 'Sem Nome')
        url = job.get('url')
        job_type = job.get('job_type')
        
        if not url:
            logger.warning(f"Job '{name}' ignorado: Sem URL configurada.")
            continue

        # 🔄 TRATAMENTO DO ENDPOINT: Se não começar com http, nós montamos a URL dinamicamente
        if not url.startswith("http"):
            if not url.startswith("/"):
                url = "/" + url
            url = f"http://localhost:{ZATO_PORT}{url}"

        if job_type == 'one_time':
            delay = int(job.get('initial_delay', 5))
            if delay <= 0:
                logger.info(f"Job '{name}' ignorado (delay <= 0).")
            else:
                logger.info(f"Agendado (Único): '{name}' para daqui a {delay}s")
                threading.Timer(delay, perform_request, args=[name, url]).start()

        elif job_type == 'interval_based':
            interval = int(job.get('interval', 60))
            unit = job.get('unit', 'seconds')
            
            if interval <= 0:
                logger.info(f"Job '{name}' ignorado (intervalo <= 0).")
            else:
                job_scheduler = schedule.every(interval)
                if unit == 'seconds':
                    job_scheduler.seconds.do(perform_request, name, url)
                elif unit == 'minutes':
                    job_scheduler.minutes.do(perform_request, name, url)
                elif unit == 'hours':
                    job_scheduler.hours.do(perform_request, name, url)
                    
                logger.info(f"Agendado (Recorrente): '{name}' a cada {interval} {unit}")

def main():
    wait_for_zato()
    load_and_schedule()
    
    logger.info("Scheduler ativo. Pressione Ctrl+C para parar.")
    while True:
        schedule.run_pending()
        time.sleep(1)

if __name__ == "__main__":
    main()