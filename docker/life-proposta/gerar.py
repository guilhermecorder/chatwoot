#!/usr/bin/env python3
"""Gera a proposta da LIFE em PDF a partir de um JSON.

    python3 gerar.py exemplo.json                 -> saida/proposta-<cliente>-<data>.pdf
    python3 gerar.py dados.json -o ~/proposta.pdf -> escolhe o arquivo de saída
    python3 gerar.py dados.json --html            -> guarda também o HTML montado (para conferir no navegador)

Só usa a biblioteca padrão do Python e o Google Chrome (sem janela) que já está na máquina.
Campos do JSON: ver README.md.
"""
import argparse
import base64
import copy
import datetime as dt
import html
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path

AQUI = Path(__file__).resolve().parent
MODELO = AQUI / "modelo"


class Erro(Exception):
    """Problema que quem preenche o JSON consegue resolver."""


# ---------------------------------------------------------------- dados

def juntar(base, extra):
    """Junta dois dicionários; o que vem em `extra` ganha. Listas são trocadas inteiras."""
    saida = copy.deepcopy(base)
    for chave, valor in extra.items():
        if isinstance(valor, dict) and isinstance(saida.get(chave), dict):
            saida[chave] = juntar(saida[chave], valor)
        else:
            saida[chave] = copy.deepcopy(valor)
    return saida


def pegar(dados, caminho, obrigatorio=True):
    atual = dados
    for parte in caminho.split("."):
        if not isinstance(atual, dict) or atual.get(parte) in (None, ""):
            if obrigatorio:
                raise Erro(f"Falta o campo \"{caminho}\" no JSON.")
            return None
        atual = atual[parte]
    return atual


def numero(valor, casas=0):
    """1234567.8 -> '1.234.568' (padrão brasileiro)."""
    texto = f"{float(valor):,.{casas}f}"
    return texto.replace(",", "#").replace(".", ",").replace("#", ".")


def decimal(valor, casas=2):
    """41.48 -> '41,48' · 5.0 -> '5' (corta zeros sobrando)."""
    texto = numero(valor, casas)
    return texto.rstrip("0").rstrip(",") if "," in texto else texto


def reais_n(valor):
    return numero(valor, 0 if float(valor).is_integer() else 2)


def reais(valor):
    return "R$ " + reais_n(valor)


def data_br(d):
    return d.strftime("%d/%m/%Y")


def ler_data(texto, campo):
    try:
        return dt.date.fromisoformat(str(texto))
    except ValueError:
        raise Erro(f"\"{campo}\" precisa estar no formato AAAA-MM-DD (veio \"{texto}\").")


def lista(valor):
    if valor is None:
        return []
    return valor if isinstance(valor, list) else [valor]


def plural(palavra, quantidade):
    if quantidade == 1:
        return palavra
    return palavra + ("es" if palavra.endswith(("r", "z")) else "s")


ESTRELAS = (
    '<svg class="estrelas" viewBox="0 0 80 13" aria-label="5 estrelas">'
    + "".join(
        f'<path transform="translate({i * 16.6} 0)" fill="#F5B301" '
        'd="M6.5 0l1.9 4.3 4.6.5-3.4 3.1.9 4.6-4-2.3-4 2.3.9-4.6L0 4.8l4.6-.5z"/>'
        for i in range(5)
    )
    + "</svg>"
)


def svg(miolo):
    return f'<svg viewBox="0 0 24 24" aria-hidden="true">{miolo}</svg>'


