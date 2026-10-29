"""Genere les versions participant (labs/LABx_*_enonce.sql) a partir des corriges
(formateur/LABx_*_corrige.sql), en remplacant chaque bloc
-- >>> SOLUTION ... -- <<< SOLUTION par une zone de travail.
Usage (depuis n'importe ou) : python utils/make_enonces.py"""
import glob, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "formateur")
DST_DIR = os.path.join(ROOT, "labs")

for src in sorted(glob.glob(os.path.join(SRC_DIR, "LAB*_corrige.sql"))):
    txt = open(src, encoding="utf-8").read()
    assert txt.count("-- >>> SOLUTION") == txt.count("-- <<< SOLUTION"), src
    out = re.sub(r"-- >>> SOLUTION\n.*?-- <<< SOLUTION\n",
                 "-- A VOUS DE JOUER\n\n\n", txt, flags=re.S)
    dst = os.path.join(DST_DIR, os.path.basename(src).replace("_corrige.sql", "_enonce.sql"))
    with open(dst, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print(f"{os.path.relpath(dst, ROOT)}: {txt.count('-- >>> SOLUTION')} blocs masques, {len(out.splitlines())} lignes")
