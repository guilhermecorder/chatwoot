#!/usr/bin/env python3
"""Gera a JUSTIFICATIVA do orçamento (documento interno: como se chegou ao preço), no mesmo visual da proposta.

    python3 gerar_justificativa.py justificativa.json                -> saida/justificativa-<cliente>-<data>.pdf
    python3 gerar_justificativa.py justificativa.json -o arquivo.pdf
    python3 gerar_justificativa.py justificativa.json --html         -> guarda também o HTML montado

Toda proposta sai com a sua justificativa (pedido do Guilherme, 11/11/2026).
Os números vêm prontos do JSON (o cotador calcula); aqui só se formata. Campos: ver README.md.
"""
import argparse
import html
import json
import re
import sys
import unicodedata
from pathlib import Path

from gerar import (AQUI, MODELO, Erro, arco, compilar, data_br, decimal, embutir, gerar_pdf, ler_data, lista,
                   montar, numero, reais)


def pct(fracao):
    """0.2503 -> '25,03%' · 1.06 -> '106%'"""
    return decimal(float(fracao) * 100, 2) + "%"


def kwh(valor):
    return decimal(valor, 2) if not float(valor).is_integer() else numero(valor)


def pegar(dados, caminho):
    atual = dados
    for parte in caminho.split("."):
        if not isinstance(atual, dict) or atual.get(parte) in (None, ""):
            raise Erro(f"Falta o campo \"{caminho}\" no JSON da justificativa.")
        atual = atual[parte]
    return atual


def preparar(d):
    f = {}
    for campo in ("cliente", "cidade", "resumo.valor_projeto", "resumo.custo_total", "resumo.lucro", "resumo.margem",
                  "consumo.linhas", "consumo.total_reais", "consumo.total_kwh", "consumo.tarifa",
                  "sistema.formula", "sistema.potencia_necessaria_kwp", "sistema.placas", "sistema.potencia_placa_w",
                  "sistema.potencia_kwp", "sistema.producao_kwh_mes", "sistema.cobertura", "sistema.equipamento",
                  "kit.regra", "kit.cotacoes", "kit.media", "adequacao.valor", "adequacao.faixa", "custos", "preco.regra",
                  "preco.faixa", "preco.socios", "preco.por_kwp", "conferir", "fonte"):
        pegar(d, campo)

    dia = ler_data(d["data"], "data") if d.get("data") else None
    f["data"] = data_br(dia) if dia else ""
    f["data_iso"] = dia.isoformat() if dia else "sem-data"

    r = d["resumo"]
    f["valor_projeto"], f["custo_total"], f["lucro"] = reais(r["valor_projeto"]), reais(r["custo_total"]), reais(r["lucro"])
    f["margem"] = pct(r["margem"])

    c = d["consumo"]
    f["consumo"] = [
        {"rotulo": l["rotulo"], "reais": reais(l["reais"]), "kwh": kwh(l["kwh"]), "nota": l.get("nota", ""), "mais": i > 0}
        for i, l in enumerate(lista(c["linhas"]))
    ]
    f["consumo_kwh"], f["consumo_reais"] = kwh(c["total_kwh"]), reais(c["total_reais"])
    f["tarifa"] = "R$ " + decimal(c["tarifa"], 3)

    s = d["sistema"]
    f["necessaria"], f["kwp"] = decimal(s["potencia_necessaria_kwp"]), decimal(s["potencia_kwp"])
    f["placa_w"], f["producao"], f["cobertura"] = numero(s["potencia_placa_w"]), kwh(s["producao_kwh_mes"]), pct(s["cobertura"])

    k = d["kit"]
    f["cotacoes"] = [
        {"fornecedor": q["fornecedor"], "valor": reais(q["valor"]), "detalhe": q.get("detalhe", ""),
         "entra": bool(q.get("entra_na_media")), "classe": "" if q.get("entra_na_media") else "fora"}
        for q in lista(k["cotacoes"])
    ]
    nao = lista(k.get("nao_cotados"))
    f["nao_cotados"] = ", ".join(nao[:-1]) + " e " + nao[-1] if len(nao) > 1 else "".join(nao)
    n = k.get("fornecedores_na_media", sum(1 for q in f["cotacoes"] if q["entra"]))
    f["na_media"] = f"de {n} fornecedor" + ("" if n == 1 else "es")
    f["media"] = reais(k["media"])

    f["custos"] = [
        {"nome": x["nome"], "valor": reais(x["valor"]), "taxa": pct(x["taxa"]) if x.get("taxa") else ""}
        for x in lista(d["custos"])
    ]

    # Adequação: sempre descrita, com a faixa da tabela e o valor (pedido do Guilherme, 11/11/2026)
    a = d["adequacao"]
    f["adequacao"] = (f"valor informado na mão, {reais(a['valor'])} (a tabela não tem faixa para este projeto)" if a.get("manual")
                      else f"{a['faixa']} = {reais(a['valor'])}")
    if not any(abs(float(x["valor"]) - float(a["valor"])) < 0.005 and "dequa" in x["nome"] for x in lista(d["custos"])):
        raise Erro("A adequação não está na lista de custos (ou o valor não bate com adequacao.valor).")

    p = d["preco"]
    f["por_kwp"] = reais(p["por_kwp"])
    f["faixa"] = [
        {"margem": pct(o["margem"]), "valor": reais(o["valor"]), "padrao": bool(o.get("padrao")), "selo": o.get("selo", "Padrão"),
         "classe": "indicada" if o.get("padrao") else ""}
        for o in lista(p["faixa"])
    ]
    f["socios"] = [{"nome": o["nome"], "parte": pct(o["parte"]), "valor": reais(o["valor"])} for o in lista(p["socios"])]
    # telas mais cheias que o normal ganham a versão compacta (preço ajustado = 4 linhas na faixa; mais de 5 itens a conferir)
    f["preco_classe"] = "cheia" if len(f["faixa"]) > 3 else ""
    f["conferir_classe"] = "compacta" if len(lista(d["conferir"])) > 5 else ""

    # conferência: os números da tela batem entre si?
    avisos = []
    soma_custos = round(sum(float(x["valor"]) for x in lista(d["custos"])), 2)
    if abs(soma_custos - float(r["custo_total"])) > 0.01:
        avisos.append(f"Os custos somam {reais(soma_custos)}, mas resumo.custo_total é {f['custo_total']}.")
    if abs(float(r["custo_total"]) + float(r["lucro"]) - float(r["valor_projeto"])) > 0.01:
        avisos.append("custo_total + lucro não dá o valor_projeto.")
    f["avisos_dados"] = avisos
    d["f"] = f
    return d


