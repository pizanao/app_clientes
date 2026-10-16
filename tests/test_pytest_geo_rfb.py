import gzip
import io
import json
import sqlite3
import urllib.error
from unittest.mock import MagicMock
import pytest

from scripts.carregar_geojson_sqlite import (
    FieldStats,
    GeoJsonTable,
    extract_coordinates_and_bounds,
    utm21s_to_wgs84,
)
from scripts.enriquecer_clientes_rfb import format_cep, format_telefone, normalizar_bairro
import scripts.restaurar_imoveis as mod_imoveis
import scripts.restaurar_rfb as mod_rfb


@pytest.mark.parametrize('easting,northing,expected_lon,expected_lat', [
    (744866.7916, 7737103.7295, -54.652909, -20.448769),
    (750000.0, 7735000.0, -54.603452, -20.467008),
])
def test_utm21s_to_wgs84_parametrized(easting, northing, expected_lon, expected_lat):
    """Testa precisão geodésica da conversão UTM Zona 21S (EPSG:31981) para WGS84 (EPSG:4326)."""
    lon, lat = utm21s_to_wgs84(easting, northing)
    assert abs(lon - expected_lon) < 1e-4
    assert abs(lat - expected_lat) < 1e-4


def test_extract_coordinates_and_bounds_wgs84_preservation():
    """Garante que coordenadas já em WGS84 são preservadas sem distorção."""
    geom = {
        'type': 'Polygon',
        'coordinates': [[[-54.60, -20.45], [-54.59, -20.45], [-54.59, -20.44], [-54.60, -20.44], [-54.60, -20.45]]]
    }
    gtype, bbox, centroid = extract_coordinates_and_bounds(geom)
    assert gtype == 'Polygon'
    assert abs(bbox[0] - (-54.60)) < 1e-4
    assert abs(bbox[1] - (-20.45)) < 1e-4
    assert abs(bbox[2] - (-54.59)) < 1e-4
    assert abs(bbox[3] - (-20.44)) < 1e-4
    assert abs(centroid[0] - (-20.446)) < 1e-3
    assert abs(centroid[1] - (-54.596)) < 1e-3


def test_extract_coordinates_and_bounds_utm_reprojection():
    """Converte ponto em UTM EPSG:31981 para WGS84."""
    geom_utm = {'type': 'Point', 'coordinates': [744866.7916, 7737103.7295]}
    gtype, bbox, centroid = extract_coordinates_and_bounds(geom_utm)
    assert gtype == 'Point'
    assert abs(bbox[0] - (-54.652909)) < 1e-4
    assert abs(bbox[1] - (-20.448769)) < 1e-4
    assert abs(centroid[0] - (-20.448769)) < 1e-4
    assert abs(centroid[1] - (-54.652909)) < 1e-4


@pytest.mark.parametrize('sample_values,expected_type', [
    ([1, 2, 100], 'INTEGER'),
    (['10', '25', '300'], 'INTEGER'),
    (['04160902071', '00017'], 'TEXT'),  # preserva zeros à esquerda
    ([10, 25.5, 100], 'REAL'),
    (['RESIDENCIAL', 'COMERCIAL'], 'TEXT'),
    ([None, None], 'TEXT'),
    ([True, False], 'INTEGER'),
    ([[1, 2], [3, 4]], 'TEXT'),
    ([{'chave': 'valor'}], 'TEXT'),
])
def test_field_stats_type_inference(sample_values, expected_type):
    """Verifica inferência de tipos SQLite em FieldStats para números, zeros à esquerda, booleanos e nulos."""
    st = FieldStats('campo_teste')
    for val in sample_values:
        st.record_value(val)
    assert st.infer_sqlite_type() == expected_type


