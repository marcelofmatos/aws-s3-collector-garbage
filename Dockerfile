FROM futurevision/aws-s3-sync:latest

# Configuração da variável de retenção de backups
ARG BACKUP_RETENTION_DAYS=7
ENV BACKUP_RETENTION_DAYS=$BACKUP_RETENTION_DAYS

# Instalação de ferramentas adicionais necessárias para o garbage collector
RUN apk add --no-cache \
    coreutils \
    findutils \
    grep \
    sed \
    bc

# Copia os scripts customizados
COPY scripts/garbage-collector.sh /usr/local/bin/garbage-collector.sh
COPY scripts/start.sh /start.sh

# Torna os scripts executáveis
RUN chmod +x /usr/local/bin/garbage-collector.sh /start.sh

# Define o entrypoint customizado
ENTRYPOINT ["/start.sh"]

# Labels para documentação
LABEL maintainer="Marcelo Matos <contato@marcelomatos.dev>"
LABEL description="AWS S3 Garbage Collector baseado em futurevision/aws-s3-sync"
LABEL version="1.0.0"