#!/usr/bin/env python3
"""
Gera o dataset territorial enriquecido a partir dos dados espaciais do SISGRAN / PLANURB
e do cadastro de imóveis carregado no PostGIS / GeoJSON:
  - geojson/bairros.geojson (74 bairros oficiais do Plano Diretor)
  - geojson/pd-macrozonas-urbanas.geojson (macrozonas do zoneamento urbano LC 341/2018)
  - geojson/parcelamentos.geojson (894 parcelamentos e loteamentos da PLANURB)
  - PostGIS (ou geojson/imoveis.geojson): 20.000 imóveis reais de Campo Grande MS

Gera: app/data/perfis_sisgran.py com PERFIS_CAMPO_GRANDE, COORDENADAS_BAIRROS e CEP_PREFIXOS_BAIRROS.
"""
import json
import os
import re
import subprocess
import unicodedata
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional

ROOT = Path(__file__).resolve().parent.parent
GEOJSON_DIR = ROOT / 'geojson'
OUTPUT_FILE = ROOT / 'app' / 'data' / 'perfis_sisgran.py'


def normalize(text: str) -> str:
    if not text:
        return ''
    n = unicodedata.normalize('NFKD', text)
    return ''.join(c for c in n if not unicodedata.combining(c)).upper().strip()


def title_case(text: str) -> str:
    if not text:
        return ''
    words = text.strip().split()
    lowers = {'de', 'da', 'do', 'dos', 'das', 'e', 'em', 'para', 'com'}
    result = []
    for i, w in enumerate(words):
        wl = w.lower()
        if i > 0 and wl in lowers:
            result.append(wl)
        else:
            result.append(w.capitalize())
    return ' '.join(result)


def format_street_name(text: str) -> str:
    """Padroniza nome de logradouro em Title Case com pontuação e artigos corretos."""
    if not text:
        return ''
    s = text.strip()
    s = re.sub(r'\bDR\b\.?', 'Dr.', s, flags=re.IGNORECASE)
    s = re.sub(r'\bDRA\b\.?', 'Dra.', s, flags=re.IGNORECASE)
    s = re.sub(r'\bENG\b\.?', 'Eng.', s, flags=re.IGNORECASE)
    s = re.sub(r'\bPROF\b\.?', 'Prof.', s, flags=re.IGNORECASE)
    s = re.sub(r'\bMS\b', 'MS', s, flags=re.IGNORECASE)
    s = re.sub(r'\bBR\b', 'BR', s, flags=re.IGNORECASE)
    s = re.sub(r'\bPRACA\b', 'Praça', s, flags=re.IGNORECASE)

    words = s.split()
    lowers = {'de', 'da', 'do', 'dos', 'das', 'e', 'em', 'para', 'com'}
    result = []
    for i, w in enumerate(words):
        wl = w.lower()
        if w in ('Dr.', 'Dra.', 'Eng.', 'Prof.', 'MS', 'BR', 'Praça'):
            result.append(w)
        elif i > 0 and wl in lowers:
            result.append(wl)
        else:
            result.append(w.capitalize())
    return ' '.join(result)


def get_pts(coords):
    pts = []
    def extract(c):
        if isinstance(c, (list, tuple)) and len(c) >= 2 and isinstance(c[0], (int, float)) and isinstance(c[1], (int, float)):
            pts.append((float(c[0]), float(c[1])))
        elif isinstance(c, (list, tuple)):
            for sub in c:
                extract(sub)
    extract(coords)
    return pts


def get_rings(geom):
    rings = []
    t = geom['type']
    c = geom['coordinates']
    if t == 'Polygon':
        if c and len(c) > 0:
            rings.append([(float(p[0]), float(p[1])) for p in c[0]])
    elif t == 'MultiPolygon':
        for poly in c:
            if poly and len(poly) > 0:
                rings.append([(float(p[0]), float(p[1])) for p in poly[0]])
    return rings


def point_in_poly(x, y, ring):
    n = len(ring)
    inside = False
    p1x, p1y = ring[0]
    for i in range(n + 1):
        p2x, p2y = ring[i % n]
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xinters:
                        inside = not inside
        p1x, p1y = p2x, p2y
    return inside


