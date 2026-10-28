"""Composite per-layer KiCad SVG plots into realistic-looking board images."""
import re, subprocess, sys
import pcbnew

PCB, OUTDIR = sys.argv[1], sys.argv[2]
OX, OY, W, H = 50.0, 50.0, 175.0, 125.0
b = pcbnew.LoadBoard(PCB)

MASK = '#1f5f35'
COPPER_UNDER = '#2f7d44'
PAD = '#d2ac55'
SILK = '#f4f4f0'
HOLE = '#16181a'


def plot(layer, mirror):
    out = f'{OUTDIR}/{layer}{"_m" if mirror else ""}.svg'
    cmd = ['kicad-cli', 'pcb', 'export', 'svg', '--layers', layer, '--page-size-mode', '2',
           '--exclude-drawing-sheet', '--black-and-white', '--drill-shape-opt', '0', '-o', out, PCB]
    if mirror:
        cmd.insert(4, '--mirror')
    subprocess.run(cmd, check=True, capture_output=True)
    return open(out).read()


def inner(svg, color, opacity=1.0):
    svg = svg[svg.index('<svg'):]
    svg = re.sub(r'width="[^"]*" height="[^"]*"', f'x="0" y="0" width="{VW}" height="{VH}"', svg, count=1)
    svg = svg.replace('#000000', color).replace('#000', color)
    return f'<g opacity="{opacity}">{svg}</g>'


ref = plot('Edge.Cuts', False)
vb = re.search(r'viewBox="([^"]*)"', ref).group(1)
VW, VH = map(float, vb.split()[2:])
# outline origin: the min x of the outline segments and min y
paths = re.findall(r'M([\d.]+) ([\d.]+)\s*L([\d.]+) ([\d.]+)', ref)
bx0 = min(min(float(p[0]), float(p[2])) for p in paths)
by0 = min(min(float(p[1]), float(p[3])) for p in paths)


def xy(v, mirror):
    x = pcbnew.ToMM(v.x) - OX + bx0
    y = pcbnew.ToMM(v.y) - OY + by0
    return (VW - x if mirror else x), y


def holes(mirror):
    s = []
    for fp in b.GetFootprints():
        for p in fp.Pads():
            d = p.GetDrillSize()
            if d.x > 0:
                x, y = xy(p.GetPosition(), mirror)
                s.append(f'<circle cx="{x:.3f}" cy="{y:.3f}" r="{pcbnew.ToMM(d.x) / 2:.3f}" fill="{HOLE}"/>')
    for t in b.GetTracks():
        if t.GetClass() == 'PCB_VIA':
            x, y = xy(t.GetPosition(), mirror)
            s.append(f'<circle cx="{x:.3f}" cy="{y:.3f}" r="{pcbnew.ToMM(t.GetDrillValue()) / 2:.3f}" fill="{HOLE}"/>')
    return '\n'.join(s)


def body_box(fp, layer=pcbnew.F_Fab):
    ext = None
    for it in fp.GraphicalItems():
        if it.GetLayer() == layer:
            r = it.GetBoundingBox()
            e = (r.GetLeft(), r.GetTop(), r.GetRight(), r.GetBottom())
            ext = e if ext is None else (min(ext[0], e[0]), min(ext[1], e[1]), max(ext[2], e[2]), max(ext[3], e[3]))
    return ext


