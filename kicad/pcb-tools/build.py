"""Build an unrouted be6502.kicad_pcb from the exported netlist."""
import re, sys
import pcbnew

NET, OUT = sys.argv[1], sys.argv[2]
FPLIB = '/usr/share/kicad/footprints'
OX, OY = 50.0, 50.0          # board origin on the page
W, H = 175.0, 125.0          # board size

# ---- tiny s-expression parser ------------------------------------------
def parse(text):
    toks = re.findall(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+', text)
    stack = [[]]
    for t in toks:
        if t == '(':
            stack.append([])
        elif t == ')':
            e = stack.pop(); stack[-1].append(e)
        else:
            stack[-1].append(t[1:-1] if t.startswith('"') else t)
    return stack[0][0]

def find(e, key):
    return [c for c in e if isinstance(c, list) and c and c[0] == key]

def val(e, key):
    r = find(e, key)
    return r[0][1] if r else None

root = parse(open(NET).read())
comps = {}
for c in find(find(root, 'components')[0], 'comp'):
    sp = find(c, 'sheetpath')[0]
    comps[val(c, 'ref')] = dict(value=val(c, 'value'), fp=val(c, 'footprint'),
                                path=val(sp, 'tstamps') + val(c, 'tstamps'))
nets = {}
for n in find(find(root, 'nets')[0], 'net'):
    nets[val(n, 'name')] = [(val(x, 'ref'), val(x, 'pin')) for x in find(n, 'node')]

# ---- placement: (x, y, rotation) in board mm, y down -------------------
# DIPs at 90 deg lie horizontally, pin 1 bottom-left, notch on the left.
P = {
    # row A: CPU, bank latch, GAL, 12 MHz oscillator
    'U1': (14, 40, 90), 'U2': (76, 32, 90), 'U3': (110, 32, 90), 'X1': (151, 32, 90),
    # row B: ROM, RAM, 74HC138
    'U4': (14, 72, 90), 'U5': (62, 72, 90), 'U6': (115, 64, 90),
    # row C: VIA, ACIA, 1.8432 MHz oscillator
    'U7': (14, 104, 90), 'U8': (76, 104, 90), 'X2': (127, 104, 90),
    # RS-232 corner
    'U9': (138, 87, 90), 'J2': (163, 94, 90),
    'C2': (140, 72, 0), 'C3': (148, 72, 0), 'C4': (156, 72, 0), 'C5': (150, 94, 0),
    # power, reset
    'J1': (12, 8, 0), 'C1': (25, 8, 0),
    'R1': (40, 8, 0), 'R2': (40, 14, 0), 'SW1': (58, 6, 0),
}
# Port B LEDs and resistors along the bottom edge under the VIA
for i in range(8):
    P['D%d' % (i + 1)] = (12 + i * 7, 115, 90)
    P['R%d' % (i + 3)] = (66 + i * 5.08, 110.5, 270)

board = pcbnew.BOARD()
ds = board.GetDesignSettings()
ds.SetCopperLayerCount(2)

# net classes: power nets wider
nc_default = ds.m_NetSettings.m_DefaultNetClass
nc_default.SetTrackWidth(pcbnew.FromMM(0.2))
nc_default.SetClearance(pcbnew.FromMM(0.2))
nc_default.SetViaDiameter(pcbnew.FromMM(0.8))
nc_default.SetViaDrill(pcbnew.FromMM(0.4))
pwr = pcbnew.NETCLASS('Power')
pwr.SetTrackWidth(pcbnew.FromMM(0.5))
pwr.SetClearance(pcbnew.FromMM(0.2))
pwr.SetViaDiameter(pcbnew.FromMM(0.8))
pwr.SetViaDrill(pcbnew.FromMM(0.4))
ds.m_NetSettings.m_NetClasses['Power'] = pwr

netinfo = {}
for name in nets:
    ni = pcbnew.NETINFO_ITEM(board, name)
    board.Add(ni)
    if name in ('VCC', 'GND'):
        ni.SetNetClass(pwr)
    netinfo[name] = ni

pad_net = {}
for name, nodes in nets.items():
    for ref, pin in nodes:
        pad_net[(ref, pin)] = name

def mm(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))

for ref, c in sorted(comps.items()):
    lib, name = c['fp'].split(':')
    fp = pcbnew.FootprintLoad(f'{FPLIB}/{lib}.pretty', name)
    assert fp, c['fp']
    fp.SetReference(ref)
    fp.SetValue(c['value'])
    fp.SetFPIDAsString(c['fp']) if hasattr(fp, 'SetFPIDAsString') else fp.SetFPID(pcbnew.LIB_ID(lib, name))
    fp.SetPath(pcbnew.KIID_PATH(c['path'].rstrip('/')))
    x, y, rot = P[ref]
    x, y = round(x / 1.27) * 1.27, round(y / 1.27) * 1.27
    fp.SetPosition(mm(x, y))
    fp.SetOrientationDegrees(rot)
    board.Add(fp)
    for pad in fp.Pads():
        n = pad_net.get((ref, pad.GetNumber()))
        if n:
            pad.SetNet(netinfo[n])
        elif pad.GetNumber() not in ('', '0'):
            pad.SetNetCode(0)

# board outline with rounded corners left square for simplicity
pts = [(0, 0), (W, 0), (W, H), (0, H)]
for i in range(4):
    s = pcbnew.PCB_SHAPE(board)
    s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(mm(*pts[i])); s.SetEnd(mm(*pts[(i + 1) % 4]))
    s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(pcbnew.FromMM(0.1))
    board.Add(s)

# mounting holes
for i, (x, y) in enumerate([(4, 4), (W - 4, 4), (4, H - 4), (W - 4, H - 4)]):
    fp = pcbnew.FootprintLoad(f'{FPLIB}/MountingHole.pretty', 'MountingHole_3.2mm_M3')
    fp.SetReference('H%d' % (i + 1))
    fp.SetFPID(pcbnew.LIB_ID('MountingHole', 'MountingHole_3.2mm_M3'))
    fp.SetBoardOnly(True)
    fp.Reference().SetVisible(False)
    fp.SetPosition(mm(x, y))
    board.Add(fp)

# board title on the front silkscreen
for txt, y, size in [('be6502', 44, 2.5), ('W65C816S breadboard computer', 49, 1.2)]:
    st = pcbnew.PCB_TEXT(board)
    st.SetText(txt)
    st.SetLayer(pcbnew.F_SilkS)
    st.SetPosition(mm(157, y))
    st.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size)))
    st.SetTextThickness(pcbnew.FromMM(size * 0.15))
    board.Add(st)

pcbnew.SaveBoard(OUT, board)
print('saved', OUT, len(comps), 'footprints', len(nets), 'nets')