# Ícones de linha (no quadradinho colorido, como nos Ajustes do iPhone)
ICONES = {
    "casa": svg('<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v9.5h13V10"/>'),
    "pino": svg('<path d="M12 21s-6.5-6.2-6.5-11a6.5 6.5 0 0 1 13 0c0 4.8-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.4"/>'),
    "raio": svg('<path d="M13 2.5 5 13.5h6l-1 8 8-11h-6z"/>'),
    "sol": svg('<circle cx="12" cy="12" r="4"/><path d="M12 2.5V5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8"/>'),
    "area": svg('<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/><path d="M3.5 12h17M12 3.5v17"/>'),
    "peso": svg('<path d="M8.5 8a3.5 3.5 0 0 1 7 0"/><path d="M5.5 9h13l1.5 11.5h-16z"/>'),
    "potencia": svg('<path d="M4 17a8 8 0 1 1 16 0"/><path d="M12 17l4.5-5.5"/>'),
    "placa": svg('<rect x="3" y="4.5" width="18" height="11.5" rx="1.5"/><path d="M3 10.2h18M9 4.5V16M15 4.5V16M12 16v3.5M8 19.5h8"/>'),
    "inversor": svg('<rect x="5" y="3" width="14" height="18" rx="3"/><path d="M9 8h6M9 11.5h6"/><circle cx="12" cy="16.5" r="1.3"/>'),
    "check": svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
    "escudo": svg('<path d="M12 2.8 4.5 5.6v5.6c0 4.6 3.2 8.6 7.5 10 4.3-1.4 7.5-5.4 7.5-10V5.6z"/><path d="M8.6 12.2l2.4 2.4 4.5-4.6"/>'),
    "cadeado": svg('<rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>'),
    "nuvem": svg('<path d="M7 17.5a4.5 4.5 0 1 1 .9-8.9 5.5 5.5 0 0 1 10.6 1.9A3.5 3.5 0 0 1 18 17.5z"/><path d="M12.5 13.5l-2 3.5h3l-2 3.5"/>'),
    "chama": svg('<path d="M12 21.5c-3.6 0-6.5-2.6-6.5-6.2 0-3.6 3-5.4 3.8-9.3 2.6 1.6 3.4 3.6 3.4 5.2 1-.6 1.6-1.8 1.7-3 2 1.6 4.1 4.3 4.1 7.1 0 3.6-2.9 6.2-6.5 6.2z"/>'),
    "relogio": svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
    "cartao": svg('<rect x="2.5" y="5.5" width="19" height="13" rx="2.5"/><path d="M2.5 10h19M6.5 15h4"/>'),
}
ICONES_SEGURO = ["cadeado", "nuvem", "chama", "raio"]
CORES = ["amarelo", "azul", "verde", "ciano"]


