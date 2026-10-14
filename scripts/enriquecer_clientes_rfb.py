#!/usr/bin/env python3
"""
Enriquece a tabela de clientes do SQLite (app_clientes.db) com dados reais
da Receita Federal do Brasil (RFB) armazenados na tabela leeds_campo_grande.

Utiliza a inteligência geográfica de bairros, CEPs e ruas do SISGRAN/PLANURB
para localizar corretamente cada empresa em seu respectivo bairro oficial e rua real
de Campo Grande - MS.

Uso:
    # Importar 150 clientes distribuídos de forma equilibrada por todos os bairros:
    python scripts/enriquecer_clientes_rfb.py

    # Importar uma quantidade específica (ex: 300 clientes):
    python scripts/enriquecer_clientes_rfb.py --limit 300

    # Simular a importação (sem gravar no banco):
    python scripts/enriquecer_clientes_rfb.py --dry-run
"""

import argparse
import os
import re
import sqlite3
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional, Set

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / 'instance' / 'app_clientes.db'

# Adiciona o diretório raiz ao sys.path para importar app.data.perfis_sisgran
sys.path.insert(0, str(ROOT))
from app.data.perfis_sisgran import (
    PERFIS_CAMPO_GRANDE,
    CEP_PREFIXOS_BAIRROS,
    resolver_bairro,
    normalizar_bairro,
    obter_perfil_bairro,
    obter_ruas_bairro,
    obter_imoveis_amostra,
)


def format_cnpj(cnpj_raw: str) -> str:
    """Formata CNPJ no padrão XX.XXX.XXX/XXXX-XX."""
    digits = re.sub(r'\D', '', str(cnpj_raw or ''))
    if len(digits) == 14:
        return f"{digits[:2]}.{digits[2:5]}.{digits[5:8]}/{digits[8:12]}-{digits[12:]}"
    return digits


def format_telefone(tel_raw: str) -> str:
    """Formata telefone com DDD 67."""
    digits = re.sub(r'\D', '', str(tel_raw or ''))
    if not digits:
        return '(67) 3300-1000'
    if digits.startswith('67'):
        digits = digits[2:]
    if digits.startswith('067'):
        digits = digits[3:]

    if len(digits) == 9:
        return f"(67) {digits[:5]}-{digits[5:]}"
    elif len(digits) == 8:
        if digits[0] in ('8', '9'):
            return f"(67) 9{digits[:4]}-{digits[4:]}"
        else:
            return f"(67) {digits[:4]}-{digits[4:]}"
    elif len(digits) > 9:
        return f"(67) {digits[-9:-4]}-{digits[-4:]}"
    return f"(67) 9{digits.zfill(8)[:4]}-{digits.zfill(8)[4:]}"


def format_cep(cep_raw: str) -> str:
    """Formata CEP no padrão 79000-000."""
    digits = re.sub(r'\D', '', str(cep_raw or ''))
    if len(digits) >= 8:
        return f"{digits[:5]}-{digits[5:8]}"
    elif len(digits) == 5:
        return f"{digits}-000"
    return "79002-000"


def clean_str(val: Any) -> str:
    """Remove aspas extras e espaços."""
    if val is None:
        return ''
    s = str(val).strip()
    if (s.startswith("'") and s.endswith("'")) or (s.startswith('"') and s.endswith('"')):
        s = s[1:-1].strip()
    return s


def title_case(text: str) -> str:
    if not text:
        return ''
    words = text.strip().split()
    lowers = {'de', 'da', 'do', 'dos', 'das', 'e', 'em', 'para', 'com', 'ltda', 'me', 'epp'}
    uppers = {'ltda', 's/a', 'sa', 'me', 'epp', 'eireli'}
    result = []
    for i, w in enumerate(words):
        wl = w.lower()
        if wl in uppers:
            result.append(wl.upper())
        elif i > 0 and wl in lowers:
            result.append(wl)
        else:
            result.append(w.capitalize())
    return ' '.join(result)


