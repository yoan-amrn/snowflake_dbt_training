"""
LAB 3 - Exercice 6 : app Streamlit in Snowflake sur TPCH
Copier-coller dans l'editeur Streamlit de Snowsight (packages par defaut suffisants).
"""
import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()
TPCH = "SNOWFLAKE_SAMPLE_DATA.TPCH_SF1"

st.set_page_config(page_title="TPCH - Pilotage commercial", layout="wide")
st.title("TPCH - Pilotage commercial")


@st.cache_data(ttl=600)
def run(sql, params=None):
    return session.sql(sql, params=params or []).to_pandas()


# ---------------------------------------------------------------------------
# Filtres
# ---------------------------------------------------------------------------
regions = run(f"SELECT R_NAME FROM {TPCH}.REGION ORDER BY 1")["R_NAME"].tolist()

with st.sidebar:
    st.header("Filtres")
    sel_regions = st.multiselect("Regions", regions, default=regions)
    annees = st.slider("Annees de commande", 1992, 1998, (1996, 1998))
    segment = st.selectbox(
        "Segment client",
        ["Tous", "AUTOMOBILE", "BUILDING", "FURNITURE", "HOUSEHOLD", "MACHINERY"],
    )

if not sel_regions:
    st.warning("Selectionnez au moins une region.")
    st.stop()

placeholders = ", ".join(["?"] * len(sel_regions))
where = f"""
    r.R_NAME IN ({placeholders})
    AND YEAR(o.O_ORDERDATE) BETWEEN ? AND ?
    AND (? = 'Tous' OR c.C_MKTSEGMENT = ?)
"""
params = [*sel_regions, annees[0], annees[1], segment, segment]
base = f"""
    FROM {TPCH}.ORDERS o
    JOIN {TPCH}.CUSTOMER c ON c.C_CUSTKEY  = o.O_CUSTKEY
    JOIN {TPCH}.NATION   n ON n.N_NATIONKEY = c.C_NATIONKEY
    JOIN {TPCH}.REGION   r ON r.R_REGIONKEY = n.N_REGIONKEY
    WHERE {where}
"""

# ---------------------------------------------------------------------------
# KPIs
# ---------------------------------------------------------------------------
kpi = run(
    f"""SELECT COUNT(*) AS NB_CMD, SUM(o.O_TOTALPRICE) AS CA,
               COUNT(DISTINCT o.O_CUSTKEY) AS NB_CLIENTS {base}""",
    params,
).iloc[0]

c1, c2, c3, c4 = st.columns(4)
c1.metric("Chiffre d'affaires", f"{kpi.CA / 1e9:,.2f} Md$")
c2.metric("Commandes", f"{kpi.NB_CMD:,}".replace(",", " "))
c3.metric("Clients actifs", f"{kpi.NB_CLIENTS:,}".replace(",", " "))
c4.metric("Panier moyen", f"{kpi.CA / max(kpi.NB_CMD, 1):,.0f} $".replace(",", " "))

# ---------------------------------------------------------------------------
# Onglets
# ---------------------------------------------------------------------------
tab_geo, tab_temps, tab_clients = st.tabs(["Par nation", "Evolution", "Clients"])

with tab_geo:
    df = run(
        f"""SELECT n.N_NAME AS NATION, SUM(o.O_TOTALPRICE) / 1e6 AS CA_MUSD
            {base} GROUP BY 1 ORDER BY 2 DESC""",
        params,
    )
    st.bar_chart(df, x="NATION", y="CA_MUSD", height=400)

with tab_temps:
    df = run(
        f"""SELECT DATE_TRUNC('month', o.O_ORDERDATE) AS MOIS, r.R_NAME AS REGION,
                   SUM(o.O_TOTALPRICE) / 1e6 AS CA_MUSD
            {base} GROUP BY 1, 2 ORDER BY 1""",
        params,
    )
    st.line_chart(df, x="MOIS", y="CA_MUSD", color="REGION", height=400)

with tab_clients:
    df = run(
        f"""SELECT c.C_NAME AS CLIENT, n.N_NAME AS NATION, c.C_MKTSEGMENT AS SEGMENT,
                   COUNT(*) AS NB_CMD, SUM(o.O_TOTALPRICE) AS CA
            {base} GROUP BY ALL ORDER BY CA DESC LIMIT 20""",
        params,
    )
    st.subheader("Top 20 clients")
    st.dataframe(df, use_container_width=True, hide_index=True)

    # Exercice 6.3 : table gouvernee du LAB 1 (schema courant de l'app)
    st.subheader("Table CUSTOMER du LAB 1 (gouvernee)")
    try:
        gov = run("SELECT CUSTOMER_NAME, EMAIL, PHONE, ACCOUNT_BALANCE, REGION FROM CUSTOMER LIMIT 10")
        st.dataframe(gov, use_container_width=True, hide_index=True)
        st.caption("Masquage / filtrage evalues avec les droits du PROPRIETAIRE de l'app.")
    except Exception as e:  # table absente si le LAB 1 n'a pas ete fait
        st.info(f"Table CUSTOMER introuvable dans ce schema ({e.__class__.__name__}).")