def preparar(dados):
    """Monta o bloco `f` com tudo já formatado para o modelo."""
    f = {}
    cidade = pegar(dados, "cliente.cidade")
    uf = pegar(dados, "cliente.uf", obrigatorio=False)
    f["cidade"] = f"{cidade}/{uf}" if uf else cidade
    pegar(dados, "cliente.nome")
    dados["cliente"].setdefault("distribuidora", "CPFL")

    # datas
    proposta = dados.setdefault("proposta", {})
    dia = ler_data(proposta["data"], "proposta.data") if proposta.get("data") else dt.date.today()
    dias = int(proposta.get("validade_dias", 7))
    fim = ler_data(proposta["validade"], "proposta.validade") if proposta.get("validade") else dia + dt.timedelta(days=dias)
    f["data"], f["validade"], f["validade_dias"] = data_br(dia), data_br(fim), (fim - dia).days
    f["data_iso"] = dia.isoformat()

    # conta e economia
    f["conta"] = reais(pegar(dados, "conta.valor_mensal"))
    f["consumo"] = numero(pegar(dados, "conta.consumo_kwh_mes"))
    # Como a conta foi calculada (opcional): ex. conta de hoje + 2 ares-condicionados (pedido do Guilherme, 11/11/2026)
    partes = lista(dados["conta"].get("composicao"))
    f["composicao"] = [
        {"rotulo": p["rotulo"], "valor": reais(p["valor"]), "mais": i > 0} for i, p in enumerate(partes)
    ]
    f["recap_classe"] = ("detalhada longa" if len(partes) > 2 else "detalhada") if partes else ""
    f["avisos_dados"] = []
    if partes:
        soma = sum(float(p["valor"]) for p in partes)
        if abs(soma - float(dados["conta"]["valor_mensal"])) > 0.5:
            f["avisos_dados"].append(
                f"conta.composicao soma {reais(soma)}, mas conta.valor_mensal é {f['conta']}. A tela 7 mostra os dois; confira."
            )
    eco_mes = pegar(dados, "economia.mensal")
    f["eco_mes_n"] = reais_n(eco_mes)
    f["conta_eco"] = reais(eco_mes)
    f["eco_mes_classe"] = "longo" if len(f["eco_mes_n"]) > 6 else ""
    # Taxa mínima da CPFL (opcional, 13/11/2026): a conta não zera, e a economia já vem com a taxa descontada.
    # economia.taxa_minima = {valor, kwh, rede} · economia.conta_mensal · economia.observacao (frase para o pé da tela)
    eco = dados["economia"]
    taxa = eco.get("taxa_minima") or {}
    f["taxa_minima"] = reais(taxa["valor"]) if taxa.get("valor") else ""
    f["conta_base"] = reais(eco.get("conta_mensal") or dados["conta"]["valor_mensal"])
    f["eco_sub"] = "por mês, já descontada a taxa mínima da CPFL" if f["taxa_minima"] else "por mês"
    if f["taxa_minima"]:
        f["recap_classe"] = (f["recap_classe"] + " com-taxa").strip()
        conta_base = float(eco.get("conta_mensal") or dados["conta"]["valor_mensal"])
        if abs(conta_base - float(taxa["valor"]) - float(eco_mes)) > 0.5:
            f["avisos_dados"].append(
                f"Conta ({f['conta_base']}) menos a taxa mínima ({f['taxa_minima']}) não dá a economia mensal ({f['conta_eco']}). A tela 7 mostra os três; confira."
            )
    f["eco_ano"] = reais(pegar(dados, "economia.anual"))
    f["eco_10"] = reais(pegar(dados, "economia.em_10_anos"))
    f["eco_25"] = reais(pegar(dados, "economia.em_25_anos"))
    marcos = [("Em 1 ano", "anual"), ("Em 10 anos", "em_10_anos"), ("Em 25 anos", "em_25_anos")]
    maior = max(float(dados["economia"][c]) for _, c in marcos) or 1
    f["barras"] = [
        {
            "rotulo": rotulo,
            "valor": reais(dados["economia"][campo]),
            "pct": max(3, round(float(dados["economia"][campo]) / maior * 100)),
            "classe": "forte" if i == len(marcos) - 1 else "",
        }
        for i, (rotulo, campo) in enumerate(marcos)
    ]

    # equipamento
    pegar(dados, "telhado.tipo")
    paineis = lista(pegar(dados, "sistema.paineis"))
    inversores = lista(pegar(dados, "sistema.inversores"))
    f["paineis"] = [
        {
            "qtd": numero(p["quantidade"]),
            "nome": plural("placa", p["quantidade"]) + " " + plural("solar", p["quantidade"]),
            "descricao": f"{p['marca']} {decimal(p['potencia_w'])} W",
        }
        for p in paineis
    ]
    f["inversores"] = [
        {
            "qtd": numero(i["quantidade"]),
            "nome": plural(str(i.get("tipo", "Inversor")).lower(), i["quantidade"]),
            "descricao": " ".join(x for x in (i.get("marca"), i.get("modelo")) if x),
        }
        for i in inversores
    ]
    f["equipamentos"] = [dict(e, cor="amarelo", icone=ICONES["placa"]) for e in f["paineis"]] + [
        dict(e, cor=("azul", "ciano")[i % 2], icone=ICONES["inversor"]) for i, e in enumerate(f["inversores"])
    ]
    f["equip_classe"] = "compacta" if len(f["equipamentos"]) > 2 else ""
    potencia = pegar(dados, "sistema.potencia_kwp", obrigatorio=False)
    if potencia is None:
        potencia = sum(p["quantidade"] * p["potencia_w"] for p in paineis) / 1000
    f["potencia"] = decimal(potencia)
    f["producao_mes"] = numero(pegar(dados, "sistema.producao_kwh_mes"))
    f["producao_ano"] = numero(pegar(dados, "sistema.producao_kwh_ano"))
    cobertura = round(float(dados["sistema"]["producao_kwh_mes"]) / float(dados["conta"]["consumo_kwh_mes"]) * 100)
    f["cobertura"] = cobertura
    f["anel_cheio"] = f"{min(cobertura, 100) / 100 * 289.03:.1f}"
    f["area"] = decimal(pegar(dados, "sistema.area_m2"), 1)
    f["peso"] = numero(pegar(dados, "sistema.peso_kg"))
    f["incidencia"] = decimal(pegar(dados, "sistema.incidencia_solar"))
    if not lista(dados.get("garantias")):
        raise Erro("Falta a lista \"garantias\" no JSON.")
    f["garantias"] = [dict(g, cor=CORES[i % 3]) for i, g in enumerate(lista(dados["garantias"]))]
    maior = max(lista(dados["garantias"]), key=lambda g: float(g["anos"]))
    f["garantia_max"], f["garantia_max_item"] = numero(maior["anos"]), maior["item"]
    f["placas_total"] = numero(sum(p["quantidade"] for p in paineis))
    f["passos_qtd"] = len(lista(dados.get("instalacao")))

    # dinheiro
    preco = pegar(dados, "investimento.preco_total")
    f["preco"], f["preco_n"] = reais(preco), reais_n(preco)
    f["preco_classe"] = "longo" if len(f["preco_n"]) > 7 else ""
    antes = pegar(dados, "investimento.preco_antes")
    if isinstance(antes, dict):
        f["antes_de"] = reais(antes["de"])
        f["antes_ate"] = reais(antes["ate"]) if antes.get("ate") else ""
    else:
        f["antes_de"], f["antes_ate"] = reais(antes), ""
    # Financiamento: a Life indica a opção do meio (Guilherme, 11/11/2026), a não ser que o JSON marque outra com "indicada": true
    opcoes = lista(dados["investimento"].get("financiamento"))
    marcada = next((i for i, o in enumerate(opcoes) if o.get("indicada")), len(opcoes) // 2 if opcoes else None)
    f["financiamento"] = [
        {"parcelas": o["parcelas"], "valor": reais(o["valor"]), "indicada": i == marcada, "classe": "indicada" if i == marcada else ""}
        for i, o in enumerate(opcoes)
    ]
    f["indicada"] = f["financiamento"][marcada] if opcoes else ""
    f["tem_pagamento"] = bool(f["financiamento"] or dados["investimento"].get("cartao"))

    # gente e contato
    f["foto_vendedor"] = pegar(dados, "vendedor.foto")
    f["foto_rosto"] = dados["vendedor"].get("foto_rosto") or f["foto_vendedor"]
    f["foto_vidro"] = dados["vendedor"].get("foto_vidro") or f["foto_vendedor"]
    f["icones"] = ICONES
    f["coberturas"] = [
        dict(c, icone=ICONES.get(c.get("icone") or ICONES_SEGURO[i % len(ICONES_SEGURO)], ICONES["escudo"]))
        for i, c in enumerate(lista(dados.get("seguro", {}).get("coberturas")))
    ]
    zap = re.sub(r"\D", "", str(pegar(dados, "empresa.whatsapp")))
    f["link_whatsapp"] = f"https://wa.me/{zap}"
    f["estrelas"] = ESTRELAS

    # troca {distribuidora} e {cliente} dentro dos textos fixos
    trocas = {"{distribuidora}": dados["cliente"]["distribuidora"], "{cliente}": dados["cliente"]["nome"]}

    def trocar(valor):
        if isinstance(valor, str):
            for de, para in trocas.items():
                valor = valor.replace(de, para)
            return valor
        if isinstance(valor, list):
            return [trocar(v) for v in valor]
        if isinstance(valor, dict):
            return {k: trocar(v) for k, v in valor.items()}
        return valor

    dados = trocar(dados)
    dados["f"] = f
    return dados


# ---------------------------------------------------------------- modelo (chaves duplas)

MARCA = re.compile(r"\{\{\{\s*(.+?)\s*\}\}\}|\{\{\s*([#/]?)\s*(.+?)\s*\}\}")


def compilar(fonte):
    raiz, pilha, pos = [], [], 0
    atual = raiz
    for m in MARCA.finditer(fonte):
        if m.start() > pos:
            atual.append(("txt", fonte[pos:m.start()]))
        pos = m.end()
        if m.group(1):
            atual.append(("cru", m.group(1)))
            continue
        sinal, corpo = m.group(2), m.group(3)
        if sinal == "#":
            tipo, _, caminho = corpo.partition(" ")
            if tipo not in ("se", "nao", "cada"):
                raise Erro(f"Bloco desconhecido no modelo: {{{{#{corpo}}}}}")
            no = (tipo, caminho.strip(), [])
            atual.append(no)
            pilha.append(atual)
            atual = no[2]
        elif sinal == "/":
            if not pilha:
                raise Erro(f"Bloco fechado sem abrir no modelo: {{{{/{corpo}}}}}")
            atual = pilha.pop()
        else:
            atual.append(("var", corpo))
    if pilha:
        raise Erro("Há um bloco aberto sem fechar no modelo.")
    atual.append(("txt", fonte[pos:]))
    return raiz


FALTA = object()


def buscar(escopos, caminho):
    if caminho == ".":
        return escopos[-1]
    primeira, *resto = caminho.split(".")
    for escopo in reversed(escopos):
        if isinstance(escopo, dict) and primeira in escopo:
            valor = escopo[primeira]
            for parte in resto:
                if not isinstance(valor, dict) or parte not in valor:
                    return FALTA
                valor = valor[parte]
            return valor
    return FALTA


def montar(arvore, escopos):
    saida = []
    for no in arvore:
        tipo = no[0]
        if tipo == "txt":
            saida.append(no[1])
        elif tipo in ("var", "cru"):
            valor = buscar(escopos, no[1])
            if valor is FALTA or valor is None:
                raise Erro(f"O modelo pede \"{no[1]}\" e esse campo não veio no JSON.")
            saida.append(str(valor) if tipo == "cru" else html.escape(str(valor), quote=True))
        else:
            valor = buscar(escopos, no[1])
            cheio = valor is not FALTA and bool(valor)
            if tipo == "se" and cheio:
                saida.append(montar(no[2], escopos))
            elif tipo == "nao" and not cheio:
                saida.append(montar(no[2], escopos))
            elif tipo == "cada" and cheio:
                for item in lista(valor):
                    saida.append(montar(no[2], escopos + [item]))
    return "".join(saida)


# ---------------------------------------------------------------- página

def embutir(caminho):
    """Arquivo de imagem -> data URI (o HTML final não depende de pasta nenhuma)."""
    arquivo = Path(caminho)
    if not arquivo.is_absolute():
        arquivo = MODELO / caminho if (MODELO / caminho).exists() else AQUI / caminho
    if not arquivo.exists():
        raise Erro(f"Imagem não encontrada: {caminho}")
    tipo = mimetypes.guess_type(arquivo.name)[0] or "image/jpeg"
    return f"data:{tipo};base64," + base64.b64encode(arquivo.read_bytes()).decode("ascii")


def arco(posicao, total):
    """O sol que cruza o céu: quanto da proposta já foi lido."""
    t = (posicao - 1) / max(total - 1, 1)
    p0, p1, p2 = (4, 26), (167, -18), (330, 26)

    def ponto(u):
        return tuple((1 - u) ** 2 * a + 2 * (1 - u) * u * b + u ** 2 * c for a, b, c in zip(p0, p1, p2))

    feito = " ".join(f"{x:.1f},{y:.1f}" for x, y in (ponto(t * i / 24) for i in range(25)))
    x, y = ponto(t)
    return (
        '<svg class="arco" viewBox="0 0 334 30" aria-hidden="true">'
        f'<path d="M{p0[0]} {p0[1]} Q{p1[0]} {p1[1]} {p2[0]} {p2[1]}" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>'
        f'<polyline class="feito" points="{feito}" fill="none" stroke-width="1.5" stroke-linecap="round"/>'
        f'<circle class="sol" cx="{x:.1f}" cy="{y:.1f}" r="5"/>'
        "</svg>"
    )


def pagina(dados):
    fonte = (MODELO / "proposta.html").read_text(encoding="utf-8")
    fonte = re.sub(r"<!--(?!pe-->).*?-->", "", fonte, flags=re.S)  # tira os comentários, menos o do rodapé
    pagina_html = montar(compilar(fonte), [dados])

    css = (MODELO / "proposta.css").read_text(encoding="utf-8")
    pagina_html = pagina_html.replace('<link rel="stylesheet" href="proposta.css">', f"<style>\n{css}\n</style>")

    total = len(re.findall(r'<section class="tela', pagina_html))
    logo = embutir("img/life-logo-claro.png")
    empresa = html.escape(dados["empresa"]["nome"])
    partes = re.split(r'(?=<section class="tela)', pagina_html)
    for n in range(1, len(partes)):
        esquerda = f"Válida até {dados['f']['validade']}" if n == 1 else empresa
        pe = (
            f'<footer class="pe"><img src="{logo}" alt=""><span class="nome">{esquerda}</span>'
            f"<span>{n} / {total}</span></footer>"
        )
        partes[n] = partes[n].replace('<i class="arco"></i>', arco(n, total)).replace("<!--pe-->", pe)
    pagina_html = "".join(partes)

    # embute as imagens (fotos e as cópias desfocadas do vidro)
    pagina_html = re.sub(
        r'(src|data-vidro)="(?!data:|https?:)([^"]+)"',
        lambda m: f'{m.group(1)}="{embutir(html.unescape(m.group(2)))}"',
        pagina_html,
    )
    return pagina_html, total


# ---------------------------------------------------------------- PDF

def achar_chrome():
    candidatos = [
        os.environ.get("CHROME"),
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
        shutil.which("google-chrome"),
        shutil.which("google-chrome-stable"),
        shutil.which("chromium"),
        shutil.which("chromium-browser"),
    ]
    for c in candidatos:
        if c and Path(c).exists():
            return c
    raise Erro("Não achei o Google Chrome. Instale-o ou aponte o caminho na variável CHROME.")


def rodar_chrome(chrome, pasta, *extras):
    comando = [
        chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
        "--no-default-browser-check", "--disable-extensions",
        f"--user-data-dir={pasta / 'perfil'}",  # perfil à parte: não encosta no Chrome aberto
        *os.environ.get("CHROME_FLAGS", "").split(),  # no contêiner: --no-sandbox --disable-dev-shm-usage
        *extras,
        (pasta / "proposta.html").as_uri(),
    ]
    return subprocess.run(comando, capture_output=True, text=True, timeout=120)


def gerar_pdf(pagina_html, total, destino, guardar_html=False):
    chrome = achar_chrome()
    with tempfile.TemporaryDirectory(prefix="proposta-life-") as tmp:
        pasta = Path(tmp)
        (pasta / "proposta.html").write_text(pagina_html, encoding="utf-8")

        # 1ª passada: alguma tela estourou?
        avisos = []
        dom = rodar_chrome(chrome, pasta, "--virtual-time-budget=4000", "--dump-dom").stdout
        blocos = re.split(r'(?=<section class="tela)', dom)[1:]
        for n, bloco in enumerate(blocos, 1):
            m = re.match(r'<section[^>]*data-estouro="(\d+)"', bloco)
            if m:
                avisos.append(f"Tela {n}: o conteúdo passou {m.group(1)} px do espaço. Encurte o texto dessa tela.")

        # 2ª passada: o PDF
        pdf = pasta / "proposta.pdf"
        r = rodar_chrome(chrome, pasta, "--no-pdf-header-footer", "--print-to-pdf-no-header",
                         "--virtual-time-budget=4000", f"--print-to-pdf={pdf}")
        if not pdf.exists():
            raise Erro("O Chrome não gerou o PDF.\n" + (r.stderr or "")[-800:])
        paginas = len(re.findall(rb"/Type\s*/Page(?![s\w])", pdf.read_bytes()))
        if paginas and paginas != total:
            avisos.append(f"O PDF saiu com {paginas} páginas e o modelo tem {total} telas.")

        destino.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(pdf, destino)
        if guardar_html:
            shutil.copyfile(pasta / "proposta.html", destino.with_suffix(".html"))
    return avisos


def nome_arquivo(dados):
    base = unicodedata.normalize("NFKD", dados["cliente"]["nome"]).encode("ascii", "ignore").decode()
    base = re.sub(r"[^a-zA-Z0-9]+", "-", base).strip("-").lower() or "cliente"
    return f"proposta-{base}-{dados['f']['data_iso']}.pdf"


def gerar_resumo_jpg(pagina_html, destino):
    """Foto do ÚLTIMO card (o resumo da proposta) em JPG, para usar no follow-up (pedido do Guilherme, 11/11/2026).
    Devolve a lista de avisos (vazia se deu certo)."""
    chrome = achar_chrome()
    so_o_resumo = "<style>section.tela:not(.resumo-tela){display:none !important}html,body{margin:0;background:#000}</style></head>"
    with tempfile.TemporaryDirectory(prefix="proposta-life-") as tmp:
        pasta = Path(tmp)
        (pasta / "proposta.html").write_text(pagina_html.replace("</head>", so_o_resumo, 1), encoding="utf-8")
        png = pasta / "resumo.png"
        r = rodar_chrome(chrome, pasta, "--window-size=390,760", "--force-device-scale-factor=3",
                         "--virtual-time-budget=4000", f"--screenshot={png}")
        if not png.exists():
            return ["Não consegui tirar a foto do card de resumo.\n" + (r.stderr or "")[-300:]]
        destino.parent.mkdir(parents=True, exist_ok=True)
        if shutil.which("sips"):          # macOS
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "88", str(png), "--out", str(destino)],
                           capture_output=True, check=False)
        else:
            try:
                from PIL import Image
                Image.open(png).convert("RGB").save(destino, "JPEG", quality=88)
            except ImportError:
                pass
        if not destino.exists():
            shutil.copyfile(png, destino.with_suffix(".png"))
            return [f"O card de resumo saiu em PNG ({destino.with_suffix('.png').name}): não achei como converter para JPG."]
    return []