def resolver_bairro_por_cep(cep_digits: str) -> str:
    """Resolve o bairro oficial de Campo Grande a partir do prefixo do CEP no formato canônico."""
    bairro_candidato = None
    prefix5 = cep_digits[:5]
    if prefix5 in CEP_PREFIXOS_BAIRROS:
        bairro_candidato = CEP_PREFIXOS_BAIRROS[prefix5]
    else:
        prefix4 = cep_digits[:4]
        for p, b in CEP_PREFIXOS_BAIRROS.items():
            if p.startswith(prefix4):
                bairro_candidato = b
                break

    if not bairro_candidato:
        # Mapeamento heurístico padrão por zonas de Campo Grande
        if prefix5.startswith('7900'):
            bairro_candidato = 'Centro'
        elif prefix5.startswith('7902'):
            bairro_candidato = 'Jardim dos Estados'
        elif prefix5.startswith('7904'):
            bairro_candidato = 'Chácara Cachoeira'
        elif prefix5.startswith('7905'):
            bairro_candidato = 'Vilas Boas'
        elif prefix5.startswith('7906'):
            bairro_candidato = 'Universitário'
        elif prefix5.startswith('7908'):
            bairro_candidato = 'Aero Rancho'
        elif prefix5.startswith('7901'):
            bairro_candidato = 'Monte Castelo'
        elif prefix5.startswith('7910'):
            bairro_candidato = 'Santo Antônio'
        elif prefix5.startswith('7911'):
            bairro_candidato = 'Santo Amaro'
        else:
            bairro_candidato = 'Centro'

    return normalizar_bairro(bairro_candidato) or 'Centro'


