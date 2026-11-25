# Phase-5 preparation only; preserves the owner project and all run outputs.
from pathlib import Path
import xml.etree.ElementTree as ET
root=Path('C:/vivado_verilog_proj/NOC_PQATTEST');out=Path(__file__).resolve().parent
assert out==Path('C:/vivado_verilog_proj/_r10g2')
target=out/'NOC_PQATTEST.xpr'
assert not target.exists(),'isolated project already exists; inspect before retrying'
tree=ET.parse(root/'NOC_PQATTEST.xpr');project=tree.getroot();project.set('Path',target.as_posix())
def source_path(text):
    return text.replace('$PPRDIR',root.as_posix()).replace('$PSRCDIR',(root/'NOC_PQATTEST.srcs').as_posix())
for f in project.iter('File'):
    if 'Path' in f.attrib:f.set('Path',source_path(f.get('Path')))
for node in project.iter():
    for key,value in list(node.attrib.items()):
        if key.endswith('TclHook'):node.set(key,source_path(value))
# PRUNDIR, PCACHEDIR, RelSrcDir and generated-output directories remain local to the copied project.
tree.write(target,encoding='UTF-8',xml_declaration=True)
print('Prepared isolated project copy:',target)
