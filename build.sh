#!/bin/bash

set -e

# Configurações
IMAGE_NAME="aws-s3-gc"
IMAGE_TAG="latest"
RETENTION_DAYS=${1:-7}

echo "🔨 Construindo imagem Docker AWS S3 Garbage Collector"
echo "📦 Nome da imagem: $IMAGE_NAME:$IMAGE_TAG"
echo "📅 Retenção padrão: $RETENTION_DAYS dias"

# Build da imagem
docker build \
  --build-arg BACKUP_RETENTION_DAYS=$RETENTION_DAYS \
  -t $IMAGE_NAME:$IMAGE_TAG \
  .

echo "✅ Imagem construída com sucesso!"
echo ""
echo "🚀 Exemplos de uso:"
echo ""
echo "# Teste da funcionalidade de ajuda:"
echo "docker run --rm $IMAGE_NAME:$IMAGE_TAG help"
echo ""
echo "# Garbage collection (dry-run):"
echo "docker run --rm -e KEY=xxx -e SECRET=xxx -e REGION=us-east-1 -e BUCKET=my-bucket -e DRY_RUN=true $IMAGE_NAME:$IMAGE_TAG gc"
echo ""
echo "# Usando docker-compose:"
echo "cd examples/ && cp .env.example .env"
echo "# (edite o .env com suas credenciais)"
echo "docker-compose -f docker-compose-one-shot.yml up"