def test_geojson_table_analyze_and_ddl_generation(tmp_path):
    """Testa análise de arquivo GeoJSON em EPSG:31981 e geração de DDL com R*Tree."""
    geojson_file = tmp_path / 'lotes_teste.geojson'
    sample_data = {
        'type': 'FeatureCollection',
        'crs': {'type': 'name', 'properties': {'name': 'urn:ogc:def:crs:EPSG::31981'}},
        'features': [
            {
                'type': 'Feature',
                'geometry': {
                    'type': 'MultiPolygon',
                    'coordinates': [[[[744866.79, 7737103.72], [744877.07, 7737097.54], [744866.79, 7737103.72]]]]
                },
                'properties': {
                    'gid': 1,
                    'codlote': '04160902071',
                    'nomebairro': 'SANTO AMARO',
                    'ruaimo': 'JERUSALEM',
                    'arealote': 432.0,
                }
            }
        ]
    }
    geojson_file.write_text(json.dumps(sample_data), encoding='utf-8')

    gt = GeoJsonTable(str(geojson_file), 'geo_lotes_teste')
    gt.analyze()

    assert len(gt.features) == 1
    assert gt.geometry_type == 'MultiPolygon'
    assert -55.0 < gt.bbox[0] < -54.0
    assert -21.0 < gt.bbox[1] < -20.0
    assert gt.fields['codlote'].infer_sqlite_type() == 'TEXT'
    assert gt.fields['arealote'].infer_sqlite_type() == 'REAL'

    ddl = '\n'.join(gt.generate_ddl())
    assert 'CREATE TABLE IF NOT EXISTS "geo_lotes_teste"' in ddl
    assert 'CREATE VIRTUAL TABLE IF NOT EXISTS "geo_lotes_teste_rtree" USING rtree' in ddl
    assert 'idx_geo_lotes_teste_nomebairro' in ddl


def test_restaurar_imoveis_csv_gz_and_idempotency(tmp_path):
    """Testa restauração de geo_imoveis via .csv.gz e verificação do índice R*Tree."""
    db_file = tmp_path / 'imoveis.db'
    csv_gz = tmp_path / 'geo_imoveis.csv.gz'

    csv_content = (
        'gid,codlote,ruaimo,nrporta,nomebairro,usoimovel,arealote,areaedific,'
        'geometry_geojson,geometry_type,min_lng,min_lat,max_lng,max_lat,centroid_lat,centroid_lng\n'
        '1,04160902071,AFONSO PENA,1500,CENTRO,COMERCIAL,500.0,320.0,'
        '"{""type"":""MultiPolygon"",""coordinates"":[]}",MultiPolygon,-54.62,-20.46,-54.61,-20.45,-20.455,-54.615\n'
    )
    with gzip.open(csv_gz, 'wt', encoding='utf-8') as f:
        f.write(csv_content)

    mod_imoveis.restaurar_dump(csv_gz, db_file, force=True)

    con = sqlite3.connect(str(db_file))
    assert mod_imoveis.verificar_tabela_existente(con) == 1
    cur = con.cursor()
    cur.execute('SELECT COUNT(*) FROM geo_imoveis_rtree')
    assert cur.fetchone()[0] == 1
    con.close()


def test_restaurar_imoveis_sql_gz_and_rtree_spatial_query(tmp_path):
    """Testa restauração de geo_imoveis via .sql.gz e consulta espacial na R*Tree."""
    db_file = tmp_path / 'imoveis_sql.db'
    sql_gz = tmp_path / 'geo_imoveis.sql.gz'

    cols = 'id, gid, codlote, ruaimo, nrporta, nomebairro, usoimovel, arealote, areaedific, geometry_geojson, geometry_type, min_lng, min_lat, max_lng, max_lat, centroid_lat, centroid_lng'
    sql_content = (
        "BEGIN TRANSACTION;\n"
        "DROP TABLE IF EXISTS \"geo_imoveis_rtree\";\n"
        "DROP TABLE IF EXISTS \"geo_imoveis\";\n"
        + mod_imoveis.CREATE_TABLE_GEO_IMOVEIS_SQL + "\n"
        f"INSERT INTO \"geo_imoveis\" ({cols}) VALUES(1, 1, '04160902071', 'AFONSO PENA', '1500', 'CENTRO', 'COMERCIAL', 500.0, 320.0, '{{\"type\":\"Point\",\"coordinates\":[-54.62,-20.46]}}', 'Point', -54.62, -20.46, -54.62, -20.46, -20.46, -54.62);\n"
        + "\n".join(mod_imoveis.INDEXES_GEO_IMOVEIS_SQL) + "\n"
        "COMMIT;\n"
    )
    with gzip.open(sql_gz, 'wt', encoding='utf-8') as f:
        f.write(sql_content)

    mod_imoveis.restaurar_dump(sql_gz, db_file, force=True)

    con = sqlite3.connect(str(db_file))
    assert mod_imoveis.verificar_tabela_existente(con) == 1
    cur = con.cursor()
    cur.execute("SELECT id FROM geo_imoveis_rtree WHERE min_lng <= -54.61 AND max_lng >= -54.63 AND min_lat <= -20.45 AND max_lat >= -20.47")
    row = cur.fetchone()
    assert row is not None
    assert row[0] == 1
    con.close()