def pagina(dados):
    fonte = (MODELO / "justificativa.html").read_text(encoding="utf-8")
    fonte = re.sub(r"<!--(?!pe-->).*?-->", "", fonte, flags=re.S)
    pagina_html = montar(compilar(fonte), [dados])
    css = (MODELO / "proposta.css").read_text(encoding="utf-8") + "\n" + (MODELO / "justificativa.css").read_text(encoding="utf-8")
    pagina_html = pagina_html.replace('<link rel="stylesheet" href="proposta.css">', f"<style>\n{css}\n</style>")
    pagina_html = pagina_html.replace('<link rel="stylesheet" href="justificativa.css">', "")

    total = len(re.findall(r'<section class="tela', pagina_html))
    logo = embutir("img/life-logo-claro.png")
    partes = re.split(r'(?=<section class="tela)', pagina_html)
    for n in range(1, len(partes)):
        pe = (f'<footer class="pe"><img src="{logo}" alt=""><span class="nome">Life Energia Solar, uso interno</span>'
              f"<span>{n} / {total}</span></footer>")
        partes[n] = partes[n].replace('<i class="arco"></i>', arco(n, total)).replace("<!--pe-->", pe)
    pagina_html = "".join(partes)
    pagina_html = re.sub(
        r'(src|data-vidro)="(?!data:|https?:)([^"]+)"',
        lambda m: f'{m.group(1)}="{embutir(html.unescape(m.group(2)))}"',
        pagina_html,
    )
    return pagina_html, total


def gerar(dados, destino=None, guardar_html=False):
    """Gera a justificativa a partir do dicionário. Devolve (destino, total de telas, avisos). Levanta Erro se faltar campo."""
    dados = preparar(dados)
    pagina_html, total = pagina(dados)
    if destino:
        destino = Path(destino).expanduser()
    else:
        base = unicodedata.normalize("NFKD", str(dados["cliente"])).encode("ascii", "ignore").decode()
        base = re.sub(r"[^a-zA-Z0-9]+", "-", base).strip("-").lower() or "cliente"
        destino = AQUI / "saida" / f"justificativa-{base}-{dados['f']['data_iso']}.pdf"
    avisos = dados["f"]["avisos_dados"] + gerar_pdf(pagina_html, total, destino, guardar_html=guardar_html)
    return destino, total, avisos


def main():
    ap = argparse.ArgumentParser(description="Gera a justificativa do orçamento da LIFE em PDF.")
    ap.add_argument("json", help="justificativa.json do cliente")
    ap.add_argument("-o", "--saida", help="arquivo PDF de saída (padrão: saida/justificativa-<cliente>-<data>.pdf)")
    ap.add_argument("--html", action="store_true", help="guarda também o HTML montado ao lado do PDF")
    args = ap.parse_args()
    try:
        try:
            dados = json.loads(Path(args.json).read_text(encoding="utf-8"))
        except FileNotFoundError:
            raise Erro(f"Arquivo não encontrado: {args.json}")
        except json.JSONDecodeError as e:
            raise Erro(f"O JSON está com erro de escrita: {e}")
        destino, total, avisos = gerar(dados, args.saida, guardar_html=args.html)
    except Erro as e:
        print(f"ERRO: {e}", file=sys.stderr)
        return 1
    print(f"PDF pronto: {destino} ({total} telas)")
    for a in avisos:
        print(f"AVISO: {a}", file=sys.stderr)
    return 2 if avisos else 0


if __name__ == "__main__":
    sys.exit(main())
