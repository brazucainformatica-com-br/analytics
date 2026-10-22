"""
Tema "Brazuca Analytics" para o Superset 6.1 (Ant Design v5 + tokens Superset + ECharts).

Linguagem visual de relatório corporativo (estilo Power BI): tela de fundo cinza-claro,
visuais em cartões brancos com cantos levemente arredondados e sombra suave, tipografia
Segoe UI/Inter, eixos discretos e paleta institucional da Brazuca Informática.
Nenhum ativo da Microsoft é distribuído: "Segoe UI" é apenas citado como fonte do sistema
(presente no Windows); nos demais sistemas vale a Inter, que já vem no Superset.
"""

BRAND_BLUE = "#4056D6"
BRAND_NAVY = "#101C33"
BRAND_GREEN = "#3E8E41"
BRAND_GOLD = "#F2B233"
BRAND_CORAL = "#E5675C"

FONT_STACK = "'Segoe UI', Inter, -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"

# Ordem pensada para contraste entre séries vizinhas (azul, dourado, verde, coral...)
BRAZUCA_COLORS = [
    BRAND_BLUE,
    BRAND_GOLD,
    BRAND_GREEN,
    BRAND_CORAL,
    BRAND_NAVY,
    "#12A3B8",  # turquesa
    "#8C9BEA",  # azul claro
    "#F28B30",  # laranja
    "#8FC79A",  # verde claro
    "#A66CC4",  # roxo
    "#5A6474",  # grafite
    "#C9A227",  # ouro escuro
]

BRAZUCA_CATEGORICAL = [
    {
        "id": "brazucaAnalytics",
        "description": "Paleta institucional Brazuca Informática",
        "label": "Brazuca Analytics",
        "isDefault": True,
        "colors": BRAZUCA_COLORS,
    }
]

BRAZUCA_SEQUENTIAL = [
    {
        "id": "brazucaBlues",
        "description": "Sequencial azul Brazuca",
        "label": "Brazuca — azul",
        "isDiverging": False,
        "isDefault": True,
        "colors": ["#EEF1FC", "#C9D1F4", "#94A3EA", "#5E74DF", BRAND_BLUE, "#2C3DA0", BRAND_NAVY],
    },
    {
        "id": "brazucaRedGreen",
        "description": "Divergente para metas (abaixo/acima)",
        "label": "Brazuca — meta",
        "isDiverging": True,
        "colors": [BRAND_CORAL, "#F2A99F", "#F5F5F5", "#9CCB9F", BRAND_GREEN],
    },
]

# Estilo global (vale para todos os gráficos ECharts): legenda e tooltip
_ECHARTS = {
    "textStyle": {"fontFamily": FONT_STACK},
    "legend": {
        "icon": "circle",
        "itemWidth": 9,
        "itemHeight": 9,
        "itemGap": 14,
        "textStyle": {"fontSize": 12, "color": "#605E5C"},
    },
    "tooltip": {
        "backgroundColor": "#FFFFFF",
        "borderColor": "#E1DFDD",
        "borderWidth": 1,
        "padding": [8, 12],
        "textStyle": {"color": "#252423", "fontSize": 12},
        "extraCssText": "box-shadow: 0 4px 12px rgba(0,0,0,.12); border-radius: 6px;",
    },
}

# Eixos discretos só nos gráficos cartesianos (não cria eixos em pizza, funil etc.)
_CARTESIAN_TYPES = [
    "echarts_timeseries",
    "echarts_timeseries_bar",
    "echarts_timeseries_line",
    "echarts_timeseries_smooth",
    "echarts_timeseries_step",
    "echarts_timeseries_scatter",
    "echarts_area",
    "mixed_timeseries",
    "waterfall",
    "histogram_v2",
    "box_plot",
    "bubble_v2",
]