REGIOES_CONFIG = {
    'CENTRO': {
        'cep_prefix': '79002',
        'nichos': ['Comércio & Varejo', 'Escritórios de Advocacia', 'Consultórios & Clínicas', 'Contabilidades', 'Imobiliárias'],
        'ruas_padrao': ['Rua 14 de Julho', 'Avenida Calógeras', 'Rua Dom Aquino', 'Rua Barão do Rio Branco'],
    },
    'PROSA': {
        'cep_prefix': '79020',
        'nichos': ['Clínicas Médicas & Odontológicas', 'Escritórios Corporativos & Advocacia', 'Coworkings & Startups', 'Estética & Saúde', 'Boutiques'],
        'ruas_padrao': ['Avenida Mato Grosso', 'Avenida Afonso Pena', 'Rua Euclides da Cunha', 'Rua Ceará'],
    },
    'BANDEIRA': {
        'cep_prefix': '79041',
        'nichos': ['Gastronomia & Restaurantes', 'Academias & Centros Esportivos', 'Escolas & Cursos', 'Auto Centers', 'Varejo & Serviços'],
        'ruas_padrao': ['Avenida Três Barras', 'Avenida Marquês de Pombal', 'Avenida Eduardo Elias Zahran', 'Avenida Bom Pastor'],
    },
    'ANHANDUIZINHO': {
        'cep_prefix': '79060',
        'nichos': ['Supermercados & Atacarejos', 'Farmácias & Drogarias', 'Auto Peças & Oficinas', 'Materiais de Construção', 'Comércio Local'],
        'ruas_padrao': ['Avenida Marechal Deodoro', 'Avenida Manoel da Costa Lima', 'Avenida Guaicurus', 'Avenida Presidente Tancredo Neves'],
    },
    'LAGOA': {
        'cep_prefix': '79080',
        'nichos': ['Comércio Varejista', 'Oficinas Mecânicas', 'Padarias & Confeitarias', 'Pet Shops & Agropecuárias', 'Salões de Beleza'],
        'ruas_padrao': ['Avenida Bandeirantes', 'Avenida Duque de Caxias', 'Avenida Marinha', 'Rua Souto Maior'],
    },
    'IMBIRUSSU': {
        'cep_prefix': '79100',
        'nichos': ['Indústrias & Distribuidoras', 'Galpões Logísticos', 'Auto Centers', 'Comércio Geral', 'Prestadores de Serviços'],
        'ruas_padrao': ['Avenida Júlio de Castilho', 'Avenida Duque de Caxias', 'Avenida Presidente Vargas', 'Rua Capibaribe'],
    },
    'SEGREDO': {
        'cep_prefix': '79010',
        'nichos': ['Clínicas Populares', 'Academias', 'Escolas & Creches', 'Supermercados', 'Comércio de Bairro'],
        'ruas_padrao': ['Avenida Coronel Antonino', 'Avenida Mascarenhas de Moraes', 'Avenida Monte Castelo', 'Rua Zulmira Borba'],
    },
}

CEP_ESPECIFICOS = {
    'AERO RANCHO': '79083',
    'ALVES PEREIRA': '79060',
    'AMAMBAÍ': '79008',
    'AUTONOMISTA': '79022',
    'BANDEIRANTES': '79006',
    'BELA VISTA': '79003',
    'CARANDÁ': '79032',
    'CENTENÁRIO': '79070',
    'CENTRO': '79002',
    'CHÁCARA CACHOEIRA': '79040',
    'COOPHAVILA II': '79097',
    'CORONEL ANTONINO': '79011',
    'JARDIM DOS ESTADOS': '79020',
    'MONTE CASTELO': '79010',
    'MORENINHA': '79065',
    'NOVA LIMA': '79017',
    'NOVOS ESTADOS': '79034',
    'NÚCLEO INDUSTRIAL': '79115',
    'PIRATININGA': '79081',
    'POPULAR': '79106',
    'SANTA FÉ': '79021',
    'SANTO AMARO': '79112',
    'SANTO ANTÔNIO': '79100',
    'SÃO FRANCISCO': '79010',
    'SOBRINHO': '79110',
    'TIJUCA': '79094',
    'TIRADENTES': '79041',
    'UNIVERSITÁRIO': '79063',
    'VILAS BOAS': '79051',
}