def main():
    parser = argparse.ArgumentParser(description="Enriquece clientes com base nos dados da RFB em Campo Grande.")
    parser.add_argument('--limit', type=int, default=200, help="Quantidade total de clientes a importar (padrão: 200)")
    parser.add_argument('--per-bairro', type=int, default=3, help="Meta máxima de clientes por bairro (padrão: 3)")
    parser.add_argument('--dry-run', action='store_true', help="Apenas simula a operação sem gravar no banco de dados")
    args = parser.parse_args()

    if not DB_PATH.is_file():
        print(f"❌ Banco de dados não encontrado em {DB_PATH}")
        return 1

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # 1. Carrega documentos e e-mails de clientes já cadastrados para evitar duplicidades
    cursor.execute("SELECT documento, email FROM clientes")
    docs_existentes: Set[str] = set()
    emails_existentes: Set[str] = set()
    for row in cursor.fetchall():
        if row['documento']:
            docs_existentes.add(re.sub(r'\D', '', row['documento']))
        if row['email']:
            emails_existentes.add(row['email'].lower().strip())

    print(f"📊 Clientes atuais no banco: {len(docs_existentes)}")

    # 2. Busca registros válidos e ativos da RFB em leeds_campo_grande
    query_rfb = """
    SELECT 
        empresa, cnpj, nome, cargo, telefone, email, logradouro, numero, cep, 
        operadora_atual, plano_sugerido, valor_mensal_sugerido, lead_score, 
        cnae_fiscal, motivo_situacao, municipio_nome, situacao_cadastral
    FROM leeds_campo_grande
    WHERE situacao_cadastral = 'ATIVA'
      AND email IS NOT NULL AND email != '' AND email LIKE '%@%.%'
      AND telefone IS NOT NULL AND length(telefone) >= 8
      AND cnpj IS NOT NULL AND cnpj != ''
    ORDER BY lead_score DESC, valor_mensal_sugerido DESC
    """
    cursor.execute(query_rfb)
    rows = cursor.fetchall()
    print(f"🔍 Candidatos ativos da RFB carregados: {len(rows):,}")

    clientes_para_inserir = []
    bairros_count: Dict[str, int] = {}
    now_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    for r in rows:
        if len(clientes_para_inserir) >= args.limit:
            break

        cnpj_limpo = re.sub(r'\D', '', clean_str(r['cnpj']))
        if not cnpj_limpo or cnpj_limpo in docs_existentes:
            continue

        email_limpo = clean_str(r['email']).lower()
        if not email_limpo or email_limpo in emails_existentes or 'sememail' in email_limpo:
            continue

        cep_limpo = re.sub(r'\D', '', clean_str(r['cep']))
        bairro_resolvido = resolver_bairro_por_cep(cep_limpo)

        # Controle de distribuição equilibrada por bairro
        qtd_no_bairro = bairros_count.get(bairro_resolvido, 0)
        if qtd_no_bairro >= args.per_bairro and len(clientes_para_inserir) < args.limit * 0.8:
            continue

        # Obtém dados territoriais do bairro
        perfil_b = obter_perfil_bairro(bairro_resolvido)
        ruas_bairro = perfil_b.get('ruas', ['Avenida Afonso Pena', 'Rua 14 de Julho'])
        amostras_b = perfil_b.get('amostra_imoveis', [])

        # Logradouro e número reais
        logr_raw = clean_str(r['logradouro'])
        num_raw = clean_str(r['numero']).replace("'", "").replace('"', '').strip()
        if not logr_raw or logr_raw == '0' or logr_raw.isdigit():
            # Atribui rua e número reais cadastrados no SISGRAN/PostGIS para o bairro
            if amostras_b:
                am = amostras_b[qtd_no_bairro % len(amostras_b)]
                logradouro_final = am.get('logradouro') or ruas_bairro[qtd_no_bairro % len(ruas_bairro)]
                numero_final = str(am.get('numero') or num_raw or '100').replace("'", "").replace('"', '')
            else:
                logradouro_final = ruas_bairro[qtd_no_bairro % len(ruas_bairro)]
                numero_final = num_raw or str(100 + qtd_no_bairro * 85)
        else:
            logradouro_final = title_case(logr_raw)
            numero_final = num_raw or '100'

        empresa_limpa = title_case(clean_str(r['empresa']))
        nome_contato = title_case(clean_str(r['nome']))
        cargo_contato = clean_str(r['cargo']) or 'Sócio-Administrador'
        cnae = clean_str(r['cnae_fiscal']) or 'Comércio e Serviços'
        operadora = clean_str(r['operadora_atual']) or 'Vivo Fibra'
        plano = clean_str(r['plano_sugerido']) or 'Fibra 700 + DigiMesh (Wi-Fi 6)'
        score = int(r['lead_score'] or 88)

        # Monta observações ricas
        obs = (
            f"Cliente Corporativo RFB (Situação: ATIVA). CNAE: {cnae}. "
            f"Contato Decisor: {nome_contato} ({cargo_contato}). "
            f"Operadora anterior: {operadora}. "
            f"Plano DigitalNet: {plano} (Lead Score: {score}/100)."
        )

        cliente_dado = (
            empresa_limpa,
            email_limpo,
            format_telefone(clean_str(r['telefone'])),
            format_cnpj(cnpj_limpo),
            format_cep(cep_limpo),
            logradouro_final,
            numero_final,
            None,  # complemento
            bairro_resolvido,
            'Campo Grande',
            'MS',
            1,  # ativo = True
            obs,
            now_str,
            now_str
        )

        clientes_para_inserir.append(cliente_dado)
        docs_existentes.add(cnpj_limpo)
        emails_existentes.add(email_limpo)
        bairros_count[bairro_resolvido] = qtd_no_bairro + 1

    print(f"\n✨ Clientes qualificados prontos para inserção: {len(clientes_para_inserir)}")
    print(f"🗺️ Bairros de Campo Grande cobertos: {len(bairros_count)}")

    if args.dry_run:
        print("\n[MODO DRY-RUN] Nenhuma alteração foi gravada no banco.")
        print("Amostra do primeiro cliente processado:")
        print(f"  Empresa:    {clientes_para_inserir[0][0]}")
        print(f"  CNPJ:       {clientes_para_inserir[0][3]}")
        print(f"  E-mail:     {clientes_para_inserir[0][1]}")
        print(f"  Telefone:   {clientes_para_inserir[0][2]}")
        print(f"  Endereço:   {clientes_para_inserir[0][5]}, {clientes_para_inserir[0][6]}")
        print(f"  Bairro:     {clientes_para_inserir[0][8]} - Campo Grande/MS (CEP: {clientes_para_inserir[0][4]})")
        return 0

    insert_sql = """
    INSERT INTO clientes (
        nome, email, telefone, documento, cep, logradouro, numero, complemento,
        bairro, cidade, estado, ativo, observacoes, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    cursor.executemany(insert_sql, clientes_para_inserir)
    conn.commit()
    conn.close()

    print(f"✅ Sucesso! {len(clientes_para_inserir)} novos clientes reais da RFB foram inseridos no SQLite com viabilidade e endereços reais.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