def _axes(label: str, line: str, split: str) -> dict:
    return {
        "xAxis": {
            "axisLine": {"lineStyle": {"color": line}},
            "axisTick": {"show": False},
            "axisLabel": {"color": label, "fontSize": 11},
        },
        "yAxis": {
            "axisLine": {"show": False},
            "axisTick": {"show": False},
            "axisLabel": {"color": label, "fontSize": 11},
            "splitLine": {"lineStyle": {"color": split, "type": "dashed"}},
        },
    }


def _by_type(label: str, line: str, split: str, bg: str) -> dict:
    by_type = {t: _axes(label, line, split) for t in _CARTESIAN_TYPES}
    # Barras com cantos levemente arredondados
    by_type["echarts_timeseries_bar"]["series"] = {"itemStyle": {"borderRadius": 2}}
    # Pizza/rosca com separação branca entre fatias
    by_type["pie"] = {"series": {"itemStyle": {"borderColor": bg, "borderWidth": 2}}}
    return by_type


_TOKENS_COMMON = {
    # Marca
    "brandAppName": "Analytics",
    "brandLogoAlt": "Brazuca Informática",
    "brandLogoUrl": "/static/assets/brazuca/logo.png",
    "brandLogoHref": "/",
    "brandLogoHeight": "28px",
    "brandLogoMargin": "14px 0",
    "brandIconMaxWidth": 40,
    # Cores funcionais
    "colorPrimary": BRAND_BLUE,
    "colorLink": BRAND_BLUE,
    "colorSuccess": BRAND_GREEN,
    "colorWarning": BRAND_GOLD,
    "colorError": BRAND_CORAL,
    "colorInfo": "#12A3B8",
    # Tipografia
    "fontFamily": FONT_STACK,
    "fontFamilyCode": "'Cascadia Code', 'Fira Code', Consolas, monospace",
    "fontSize": 13,
    "fontWeightStrong": 600,
    # Formas
    "borderRadius": 6,
    "borderRadiusLG": 8,
    "borderRadiusSM": 4,
    "controlHeight": 32,
    "motionDurationMid": "0.15s",
}

THEME_DEFAULT_BRAZUCA = {
    "algorithm": "default",
    "token": {
        **_TOKENS_COMMON,
        # Superfícies estilo "tela de relatório"
        "colorBgLayout": "#F3F2F1",
        "colorBgContainer": "#FFFFFF",
        "colorBgElevated": "#FFFFFF",
        "colorBorder": "#E1DFDD",
        "colorBorderSecondary": "#EDEBE9",
        "colorText": "#252423",
        "colorTextSecondary": "#605E5C",
        "colorTextTertiary": "#8A8886",
        "boxShadowTertiary": "0 1.6px 3.6px rgba(0,0,0,.08), 0 0.3px 0.9px rgba(0,0,0,.06)",
        "colorEditorSelection": "#E3E8FA",
    },
    "echartsOptionsOverrides": _ECHARTS,
    "echartsOptionsOverridesByChartType": _by_type("#605E5C", "#C8C6C4", "#EDEBE9", "#FFFFFF"),
}

THEME_DARK_BRAZUCA = {
    "algorithm": "dark",
    "token": {
        **_TOKENS_COMMON,
        "colorPrimary": "#7084EA",
        "colorLink": "#8C9BEA",
        "colorBgLayout": "#14161C",
        "colorBgContainer": "#1E2129",
        "colorBgElevated": "#262A33",
        "colorBorder": "#353A45",
        "colorBorderSecondary": "#2B2F38",
        "colorEditorSelection": "#2C3560",
    },
    "echartsOptionsOverrides": {
        **_ECHARTS,
        "legend": {**_ECHARTS["legend"], "textStyle": {"fontSize": 12, "color": "#B9BEC9"}},
        "tooltip": {
            **_ECHARTS["tooltip"],
            "backgroundColor": "#262A33",
            "borderColor": "#353A45",
            "textStyle": {"color": "#E8EAF0", "fontSize": 12},
        },
    },
    "echartsOptionsOverridesByChartType": _by_type("#B9BEC9", "#4A505C", "#2B2F38", "#1E2129"),
}
