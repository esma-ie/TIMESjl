"""Register the PyPI HiGHS package (gamspy_highs) with the PyPI GAMS system (gamspy_base).

gamspy_base ships CONVERT, CONOPT and demo CPLEX; HiGHS comes as the separate
gamspy_highs package and must be copied into the system directory and listed
in gmscmpun.txt, which is what `gamspy install solver highs` does. This script
does the same without pulling in gamspy itself.
"""

import os
import shutil

import gamspy_base
import gamspy_highs


def main() -> None:
    d = gamspy_base.directory
    for p in gamspy_highs.file_paths:
        shutil.copy(p, d)
    cmp = os.path.join(d, "gmscmpun.txt")
    txt = open(cmp).read()
    if "\nHIGHS " in txt or txt.startswith("HIGHS "):
        print("HiGHS already registered in", cmp)
        return
    block = gamspy_highs.verbatim + "\n"
    i = txt.find("DEFAULTS")
    txt = txt[:i] + block + txt[i:] if i >= 0 else txt + "\n" + block
    open(cmp, "w").write(txt)
    print("HiGHS registered in", cmp)


if __name__ == "__main__":
    main()