def gerar(orcamento, destino=None, guardar_html=False, resumo_jpg=None):
    """Gera a proposta a partir do dicionário do orçamento. Devolve (destino, total de telas, avisos).
    `resumo_jpg`: caminho para salvar também a foto do último card (resumo). Levanta Erro se faltar campo."""
    fixos = json.loads((AQUI / "life.json").read_text(encoding="utf-8"))
    dados = preparar(juntar(fixos, orcamento))
    pagina_html, total = pagina(dados)
    destino = Path(destino).expanduser() if destino else AQUI / "saida" / nome_arquivo(dados)
    avisos = dados["f"]["avisos_dados"] + gerar_pdf(pagina_html, total, destino, guardar_html=guardar_html)
    if resumo_jpg:
        avisos += gerar_resumo_jpg(pagina_html, Path(resumo_jpg).expanduser())
    return destino, total, avisos


def main():
    ap = argparse.ArgumentParser(description="Gera a proposta da LIFE em PDF a partir de um JSON.")
    ap.add_argument("json", help="arquivo JSON do orçamento (ver exemplo.json)")
    ap.add_argument("-o", "--saida", help="arquivo PDF de saída (padrão: saida/proposta-<cliente>-<data>.pdf)")
    ap.add_argument("--html", action="store_true", help="guarda também o HTML montado ao lado do PDF")
    ap.add_argument("--resumo-jpg", metavar="ARQUIVO", help="salva também a foto do último card (resumo) em JPG")
    args = ap.parse_args()

    try:
        try:
            orcamento = json.loads(Path(args.json).read_text(encoding="utf-8"))
        except FileNotFoundError:
            raise Erro(f"Arquivo não encontrado: {args.json}")
        except json.JSONDecodeError as e:
            raise Erro(f"O JSON está com erro de escrita: {e}")
        destino, total, avisos = gerar(orcamento, args.saida, guardar_html=args.html, resumo_jpg=args.resumo_jpg)
    except Erro as e:
        print(f"ERRO: {e}", file=sys.stderr)
        return 1

    print(f"PDF pronto: {destino} ({total} telas)")
    for a in avisos:
        print(f"AVISO: {a}", file=sys.stderr)
    return 2 if avisos else 0


if __name__ == "__main__":
    sys.exit(main())