def carregar_dados_imoveis_postgis() -> Dict[str, Dict[str, Any]]:
    """Consulta PostGIS db_geo para extrair ruas reais e estatísticas de imóveis por bairro."""
    query = """
    WITH imoveis_ruas AS (
        SELECT 
            b.bairro,
            i.ruaimo,
            i.tipoloc,
            count(*) as qtd
        FROM geo_bairros b
        JOIN geo_imoveis i ON ST_Intersects(b.geom, i.geom)
        WHERE i.ruaimo IS NOT NULL AND i.ruaimo != ''
        GROUP BY b.bairro, i.ruaimo, i.tipoloc
    ),
    ruas_ranked AS (
        SELECT 
            bairro,
            trim(tipoloc || ' ' || ruaimo) as rua_nome,
            qtd,
            row_number() OVER (PARTITION BY bairro ORDER BY qtd DESC) as rn
        FROM imoveis_ruas
    ),
    ruas_agrupadas AS (
        SELECT 
            bairro,
            json_agg(rua_nome ORDER BY rn) FILTER (WHERE rn <= 10) as ruas
        FROM ruas_ranked
        GROUP BY bairro
    ),
    amostras_ranked AS (
        SELECT 
            b.bairro,
            trim(i.tipoloc || ' ' || i.ruaimo) as logradouro,
            i.nrporta as numero,
            i.usoimovel as uso,
            i.arealote,
            i.areaedific,
            row_number() OVER (PARTITION BY b.bairro ORDER BY i.gid) as rn
        FROM geo_bairros b
        JOIN geo_imoveis i ON ST_Intersects(b.geom, i.geom)
        WHERE i.ruaimo IS NOT NULL AND i.nrporta IS NOT NULL AND i.nrporta != '0'
    ),
    amostras_agrupadas AS (
        SELECT 
            bairro,
            json_agg(json_build_object(
                'logradouro', logradouro,
                'numero', numero,
                'uso', uso,
                'arealote', arealote,
                'areaedific', areaedific
            ) ORDER BY rn) FILTER (WHERE rn <= 4) as amostras
        FROM amostras_ranked
        GROUP BY bairro
    ),
    imoveis_stats AS (
        SELECT 
            b.bairro,
            count(i.gid) as total_imoveis,
            round(coalesce(avg(nullif(i.arealote, 0)), 0)::numeric, 1) as media_arealote,
            round(coalesce(avg(nullif(i.areaedific, 0)), 0)::numeric, 1) as media_areaedific,
            count(case when i.usoimovel = 'COMERCIAL' then 1 end) as qtd_comercial,
            count(case when i.usoimovel = 'RESIDENCIAL' then 1 end) as qtd_residencial,
            count(case when i.usoimovel = 'TERRITORIAL' then 1 end) as qtd_territorial
        FROM geo_bairros b
        LEFT JOIN geo_imoveis i ON ST_Intersects(b.geom, i.geom)
        GROUP BY b.bairro
    )
    SELECT json_build_object(
        'bairro', s.bairro,
        'total_imoveis', s.total_imoveis,
        'media_arealote', s.media_arealote,
        'media_areaedific', s.media_areaedific,
        'qtd_comercial', s.qtd_comercial,
        'qtd_residencial', s.qtd_residencial,
        'qtd_territorial', s.qtd_territorial,
        'ruas', coalesce(r.ruas, '[]'::json),
        'amostras', coalesce(a.amostras, '[]'::json)
    )
    FROM imoveis_stats s
    LEFT JOIN ruas_agrupadas r ON s.bairro = r.bairro
    LEFT JOIN amostras_agrupadas a ON s.bairro = a.bairro
    ORDER BY s.bairro;
    """

    cmd = ['psql', '-U', 'postgres', '-d', 'db_geo', '-t', '-A', '-c', query]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        resultado = {}
        for line in res.stdout.strip().split('\n'):
            if line:
                d = json.loads(line)
                b_norm = normalize(d['bairro'])
                resultado[b_norm] = d
        return resultado
    except Exception as e:
        print(f"Aviso: Não foi possível consultar PostGIS diretamente ({e}). Usando dados locais.")
        return {}


