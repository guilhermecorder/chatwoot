#!/usr/bin/env python3
"""Gerador de PDF da LIFE como serviço: o Sistema LIFE manda os dados do orçamento e recebe os documentos.

    python3 servidor.py            -> escuta em http://127.0.0.1:3041
    python3 servidor.py --porta 3041 --endereco 127.0.0.1

    POST /gerar   { "proposta": {...}, "justificativa": {...} }   (o que Crm::KitQuote::Proposal monta)
      200 -> { "arquivos": [{ "nome", "tipo", "base64" }], "avisos": [...], "pasta": "..." }
      422 -> { "erro": "Falta o campo ..." }
    GET  /saude   -> { "ok": true }

Usa os mesmos geradores aprovados (gerar.py e gerar_justificativa.py): nada de desenho novo aqui.
Cada pedido fica guardado em ../clientes/_do-sistema/<cliente>-<data-hora>/ (JSONs, PDFs e o card de resumo);
no servidor de produção (GUARDAR_EM=nao) não guarda nada, porque lá o sistema guarda no cliente.
Variáveis: GERADOR_TOKEN (senha de serviço), GUARDAR_EM, CHROME (caminho do navegador), CHROME_FLAGS.
Só aceita os campos do orçamento: os textos e as fotos fixas (life.json) não podem ser trocados por quem chama.
"""
import argparse
import base64
import datetime as dt
import hmac
import json
import os
import re
import sys
import tempfile
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

AQUI = Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
import gerar  # noqa: E402
import gerar_justificativa  # noqa: E402

# Onde cada pedido fica guardado. GUARDAR_EM=nao (no servidor de produção) não guarda nada:
# lá quem guarda é o próprio sistema, no cliente.
GUARDAR_EM = os.environ.get("GUARDAR_EM") or str(AQUI.parent / "clientes" / "_do-sistema")
# Senha de serviço (opcional): com GERADOR_TOKEN definido, só atende quem mandar "Authorization: Bearer <token>".
TOKEN = os.environ.get("GERADOR_TOKEN", "")
CAMPOS_DA_PROPOSTA = ("cliente", "proposta", "conta", "telhado", "sistema", "garantias", "economia", "investimento")
CAMPOS_DA_JUSTIFICATIVA = ("cliente", "cidade", "data", "resumo", "consumo", "sistema", "kit", "adequacao", "custos",
                           "preco", "conferir", "fonte")
LIMITE = 2_000_000  # bytes do pedido


def slug(texto):
    texto = unicodedata.normalize("NFKD", str(texto)).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-zA-Z0-9]+", "-", texto).strip("-") or "Cliente"


def montar_documentos(pedido):
    """Gera os dois PDFs e o card de resumo. Devolve (arquivos, avisos, pasta). Levanta gerar.Erro."""
    if not isinstance(pedido.get("proposta"), dict) or not isinstance(pedido.get("justificativa"), dict):
        raise gerar.Erro("O pedido precisa trazer \"proposta\" e \"justificativa\".")
    proposta = {k: v for k, v in pedido["proposta"].items() if k in CAMPOS_DA_PROPOSTA}
    justificativa = {k: v for k, v in pedido["justificativa"].items() if k in CAMPOS_DA_JUSTIFICATIVA}
    nome = slug(gerar.pegar(proposta, "cliente.nome"))
    if GUARDAR_EM == "nao":
        with tempfile.TemporaryDirectory(prefix="pedido-") as tmp:
            arquivos, avisos = gerar_em(Path(tmp), nome, proposta, justificativa)
        return arquivos, avisos, None
    pasta = Path(GUARDAR_EM) / f"{nome.lower()}-{dt.datetime.now():%Y-%m-%d-%H%M%S}"
    pasta.mkdir(parents=True, exist_ok=True)
    arquivos, avisos = gerar_em(pasta, nome, proposta, justificativa)
    return arquivos, avisos, pasta


def gerar_em(pasta, nome, proposta, justificativa):
    (pasta / "proposta.json").write_text(json.dumps(proposta, ensure_ascii=False, indent=2), encoding="utf-8")
    (pasta / "justificativa.json").write_text(json.dumps(justificativa, ensure_ascii=False, indent=2), encoding="utf-8")

    avisos = []
    _, _, a = gerar.gerar(proposta, pasta / f"Proposta-{nome}.pdf", resumo_jpg=pasta / f"Resumo-{nome}.jpg")
    avisos += [f"Proposta: {x}" for x in a]
    _, _, a = gerar_justificativa.gerar(justificativa, pasta / f"Justificativa-{nome}.pdf")
    avisos += [f"Justificativa: {x}" for x in a]

    tipos = {".pdf": "application/pdf", ".jpg": "image/jpeg", ".png": "image/png"}
    arquivos = [
        {"nome": arq.name, "tipo": tipos[arq.suffix], "base64": base64.b64encode(arq.read_bytes()).decode()}
        for arq in sorted(pasta.iterdir(), key=lambda p: (p.suffix != ".pdf", not p.name.startswith("Proposta"), p.name))
        if arq.suffix in tipos
    ]
    return arquivos, avisos


class Pedido(BaseHTTPRequestHandler):
    server_version = "GeradorLife/1"

    def responder(self, status, corpo):
        dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        if self.path.rstrip("/") == "/saude":
            return self.responder(200, {"ok": True})
        return self.responder(404, {"erro": "Não existe."})

    def do_POST(self):
        if self.path.rstrip("/") != "/gerar":
            return self.responder(404, {"erro": "Não existe."})
        if TOKEN and not hmac.compare_digest(self.headers.get("Authorization", ""), f"Bearer {TOKEN}"):
            return self.responder(401, {"erro": "Sem a senha de serviço."})
        tamanho = int(self.headers.get("Content-Length") or 0)
        if not 0 < tamanho <= LIMITE:
            return self.responder(413, {"erro": "Pedido vazio ou grande demais."})
        try:
            pedido = json.loads(self.rfile.read(tamanho).decode("utf-8"))
            arquivos, avisos, pasta = montar_documentos(pedido)
        except (json.JSONDecodeError, UnicodeDecodeError):
            return self.responder(400, {"erro": "O pedido não é um JSON válido."})
        except gerar.Erro as erro:
            return self.responder(422, {"erro": str(erro)})
        except Exception as erro:  # noqa: BLE001 (o serviço não pode cair por causa de um pedido)
            return self.responder(500, {"erro": f"Falha ao gerar: {type(erro).__name__}: {erro}"})
        return self.responder(200, {"arquivos": arquivos, "avisos": avisos, "pasta": str(pasta) if pasta else None})

    def log_message(self, formato, *args):
        sys.stderr.write(f"{dt.datetime.now():%H:%M:%S} {formato % args}\n")


def main():
    ap = argparse.ArgumentParser(description="Gerador de PDF da LIFE (proposta + justificativa) como serviço.")
    ap.add_argument("--porta", type=int, default=3041)
    ap.add_argument("--endereco", default="127.0.0.1", help="onde escutar (padrão: só esta máquina)")
    a = ap.parse_args()
    servidor = ThreadingHTTPServer((a.endereco, a.porta), Pedido)
    print(f"Gerador de PDF da LIFE em http://{a.endereco}:{a.porta} (POST /gerar). Ctrl+C para parar.")
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