def parts():
    """Very rough top-view bodies for a populated look."""
    s = []
    for fp in b.GetFootprints():
        ref = fp.GetReference()
        fid = fp.GetFPID().GetLibItemName().wx_str()
        bb = body_box(fp)
        if bb is None or ref.startswith('H'):
            continue
        x0, y0 = xy(pcbnew.VECTOR2I(bb[0], bb[1]), False)
        x1, y1 = xy(pcbnew.VECTOR2I(bb[2], bb[3]), False)
        w, h = x1 - x0, y1 - y0
        cx, cy = x0 + w / 2, y0 + h / 2
        val = fp.GetValue()
        if fid.startswith('DIP') or fid.startswith('Oscillator'):
            fill = '#c9ccd1' if fid.startswith('Oscillator') else '#222326'
            txt = '#333' if fid.startswith('Oscillator') else '#d8d8d8'
            s.append(f'<rect x="{x0:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{h:.2f}" rx="0.6" fill="{fill}" stroke="#0008" stroke-width="0.2"/>')
            if fid.startswith('DIP'):
                # notch on the pin-1 end (left, since DIPs are rotated 90)
                s.append(f'<path d="M{x0:.2f} {cy - 1.2:.2f} a1.2 1.2 0 0 1 0 2.4" fill="#111"/>')
            fs = min(2.2, h * 0.22)
            s.append(f'<text x="{cx:.2f}" y="{cy:.2f}" font-family="Helvetica,Arial,sans-serif" font-size="{fs:.2f}" fill="{txt}" text-anchor="middle" dominant-baseline="middle">{val}</text>')
            s.append(f'<text x="{x0 + 2:.2f}" y="{y1 - 1:.2f}" font-family="Helvetica,Arial,sans-serif" font-size="1.3" fill="{txt}" opacity="0.7">{ref}</text>')
        elif ref.startswith('D'):
            s.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{min(w, h) / 2:.2f}" fill="#e23b2e" stroke="#7a1410" stroke-width="0.3"/>')
            s.append(f'<circle cx="{cx - 0.4:.2f}" cy="{cy - 0.4:.2f}" r="{min(w, h) / 6:.2f}" fill="#fff" opacity="0.45"/>')
        elif ref.startswith('R'):
            # body is the middle of the fab outline; leads run to the pads
            pads = [xy(p.GetPosition(), False) for p in fp.Pads()]
            (ax, ay), (bx2, by2) = pads
            s.append(f'<line x1="{ax:.2f}" y1="{ay:.2f}" x2="{bx2:.2f}" y2="{by2:.2f}" stroke="#b9b9b9" stroke-width="0.5"/>')
            s.append(f'<rect x="{x0:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{h:.2f}" rx="1" fill="#d9c08f" stroke="#8a7350" stroke-width="0.2"/>')
            vertical = h > w
            for k, c in enumerate(['#6b3a1e', '#111', '#c0392b', '#c9a227']):  # brown black red gold = 1k
                f = 0.22 + k * 0.17 + (0.08 if k == 3 else 0)
                if vertical:
                    s.append(f'<rect x="{x0:.2f}" y="{y0 + h * f:.2f}" width="{w:.2f}" height="{h * 0.07:.2f}" fill="{c}"/>')
                else:
                    s.append(f'<rect x="{x0 + w * f:.2f}" y="{y0:.2f}" width="{w * 0.07:.2f}" height="{h:.2f}" fill="{c}"/>')
        elif ref.startswith('C'):
            r = min(w, h) / 2
            s.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="#1b2f6b" stroke="#0d1838" stroke-width="0.2"/>')
            s.append(f'<path d="M{cx + r * 0.55:.2f} {cy - r * 0.83:.2f} A{r:.2f} {r:.2f} 0 0 1 {cx + r * 0.55:.2f} {cy + r * 0.83:.2f}" fill="none" stroke="#c9d3ee" stroke-width="{r * 0.35:.2f}"/>')
            s.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r * 0.55:.2f}" fill="none" stroke="#9aa6c8" stroke-width="0.15"/>')
        elif ref.startswith('SW'):
            s.append(f'<rect x="{x0:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{h:.2f}" rx="0.4" fill="#2a2a2a"/>')
            s.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{min(w, h) * 0.3:.2f}" fill="#d43a3a"/>')
        elif ref == 'J1':
            s.append(f'<rect x="{x0:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{h:.2f}" rx="0.4" fill="#2f8a4a" stroke="#1c5a2f" stroke-width="0.3"/>')
            for p in fp.Pads():
                px, py = xy(p.GetPosition(), False)
                s.append(f'<circle cx="{px:.2f}" cy="{py:.2f}" r="1.5" fill="#b8bcc2" stroke="#666" stroke-width="0.2"/>')
                s.append(f'<line x1="{px - 1:.2f}" y1="{py:.2f}" x2="{px + 1:.2f}" y2="{py:.2f}" stroke="#555" stroke-width="0.35"/>')
        elif ref == 'J2':
            s.append(f'<rect x="{x0:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{h:.2f}" rx="0.8" fill="#9ea3a8" stroke="#5d6166" stroke-width="0.3"/>')
            s.append(f'<rect x="{x0 + w * 0.15:.2f}" y="{y0 + h * 0.22:.2f}" width="{w * 0.55:.2f}" height="{h * 0.56:.2f}" rx="0.8" fill="#2b2d30"/>')
    return '\n'.join(s)


def compose(side, populated=False):
    mirror = side == 'back'
    p = 'B' if mirror else 'F'
    cu, mask, silk = plot(f'{p}.Cu', mirror), plot(f'{p}.Mask', mirror), plot(f'{p}.SilkS', mirror)
    bx = VW - bx0 - W if mirror else bx0
    body = [
        f'<rect x="{bx:.3f}" y="{by0:.3f}" width="{W}" height="{H}" rx="1.5" fill="{MASK}"/>',
        inner(cu, COPPER_UNDER),
        inner(mask, PAD),
        holes(mirror),
        inner(silk, SILK),
    ]
    if populated:
        body.append(parts())
    pad = 3
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-pad} {-pad} {VW + 2 * pad} {VH + 2 * pad}">'
            f'<rect x="{-pad}" y="{-pad}" width="{VW + 2 * pad}" height="{VH + 2 * pad}" fill="#ffffff"/>'
            + '\n'.join(body) + '</svg>')


for name, side, pop in [('front', 'front', False), ('back', 'back', False), ('populated', 'front', True)]:
    open(f'{OUTDIR}/{name}.svg', 'w').write(compose(side, pop))
print('ok', VW, VH, bx0, by0)