def test_restaurar_imoveis_skips_when_already_populated(tmp_path, monkeypatch):
    """Quando geo_imoveis já possui > 20.000 registros e force=False, não recria a tabela."""
    db_file = tmp_path / 'imoveis_cheio.db'
    con = sqlite3.connect(str(db_file))
    con.execute(mod_imoveis.CREATE_TABLE_GEO_IMOVEIS_SQL)
    con.commit()
    con.close()

    monkeypatch.setattr(mod_imoveis, 'verificar_tabela_existente', lambda conn: 462744)

    chamou_sql = {'called': False}
    monkeypatch.setattr(mod_imoveis, '_restaurar_sql', lambda conn, p: chamou_sql.update(called=True))

    dummy_gz = tmp_path / 'dummy.sql.gz'
    dummy_gz.write_bytes(b'dummy')

    mod_imoveis.restaurar_dump(dummy_gz, db_file, force=False)
    assert chamou_sql['called'] is False


def test_baixar_dump_cleans_up_tmp_on_network_failure(tmp_path, monkeypatch):
    """Se o download do dump falhar no meio, o arquivo temporário .tmp deve ser removido."""
    destino = tmp_path / 'geo_imoveis.sql.gz'

    def broken_urlopen(req, timeout=120):
        raise urllib.error.URLError('Connection reset by peer')

    monkeypatch.setattr('urllib.request.urlopen', broken_urlopen)

    with pytest.raises(RuntimeError, match='Falha ao baixar dump'):
        mod_imoveis.baixar_dump('https://example.com/geo_imoveis.sql.gz', destino)

    assert not destino.exists()
    assert not destino.with_suffix('.tmp').exists()


def test_baixar_dump_imoveis_success(tmp_path, monkeypatch):
    """Download bem-sucedido de dump geo_imoveis deve mover .tmp para o arquivo final."""
    destino = tmp_path / 'geo_imoveis.sql.gz'

    fake_resp = MagicMock()
    fake_resp.headers = {'content-length': '10'}
    fake_resp.read.side_effect = [b'0123456789', b'']
    fake_resp.__enter__.return_value = fake_resp

    monkeypatch.setattr('urllib.request.urlopen', lambda req, timeout=120: fake_resp)

    mod_imoveis.baixar_dump('https://example.com/geo_imoveis.sql.gz', destino)
    assert destino.exists()
    assert destino.read_bytes() == b'0123456789'
    assert not destino.with_suffix('.tmp').exists()


def test_restaurar_rfb_sql_gz_and_view_creation(tmp_path):
    """Testa restauração de leeds_campo_grande via .sql.gz e criação da VIEW leads_campo_grande."""
    db_file = tmp_path / 'rfb_test.db'
    sql_gz = tmp_path / 'leeds_campo_grande.sql.gz'

    sql_script = """
    CREATE TABLE "leeds_campo_grande" (
        empresa text,
        cnpj text primary key,
        nome text,
        cargo text,
        telefone text,
        email text,
        logradouro text,
        numero text,
        bairro text,
        complemento text,
        cep text
    );
    INSERT INTO "leeds_campo_grande" VALUES (
        'PADARIA PAO QUENTE LTDA', '11222333000144', 'JOSE SILVA', 'Sócio-Administrador',
        '+5567991112233 | +55', 'CONTATO@PAOQUENTE.COM', 'CEARA', '900',
        'SANTA FE', 'LOJA 1', '79021000'
    );
    """
    with gzip.open(sql_gz, 'wt', encoding='utf-8') as f:
        f.write(sql_script)

    mod_rfb.restaurar_dump(sql_gz, db_file, force=True)

    con = sqlite3.connect(str(db_file))
    assert mod_rfb.verificar_tabela_existente(con) == 1
    cur = con.cursor()
    cur.execute("SELECT empresa, bairro, complemento FROM leads_campo_grande WHERE cnpj = '11222333000144'")
    row = cur.fetchone()
    assert row == ('PADARIA PAO QUENTE LTDA', 'SANTA FE', 'LOJA 1')
    con.close()


