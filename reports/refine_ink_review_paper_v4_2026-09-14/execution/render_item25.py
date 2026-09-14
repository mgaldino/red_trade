#!/usr/bin/env python3
"""Render the explanatory note, with layout-only line breaking."""
from pathlib import Path
import argparse,subprocess
p=argparse.ArgumentParser();p.add_argument('build_directory',type=Path);a=p.parse_args()
here=Path(__file__).resolve().parent
build=a.build_directory.resolve();build.mkdir(parents=True,exist_ok=True)
text=(here/'domain_note.md').read_text()
anchor='5. `selective_unga_domain_fe_weights`'
assert text.count(anchor)==1
# Preserve the semantic list after the indented paragraph for item 4.
text=text.replace('\n'+anchor,'\n\n'+anchor)
layout=build/'domain_note_layout.md';layout.write_text(text)
subprocess.run(['pandoc',str(layout),'-f','markdown+tex_math_single_backslash','--lua-filter='+str(here/'note_layout.lua'),'--pdf-engine=xelatex','-V','fontsize=11pt','-V','geometry:margin=25mm','-o',str(build/'item25.pdf')],check=True)
