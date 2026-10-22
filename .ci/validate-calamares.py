#!/usr/bin/env python3
"""validate-calamares.py — o gate que a v1.1 não tinha.

A ISO v1.1 entregou "The following modules could not be loaded:
shellprocess@btrfs" no rig do dono: o heredoc EOSB do elite-customize.sh
reescreve o shellprocess_btrfs.conf com 4 printfs cujo \\n virou quebra de
linha REAL — a continuação caía na coluna 0, terminando o block scalar `>`
do YAML no meio do comando → parse error → módulo recusado na hora de
instalar. O gate verify-install SIMULAVA os passos do Calamares
(rsync/cp/mkinitcpio) e só GREPAVA padrões no .conf — nunca o parseou.

Este script faz o que o Calamares real faz: parseia TODOS os .conf de
/etc/calamares como YAML e resolve as instâncias @id da sequência contra
a seção `instances` do settings.conf.

Uso:  validate-calamares.py <raiz-do-sistema>   (ex.: rootfs, ou / do live)
"""
import glob
import os
import sys

import yaml


def main(root: str) -> int:
    cal = os.path.join(root, "etc", "calamares")
    if not os.path.isdir(cal):
        print(f"✖ {cal} não existe — raiz errada?")
        return 1

    bad = []
    files = [os.path.join(cal, "settings.conf")] + sorted(
        glob.glob(os.path.join(cal, "modules", "*.conf"))
    )
    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                yaml.safe_load(fh)
        except Exception as e:
            first = str(e).splitlines()[0] if str(e) else repr(e)
            bad.append(f"{f}: {first}")
    if bad:
        print("✖ YAML INVÁLIDO no Calamares (o instalador recusaria o módulo):")
        for b in bad:
            print(f"    {b[:220]}")
        return 1

    sc = yaml.safe_load(open(os.path.join(cal, "settings.conf"), encoding="utf-8"))
    inst = {}
    for i in sc.get("instances") or []:
        mid = f"{i['module']}@{i['id']}"
        inst[mid] = i.get("config", f"{mid}.conf")
    seq: list[str] = []
    for phase in sc.get("sequence") or []:
        for key in ("show", "exec"):
            seq += phase.get(key) or []
    for m in seq:
        if "@" not in m:
            continue
        if m not in inst:
            print(f"✖ sequência referencia {m} SEM instância declarada")
            return 1
        cfg = inst[m]
        if not os.path.exists(os.path.join(cal, "modules", cfg)):
            print(f"✖ instância {m}: config modules/{cfg} AUSENTE")
            return 1

    print(
        f"✔ Calamares: {len(files)} confs YAML válidos · "
        f"{len(seq)} entradas de sequência resolúveis"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