def test_restaurar_rfb_csv_gz_and_view_creation(tmp_path):
    """Testa restauração de leeds_campo_grande via .csv.gz e criação da VIEW leads_campo_grande."""
    db_file = tmp_path / 'rfb_csv_test.db'
    csv_gz = tmp_path / 'leeds_campo_grande.csv.gz'

    csv_content = (
        'empresa,cnpj,nome,cargo,telefone,email,logradouro,numero,bairro,complemento,cep\n'
        'MERCADO CENTRAL LTDA,22333444000155,MARIA SOUZA,Administradora,+556733221100,MARIA@MERCADO.COM,CALOGERAS,100,CENTRO,SALA 1,79002000\n'
    )
    with gzip.open(csv_gz, 'wt', encoding='utf-8') as f:
        f.write(csv_content)

    mod_rfb.restaurar_dump(csv_gz, db_file, force=True)

    con = sqlite3.connect(str(db_file))
    assert mod_rfb.verificar_tabela_existente(con) == 1
    cur = con.cursor()
    cur.execute("SELECT empresa, bairro FROM leads_campo_grande WHERE cnpj = '22333444000155'")
    assert cur.fetchone() == ('MERCADO CENTRAL LTDA', 'CENTRO')
    con.close()


def test_restaurar_rfb_skips_when_already_populated(tmp_path, monkeypatch):
    """Quando leeds_campo_grande já possui registros e force=False, não recria a tabela."""
    db_file = tmp_path / 'rfb_cheio.db'
    monkeypatch.setattr(mod_rfb, 'verificar_tabela_existente', lambda conn: 158558)

    chamou_sql = {'called': False}
    monkeypatch.setattr(mod_rfb, '_restaurar_sql', lambda conn, p: chamou_sql.update(called=True))

    dummy_gz = tmp_path / 'dummy_rfb.sql.gz'
    dummy_gz.write_bytes(b'dummy')

    mod_rfb.restaurar_dump(dummy_gz, db_file, force=False)
    assert chamou_sql['called'] is False


def test_baixar_dump_rfb_cleans_up_tmp_on_network_failure(tmp_path, monkeypatch):
    """Se o download do dump RFB falhar, o arquivo temporário .tmp deve ser removido."""
    destino = tmp_path / 'leeds_campo_grande.sql.gz'

    def broken_urlopen(req, timeout=60):
        raise urllib.error.URLError('Network unreachable')

    monkeypatch.setattr('urllib.request.urlopen', broken_urlopen)

    with pytest.raises(RuntimeError, match='Falha ao baixar dump RFB'):
        mod_rfb.baixar_dump('https://example.com/leeds.sql.gz', destino)

    assert not destino.exists()
    assert not destino.with_suffix('.tmp').exists()


@pytest.mark.parametrize('raw_cep,expected_cep', [
    ('79040010', '79040-010'),
    ('79002-072', '79002-072'),
    ('', '79002-000'),
    (None, '79002-000'),
])
def test_enriquecer_format_cep(raw_cep, expected_cep):
    """Verifica normalização e fallback de CEP em enriquecer_clientes_rfb.py."""
    assert format_cep(raw_cep) == expected_cep


@pytest.mark.parametrize('tel_raw,expected', [
    ('+5567991112233 | +55', '(67) 99111-2233'),
    ('6733214567', '(67) 3321-4567'),
    ('998887766', '(67) 99888-7766'),
    (None, '(67) 3300-1000'),
    ('', '(67) 3300-1000'),
])
def test_enriquecer_format_telefone(tel_raw, expected):
    """Verifica split por pipe, remoção de +55 e formatação em enriquecer_clientes_rfb.py."""
    assert format_telefone(tel_raw) == expected


@pytest.mark.parametrize('raw,expected', [
    ('CHACARA CACHOEIRA', 'Chácara Cachoeira'),
    ('centro', 'Centro'),
    ('Jardim dos Estados', 'Jardim dos Estados'),
    ('SANTA FE', 'Santa Fé'),
    ('VILASBOAS', 'Vilas Boas'),
    ('Cachoeira', 'Chácara Cachoeira'),
    ('TIRADENTES', 'Tiradentes'),
    ('Bairro Inexistente XYZ', 'Bairro Inexistente Xyz'),
])
def test_normalizar_bairro_parametrized(raw, expected):
    """Verifica normalização de nomes de bairros oficiais do SISGRAN."""
    assert normalizar_bairro(raw) == expected