CUSTOM_CANONICAL_NAMES = {
    'COOPHAVILA II': 'Coophavila II',
    'TV MORENA': 'TV Morena',
    'VILASBOAS': 'Vilas Boas',
    'DR. ALBUQUERQUE': 'Dr. Albuquerque',
    'CENTRO OESTE': 'Centro-Oeste',
}


def build_dataset():
    with open(GEOJSON_DIR / 'bairros.geojson', encoding='utf-8') as f:
        bairros_geo = json.load(f)

    with open(GEOJSON_DIR / 'pd-macrozonas-urbanas.geojson', encoding='utf-8') as f:
        macro_geo = json.load(f)

    with open(GEOJSON_DIR / 'parcelamentos.geojson', encoding='utf-8') as f:
        parc_geo = json.load(f)

    dados_postgis = carregar_dados_imoveis_postgis()

    macro_map = {}
    for feat in macro_geo['features']:
        b = normalize(feat['properties']['bairro'])
        macro_map[b] = feat['properties']['nome']

    bairros = []
    for f in bairros_geo['features']:
        b_raw = f['properties']['bairro'].strip()
        b_norm = normalize(b_raw)
        reg_urb = f['properties']['regiao_urb'].strip()
        pts = get_pts(f['geometry']['coordinates'])
        all_x = [p[0] for p in pts]
        all_y = [p[1] for p in pts]
        cent_lat = sum(all_y) / len(all_y)
        cent_lng = sum(all_x) / len(all_x)
        bbox = (min(all_x), min(all_y), max(all_x), max(all_y))
        rings = get_rings(f['geometry'])

        b_display = CUSTOM_CANONICAL_NAMES.get(b_raw, title_case(b_raw))
        bairros.append({
            'raw': b_raw,
            'norm': b_norm,
            'display': b_display,
            'regiao': reg_urb,
            'macrozona': macro_map.get(b_norm, 'MACROZONA URBANA'),
            'coords': (round(cent_lat, 4), round(cent_lng, 4)),
            'bbox': bbox,
            'rings': rings,
            'parcelamentos': []
        })

    for f in parc_geo['features']:
        p_name = f['properties'].get('nome_exibicao') or f['properties'].get('nome_parcelamento')
        if not p_name:
            continue
        pts = get_pts(f['geometry']['coordinates'])
        if not pts:
            continue
        px = sum(p[0] for p in pts) / len(pts)
        py = sum(p[1] for p in pts) / len(pts)

        for b in bairros:
            bx1, by1, bx2, by2 = b['bbox']
            if bx1 <= px <= bx2 and by1 <= py <= by2:
                matched = False
                for ring in b['rings']:
                    if point_in_poly(px, py, ring):
                        p_clean = title_case(p_name)
                        if p_clean not in b['parcelamentos']:
                            b['parcelamentos'].append(p_clean)
                        matched = True
                        break
                if matched:
                    break

    # Monta PERFIS_CAMPO_GRANDE, COORDENADAS_BAIRROS e CEP_PREFIXOS_BAIRROS
    perfis = {}
    coords = {}
    cep_map = {}

    for b in bairros:
        display_name = b['display']
        norm_name = b['norm']
        reg = b['regiao'].upper()
        reg_cfg = REGIOES_CONFIG.get(reg, REGIOES_CONFIG['CENTRO'])

        # Dados de imóveis e ruas do PostGIS
        pg_info = dados_postgis.get(norm_name, {})
        ruas_raw = pg_info.get('ruas', [])

        if ruas_raw:
            ruas_formatadas = [format_street_name(r) for r in ruas_raw]
        else:
            ruas_formatadas = reg_cfg['ruas_padrao']

        # Prefixo de CEP mapeado para o nome canônico em Title Case
        cep_prefix = CEP_ESPECIFICOS.get(b['raw'], reg_cfg['cep_prefix'])
        cep_map[cep_prefix] = display_name

        # Nichos comerciais
        nichos = reg_cfg['nichos']

        # Determina perfil predominante
        qtd_com = pg_info.get('qtd_comercial', 0)
        qtd_res = pg_info.get('qtd_residencial', 0)
        if qtd_com > 20 or (qtd_com > 0 and qtd_com >= qtd_res * 0.3):
            predominante = 'Comercial & Serviços'
        elif qtd_res > 0 and qtd_com > 0:
            predominante = 'Misto (Residencial e Comercial)'
        else:
            predominante = 'Residencial'

        # Amostras de imóveis reais
        amostras_limpas = []
        for am in pg_info.get('amostras', []):
            amostras_limpas.append({
                'logradouro': format_street_name(am.get('logradouro', '')),
                'numero': str(am.get('numero', '100')),
                'uso': am.get('uso', 'RESIDENCIAL'),
                'arealote': float(am.get('arealote') or 0),
                'areaedific': float(am.get('areaedific') or 0),
            })

        perfil_entry = {
            'nome_oficial': b['raw'],
            'nome_canonico': display_name,
            'regiao_urbana': b['regiao'],
            'macrozona': b['macrozona'],
            'coordenadas': b['coords'],
            'cep_prefix': cep_prefix,
            'ruas': ruas_formatadas,
            'nichos': nichos,
            'total_imoveis': pg_info.get('total_imoveis', 0),
            'media_arealote_m2': float(pg_info.get('media_arealote') or 0),
            'media_areaedific_m2': float(pg_info.get('media_areaedific') or 0),
            'perfil_predominante': predominante,
            'amostra_imoveis': amostras_limpas,
            'parcelamentos': sorted(b['parcelamentos'])[:15],
            'total_parcelamentos': len(b['parcelamentos']),
        }

        perfis[display_name] = perfil_entry
        coords[display_name] = b['coords']

    return perfis, coords, cep_map


