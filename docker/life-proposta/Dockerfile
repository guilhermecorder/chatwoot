# Gerador de PDF da LIFE (proposta do cliente + justificativa do orçamento) como serviço.
# É o mesmo gerador aprovado (Python + Chrome sem janela); o Sistema LIFE manda os dados e recebe os PDFs.
#   docker build -t life-proposta-pdf docker/life-proposta
#   docker run -p 3041:3041 -e GERADOR_TOKEN=... life-proposta-pdf
ARG BASE=alpine:3.24
FROM ${BASE}

# Chromium + a fonte Inter (a mais próxima da fonte do iPhone, que só existe no Mac) + Pillow (card de resumo em JPG)
RUN apk add --no-cache chromium python3 py3-pillow font-inter ttf-liberation

ENV CHROME=/usr/bin/chromium \
    CHROME_FLAGS="--no-sandbox --disable-dev-shm-usage" \
    GUARDAR_EM=nao \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY . /app

EXPOSE 3041
CMD ["python3", "servidor.py", "--endereco", "0.0.0.0", "--porta", "3041"]
