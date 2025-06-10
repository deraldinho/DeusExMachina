#!/bin/bash
# Script para instalar, configurar e criar um serviço systemd para o ngrok.

# Configurações para um script mais robusto
set -euo pipefail

echo "---------------------------------------------------------------------"
echo "🌍 A iniciar a instalação e configuração completa do ngrok..."
echo "---------------------------------------------------------------------"

# --- Variáveis (serão passadas pelo Vagrantfile) ---
# Se as variáveis não forem passadas, usamos valores padrão
NGROK_AUTHTOKEN="${NGROK_AUTHTOKEN:-}" # Fornece um valor padrão vazio se a variável for indefinida
NGROK_STATIC_DOMAIN="${NGROK_STATIC_DOMAIN:-pigeon-adjusted-early.ngrok-free.app}"
N8N_HOST_IP="${N8N_HOST_IP:-192.168.56.10}"
N8N_PORT="5678"

# --- Parte 1: Instalação do Binário do ngrok ---

# Função para verificar se um comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if command_exists ngrok; then
    echo "✅ ngrok já está instalado. Versão: $(ngrok --version)"
else
    echo "   ngrok não encontrado. A iniciar a instalação via APT..."
    
    # Garante que as dependências para adicionar repositórios estejam presentes
    sudo apt-get update -y -qq
    sudo apt-get install -y -qq curl gpg

    # Adicionar a chave GPG do repositório do ngrok
    echo "   A adicionar a chave GPG do ngrok..."
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | \
      sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null

    # Adicionar o repositório APT do ngrok
    echo "   A adicionar o repositório APT do ngrok..."
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | \
      sudo tee /etc/apt/sources.list.d/ngrok.list

    # Instalar o ngrok via APT
    echo "   A atualizar o APT e a instalar o pacote ngrok..."
    sudo apt-get update -y -qq
    sudo apt-get install -y ngrok
    
    echo "✅ ngrok instalado com sucesso!"
    ngrok --version
fi

# --- Parte 2: Configuração do Authtoken ---

# A sintaxe ${NGROK_AUTHTOKEN:-} (implícita na definição da variável no topo)
# evita o erro "unbound variable" com 'set -u'.
if [ -n "${NGROK_AUTHTOKEN}" ]; then
    echo "   A configurar o authtoken do ngrok automaticamente..."
    # Executa o comando como o utilizador 'vagrant'
    sudo -u vagrant ngrok config add-authtoken "${NGROK_AUTHTOKEN}"
    echo "✅ Authtoken do ngrok configurado para o utilizador 'vagrant'."
else
    echo "⚠️  AVISO: Nenhuma variável NGROK_AUTHTOKEN encontrada."
    echo "👉 Para configurar manualmente, aceda à VM com 'vagrant ssh' e execute: ngrok config add-authtoken SEU_TOKEN"
fi

# --- Parte 3: Criação do Serviço Systemd ---

# Descobre o caminho real do executável do ngrok
NGROK_PATH=$(command -v ngrok)
if [ -z "$NGROK_PATH" ]; then
    echo "❌ Erro Crítico: O comando ngrok não foi encontrado no PATH após a instalação."
    exit 1
fi
echo "   Caminho do executável ngrok encontrado em: ${NGROK_PATH}"

SERVICE_FILE="/etc/systemd/system/ngrok.service"

echo "🚇 A criar e a habilitar o serviço systemd para o ngrok..."
echo "   A configurar o serviço para o domínio: ${NGROK_STATIC_DOMAIN}"
echo "   A apontar para o endereço: ${N8N_HOST_IP}:${N8N_PORT}"

# Criar o ficheiro de serviço do systemd usando o caminho correto
sudo bash -c "cat > ${SERVICE_FILE}" << EOF
[Unit]
Description=Ngrok Tunnel Service for n8n
After=network-online.target

[Service]
Type=simple
User=vagrant
# Usa a variável NGROK_PATH para o caminho exato do executável
ExecStart=${NGROK_PATH} http --domain=${NGROK_STATIC_DOMAIN} ${N8N_HOST_IP}:${N8N_PORT}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Ficheiro de serviço criado em ${SERVICE_FILE}."

# Recarregar o systemd, habilitar e iniciar o serviço
echo "   A recarregar o daemon do systemd..."
sudo systemctl daemon-reload

echo "   A habilitar o serviço ngrok para iniciar no boot..."
sudo systemctl enable ngrok.service

echo "   A iniciar o serviço ngrok agora..."
sudo systemctl start ngrok.service

# Verificar o estado do serviço
echo "   A verificar o estado do serviço..."
sleep 2
if systemctl is-active --quiet ngrok.service; then
    echo "✅ Serviço ngrok está ativo e a rodar."
else
    echo "❌ Serviço ngrok falhou ao iniciar. Verifique os logs com: journalctl -u ngrok.service"
fi

echo "---------------------------------------------------------------------"
echo "✅ Instalação e configuração completa do ngrok concluída."
echo "   O túnel para '${NGROK_STATIC_DOMAIN}' agora está a rodar e iniciará automaticamente com a VM."
echo "---------------------------------------------------------------------"