def main():
    perfis, coords, cep_map = build_dataset()
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    header = '''# ==============================================================================
# PERFIS E COORDENADAS TERRITORIAIS OFICIAIS DE CAMPO GRANDE - MS (SISGRAN / PLANURB)
# ==============================================================================
# ARQUIVO GERADO AUTOMATICAMENTE a partir de:
#   - geojson/bairros.geojson (74 Bairros Oficiais do Plano Diretor)
#   - geojson/pd-macrozonas-urbanas.geojson (Macrozonas Urbanas LC 341/2018)
#   - geojson/parcelamentos.geojson (894 parcelamentos e loteamentos da PLANURB)
#   - PostGIS: 20.000 Imóveis Cadastrais Oficiais com Ruas Reais
#
# Para atualizar: python scripts/gerar_perfis_sisgran.py
# ==============================================================================
import unicodedata
from typing import Dict, Any, Tuple, Optional, List

'''

    content = [header]
    content.append(f"TOTAL_BAIRROS_OFICIAIS = 74\n\n")

    content.append("class PerfisSisgranDict(dict):\n")
    content.append("    \"\"\"Dicionário inteligente de perfis territoriais: permite acesso por nome canônico ou variação case-insensitive.\"\"\"\n")
    content.append("    def __getitem__(self, key):\n")
    content.append("        if dict.__contains__(self, key):\n")
    content.append("            return super().__getitem__(key)\n")
    content.append("        res = resolver_bairro(key)\n")
    content.append("        if res and dict.__contains__(self, res):\n")
    content.append("            return super().__getitem__(res)\n")
    content.append("        raise KeyError(key)\n\n")
    content.append("    def get(self, key, default=None):\n")
    content.append("        if dict.__contains__(self, key):\n")
    content.append("            return super().get(key, default)\n")
    content.append("        res = resolver_bairro(key)\n")
    content.append("        if res and dict.__contains__(self, res):\n")
    content.append("            return super().get(res, default)\n")
    content.append("        return default\n\n")
    content.append("    def __contains__(self, key):\n")
    content.append("        if dict.__contains__(self, key):\n")
    content.append("            return True\n")
    content.append("        res = resolver_bairro(key)\n")
    content.append("        return bool(res and dict.__contains__(self, res))\n\n\n")

    content.append("class CoordenadasBairrosDict(dict):\n")
    content.append("    \"\"\"Dicionário inteligente de coordenadas: permite busca por nome canônico ou variação case-insensitive.\"\"\"\n")
    content.append("    def __getitem__(self, key):\n")
    content.append("        if dict.__contains__(self, key):\n")
    content.append("            return super().__getitem__(key)\n")
    content.append("        res = resolver_bairro(key)\n")
    content.append("        if res and dict.__contains__(self, res):\n")
    content.append("            return super().__getitem__(res)\n")
    content.append("        raise KeyError(key)\n\n")
    content.append("    def get(self, key, default=None):\n")
    content.append("        if dict.__contains__(self, key):\n")
    content.append("            return super().get(key, default)\n")
    content.append("        res = resolver_bairro(key)\n")
    content.append("        if res and dict.__contains__(self, res):\n")
    content.append("            return super().get(res, default)\n")
    content.append("        return default\n\n")
    content.append("    def __contains__(self, key):\n")
    content.append("        if dict.__contains__(self, key):\n")
    content.append("            return True\n")
    content.append("        res = resolver_bairro(key)\n")
    content.append("        return bool(res and dict.__contains__(self, res))\n\n\n")

    content.append("PERFIS_CAMPO_GRANDE: PerfisSisgranDict = PerfisSisgranDict({\n")
    for k, v in perfis.items():
        content.append(f"    {repr(k)}: {{\n")
        for subk, subv in v.items():
            content.append(f"        {repr(subk)}: {repr(subv)},\n")
        content.append("    },\n")
    content.append("})\n\n")

    content.append("COORDENADAS_BAIRROS: CoordenadasBairrosDict = CoordenadasBairrosDict({\n")
    for k, v in coords.items():
        content.append(f"    {repr(k)}: {repr(v)},\n")
    content.append("})\n\n")

    content.append("CEP_PREFIXOS_BAIRROS: Dict[str, str] = {\n")
    for k, v in sorted(cep_map.items()):
        content.append(f"    {repr(k)}: {repr(v)},\n")
    content.append("}\n\n")

    helpers = r'''
def normalizar_nome(texto: str) -> str:
    """Remove acentuação, espaços extras e coloca em maiúsculas para busca flexível."""
    if not texto:
        return ''
    n = unicodedata.normalize('NFKD', texto)
    return ''.join(c for c in n if not unicodedata.combining(c)).upper().strip()


# Índice normalizado para resolução rápida (norm -> nome_canonico)
_NORMALIZED_INDEX: Dict[str, str] = {}
for _chave in PERFIS_CAMPO_GRANDE.keys():
    _NORMALIZED_INDEX[normalizar_nome(_chave)] = _chave

# Mapeamentos de apelidos e variações populares para bairros oficiais
_ALIASES: Dict[str, str] = {
    'VILAS BOAS': 'Vilas Boas',
    'VILASBOAS': 'Vilas Boas',
    'JARDIM LEBLON': 'Leblon',
    'LEBLON': 'Leblon',
    'CENTRO OESTE': 'Centro-Oeste',
    'CENTRO-OESTE': 'Centro-Oeste',
    'COOPHAVILA 2': 'Coophavila II',
    'COOPHAVILA II': 'Coophavila II',
    'TV MORENA': 'TV Morena',
    'DR ALBUQUERQUE': 'Dr. Albuquerque',
    'DR. ALBUQUERQUE': 'Dr. Albuquerque',
    'CHACARA CACHOEIRA': 'Chácara Cachoeira',
    'SANTA FE': 'Santa Fé',
    'JARDIM DOS ESTADOS': 'Jardim dos Estados',
}

# Índice de parcelamentos/loteamentos apontando para o bairro oficial
_PARCELAMENTO_TO_BAIRRO: Dict[str, str] = {}
for _bairro, _perfil in PERFIS_CAMPO_GRANDE.items():
    for _parc in _perfil.get('parcelamentos', []):
        _PARCELAMENTO_TO_BAIRRO[normalizar_nome(_parc)] = _bairro


def resolver_bairro(nome_busca: str) -> Optional[str]:
    """
    Localiza o bairro oficial no cadastro SISGRAN a partir de qualquer variação
    (com/sem acento, maiúsculas/minúsculas, ou nome de parcelamento/vila).
    Retorna SEMPRE o nome canônico único em formato Title Case (ex: 'Chácara Cachoeira').
    """
    if not nome_busca:
        return None

    # 1. Correspondência direta exata
    if dict.__contains__(PERFIS_CAMPO_GRANDE, nome_busca):
        return nome_busca

    norm = normalizar_nome(nome_busca)

    # 2. Aliases conhecidos
    if norm in _ALIASES:
        return _ALIASES[norm]

    # 3. Busca no índice normalizado de bairros
    if norm in _NORMALIZED_INDEX:
        return _NORMALIZED_INDEX[norm]

    # 4. Busca por correspondência parcial (ex: "Cachoeira" -> "Chácara Cachoeira")
    for k_norm, k_orig in _NORMALIZED_INDEX.items():
        if norm in k_norm or k_norm in norm:
            return k_orig

    # 5. Busca se o usuário informou o nome de uma vila/loteamento contido no bairro
    if norm in _PARCELAMENTO_TO_BAIRRO:
        return _PARCELAMENTO_TO_BAIRRO[norm]

    for p_norm, b_orig in _PARCELAMENTO_TO_BAIRRO.items():
        if norm in p_norm or p_norm in norm:
            return b_orig

    return None


def normalizar_bairro(nome_bairro: Optional[str]) -> Optional[str]:
    """
    Normaliza e unifica qualquer variação de nome de bairro para o formato canônico oficial.
    Ex: 'CHÁCARA CACHOEIRA' -> 'Chácara Cachoeira', 'VILASBOAS' -> 'Vilas Boas'.
    """
    if not nome_bairro:
        return None
    s = nome_bairro.strip()
    resolvido = resolver_bairro(s)
    if resolvido:
        return resolvido
    return title_case(s)


def obter_perfil_bairro(nome_bairro: str) -> Dict[str, Any]:
    """Retorna o perfil completo do bairro ou fallback com valores padrão de Campo Grande."""
    bairro_oficial = resolver_bairro(nome_bairro)
    if bairro_oficial and bairro_oficial in PERFIS_CAMPO_GRANDE:
        return PERFIS_CAMPO_GRANDE[bairro_oficial]

    return {
        'nome_oficial': nome_bairro or 'Centro',
        'regiao_urbana': 'Centro',
        'macrozona': 'MACROZONA 1 - MZ 1',
        'coordenadas': (-20.4628, -54.6156),
        'cep_prefix': '79002',
        'ruas': ['Avenida Afonso Pena', 'Rua 14 de Julho', 'Rua Dom Aquino'],
        'nichos': ['Comércio & Serviços', 'Consultórios', 'Escritórios'],
        'total_imoveis': 0,
        'media_arealote_m2': 400.0,
        'media_areaedific_m2': 120.0,
        'perfil_predominante': 'Comercial & Serviços',
        'amostra_imoveis': [],
        'parcelamentos': [],
        'total_parcelamentos': 0,
    }


def obter_coordenadas_bairro(nome_bairro: str) -> Tuple[float, float]:
    """Retorna as coordenadas (lat, lng) reais do centróide do bairro oficial."""
    bairro_oficial = resolver_bairro(nome_bairro)
    if bairro_oficial and bairro_oficial in COORDENADAS_BAIRROS:
        return COORDENADAS_BAIRROS[bairro_oficial]
    return (-20.4697, -54.6201)


def obter_ruas_bairro(nome_bairro: str) -> List[str]:
    """Retorna a lista de ruas reais cadastradas para o bairro."""
    perfil = obter_perfil_bairro(nome_bairro)
    return perfil.get('ruas', ['Avenida Principal', 'Rua Central'])


def obter_imoveis_amostra(nome_bairro: str) -> List[Dict[str, Any]]:
    """Retorna amostras reais de imóveis (logradouro, número, uso, área) do bairro."""
    perfil = obter_perfil_bairro(nome_bairro)
    return perfil.get('amostra_imoveis', [])


def obter_bairro_por_cep(cep: str) -> Optional[str]:
    """Descobre o bairro oficial a partir dos 5 primeiros dígitos do CEP."""
    if not cep:
        return None
    digitos = ''.join(c for c in cep if c.isdigit())
    if len(digitos) >= 5:
        prefixo = digitos[:5]
        if prefixo in CEP_PREFIXOS_BAIRROS:
            return CEP_PREFIXOS_BAIRROS[prefixo]
    return None
'''
    content.append(helpers)

    OUTPUT_FILE.write_text(''.join(content), encoding='utf-8')
    print(f"Sucesso! Gerado {OUTPUT_FILE} com {len(perfis)} entradas de bairros oficiais do SISGRAN enriquecidas com PostGIS.")


if __name__ == '__main__':
    main()
