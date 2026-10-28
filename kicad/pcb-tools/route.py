"""Simple two-layer grid router for the be6502 board.

Grid A* (8 directions, 45-degree moves) on a 0.635 mm grid with keepout maps
on a 0.3175 mm fine grid. F.Cu prefers horizontal, B.Cu prefers vertical.
Rip-up and reroute for nets that fail.
"""
import heapq, math, sys, time
import pcbnew

IN, OUT = sys.argv[1], sys.argv[2]
OX, OY = 50.0, 50.0
W, H = 175.0, 125.0
G = 0.635
g = G / 2
NX, NY = int(round(W / G)) + 1, int(round(H / G)) + 1
FX, FY = 2 * NX - 1, 2 * NY - 1
NF = FX * FY
NC = NX * NY

CLR = 0.2
HW = {'sig': 0.1, 'pwr': 0.25}
VIA_R = 0.4
EDGE_CLR = 0.5
MARGIN = 0.04
POWER = ('VCC', 'GND')

board = pcbnew.LoadBoard(IN)
LAYERS = [pcbnew.F_Cu, pcbnew.B_Cu]


def to_mm(v):
    return pcbnew.ToMM(v.x) - OX, pcbnew.ToMM(v.y) - OY


# ---- pads ------------------------------------------------------------------
class Pad:
    pass

pads = []
for fp in board.GetFootprints():
    for p in fp.Pads():
        pd = Pad()
        pd.ref = fp.GetReference()
        pd.num = p.GetNumber()
        pd.net = p.GetNetCode()
        pd.name = p.GetNetname()
        poly = p.GetEffectivePolygon()
        o = poly.Outline(0)
        pd.pts = [to_mm(o.CPoint(k)) for k in range(o.PointCount())]
        xs = [q[0] for q in pd.pts]; ys = [q[1] for q in pd.pts]
        pd.bbox = (min(xs), min(ys), max(xs), max(ys))
        pd.c = to_mm(p.GetPosition())
        pd.hole = p.GetDrillSize().x > 0
        pads.append(pd)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L))
    qx, qy = ax + t * dx - px, ay + t * dy - py
    return math.hypot(qx, qy)


def poly_dist(px, py, pts):
    inside = False
    d = 1e9
    n = len(pts)
    for k in range(n):
        ax, ay = pts[k]; bx, by = pts[(k + 1) % n]
        if (ay > py) != (by > py):
            xi = ax + (py - ay) * (bx - ax) / (by - ay)
            if xi > px:
                inside = not inside
        d = min(d, seg_dist(px, py, ax, ay, bx, by))
    return 0.0 if inside else d


# keepout maps: one per (kind, layer). kinds: 'sig' (centerline of 0.1 half
# width track), 'pwr' (0.25 half width), 'via' (via centre).
# value: 0 free, net>0 owned by that net, -1 blocked
KINDS = ('sig', 'pwr', 'via')
RADIUS_FOR = {'sig': HW['sig'], 'pwr': HW['pwr'], 'via': VIA_R}


def blank():
    return {(k, L): [0] * NF for k in KINDS for L in (0, 1)}


def mark_pt(m, fi, fj, net):
    if 0 <= fi < FX and 0 <= fj < FY:
        idx = fj * FX + fi
        v = m[idx]
        if v == 0:
            m[idx] = net
        elif v != net:
            m[idx] = -1


_disk_cache = {}
def disk(r):
    key = round(r, 4)
    if key not in _disk_cache:
        n = int(r / g) + 1
        _disk_cache[key] = [(a, b) for a in range(-n, n + 1) for b in range(-n, n + 1)
                            if math.hypot(a * g, b * g) < r - 1e-6]
    return _disk_cache[key]


def mark_disk(maps, layers, fx, fy, own_r, net):
    """Mark keepout around a copper point at fine coords (fx, fy) with copper radius own_r."""
    for k in KINDS:
        r = own_r + CLR + RADIUS_FOR[k]
        for L in layers:
            m = maps[(k, L)]
            for a, b in disk(r):
                mark_pt(m, fx + a, fy + b, net)


base = blank()
t0 = time.time()
for pd in pads:
    net = pd.net if pd.net > 0 else -1
    for k in KINDS:
        r = CLR + RADIUS_FOR[k] + MARGIN
        if pd.net <= 0 and not pd.pts:
            continue
        x0, y0, x1, y1 = pd.bbox
        i0, i1 = max(0, int((x0 - r) / g)), min(FX - 1, int((x1 + r) / g) + 1)
        j0, j1 = max(0, int((y0 - r) / g)), min(FY - 1, int((y1 + r) / g) + 1)
        for fi in range(i0, i1 + 1):
            for fj in range(j0, j1 + 1):
                if poly_dist(fi * g, fj * g, pd.pts) < r:
                    for L in (0, 1):
                        mark_pt(base[(k, L)], fi, fj, net)
# board edge
for k in KINDS:
    r = EDGE_CLR + RADIUS_FOR[k]
    for fi in range(FX):
        for fj in range(FY):
            x, y = fi * g, fj * g
            if x < r or y < r or W - x < r or H - y < r:
                for L in (0, 1):
                    base[(k, L)][fj * FX + fi] = -1
print('keepouts built %.1fs' % (time.time() - t0))

# pad terminal nodes (coarse) per pad
for pd in pads:
    pd.nodes = []
    if pd.net <= 0:
        continue
    x0, y0, x1, y1 = pd.bbox
    for i in range(max(0, int(x0 / G)), min(NX - 1, int(x1 / G) + 1) + 1):
        for j in range(max(0, int(y0 / G)), min(NY - 1, int(y1 / G) + 1) + 1):
            if poly_dist(i * G, j * G, pd.pts) == 0.0:
                pd.nodes.append(j * NX + i)
    assert pd.nodes, (pd.ref, pd.num)

pad_node_net = {}
for pd in pads:
    for n in pd.nodes:
        pad_node_net[n] = pd.net

nets = {}
for pd in pads:
    if pd.net > 0:
        nets.setdefault(pd.net, []).append(pd)
netname = {pd.net: pd.name for pd in pads}

# ---- routed objects ------------------------------------------------------
# route[net] = list of ('seg', L, (i0,j0), (i1,j1)) and ('via', (i,j))
routes = {}


def kind_of(net):
    return 'pwr' if netname[net] in POWER else 'sig'


def stamp(maps, net, objs):
    hw = HW[kind_of(net)]
    for o in objs:
        if o[0] == 'via':
            i, j = o[1]
            mark_disk(maps, (0, 1), 2 * i, 2 * j, VIA_R, net)
        else:
            _, L, (i0, j0), (i1, j1) = o
            n = max(abs(i1 - i0), abs(j1 - j0)) * 2
            for s in range(n + 1):
                fi = 2 * i0 + (2 * (i1 - i0) * s) // n if n else 2 * i0
                fj = 2 * j0 + (2 * (j1 - j0) * s) // n if n else 2 * j0
                mark_disk(maps, (L,), fi, fj, hw, net)


def rebuild():
    maps = {k: v[:] for k, v in base.items()}
    for net, objs in routes.items():
        stamp(maps, net, objs)
    return maps


DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
VIA_COST = 12.0


def astar(maps, net, sources, targets, tgt_xy, soft=False):
    """sources/targets: sets of (L, node). Returns list of (L, node) or None."""
    kind = kind_of(net)
    mt = (maps[(kind, 0)], maps[(kind, 1)])
    mv = (maps[('via', 0)], maps[('via', 1)])
    tx, ty = tgt_xy

    def free(m, fidx):
        v = m[fidx]
        return v == 0 or v == net

    def h(n):
        i, j = n % NX, n // NX
        dx, dy = abs(i - tx), abs(j - ty)
        return (max(dx, dy) - min(dx, dy)) + 1.414 * min(dx, dy)

    best = {}
    prev = {}
    heap = []
    for s in sources:
        best[s] = 0.0
        prev[s] = None
        heapq.heappush(heap, (h(s[1]), 0.0, s))
    PEN = 30.0
    while heap:
        f, c, st = heapq.heappop(heap)
        if c > best.get(st, 1e18):
            continue
        if st in targets:
            path = []
            while st is not None:
                path.append(st); st = prev[st]
            return path[::-1]
        L, n = st
        i, j = n % NX, n // NX
        m = mt[L]
        for di, dj in DIRS:
            ni, nj = i + di, j + dj
            if not (0 <= ni < NX and 0 <= nj < NY):
                continue
            fn = (2 * nj) * FX + 2 * ni
            fm = (2 * j + dj) * FX + 2 * i + di
            pen = 0.0
            if not (free(m, fn) and free(m, fm)):
                if not soft or m[fn] == -2 or base[(kind, L)][fn] not in (0, net) \
                        or base[(kind, L)][fm] not in (0, net):
                    continue
                pen = PEN
            if di and dj:
                step = 1.414 * 1.25
            elif (dj == 0) == (L == 0):
                step = 1.0
            else:
                step = 2.2
            nn = nj * NX + ni
            ns = (L, nn)
            nc = c + step + pen
            if nc < best.get(ns, 1e18):
                best[ns] = nc; prev[ns] = st
                heapq.heappush(heap, (nc + h(nn), nc, ns))
        # layer change
        ns = (1 - L, n)
        fn = (2 * j) * FX + 2 * i
        if pad_node_net.get(n) == net:
            vc = 0.0
        elif free(mv[0], fn) and free(mv[1], fn):
            vc = VIA_COST
        elif soft and base[('via', 0)][fn] in (0, net) and base[('via', 1)][fn] in (0, net):
            vc = VIA_COST + PEN
        else:
            continue
        nc = c + vc
        if nc < best.get(ns, 1e18):
            best[ns] = nc; prev[ns] = st
            heapq.heappush(heap, (nc + h(n), nc, ns))
    return None


def path_objs(path, net):
    objs = []
    k = 0
    while k < len(path) - 1:
        L, n = path[k]
        L2, n2 = path[k + 1]
        if L2 != L:
            if pad_node_net.get(n) != net:
                objs.append(('via', (n % NX, n // NX)))
            k += 1
            continue
        # extend straight run
        i0, j0 = n % NX, n // NX
        di, dj = n2 % NX - i0, n2 // NX - j0
        e = k + 1
        while e + 1 < len(path) and path[e + 1][0] == L and \
                path[e + 1][1] % NX - path[e][1] % NX == di and \
                path[e + 1][1] // NX - path[e][1] // NX == dj:
            e += 1
        ie, je = path[e][1] % NX, path[e][1] // NX
        objs.append(('seg', L, (i0, j0), (ie, je)))
        k = e
    return objs


def route_net(maps, net, soft=False):
    pl = nets[net]
    remaining = list(range(1, len(pl)))
    tree = set((L, n) for n in pl[0].nodes for L in (0, 1))
    objs = []
    while remaining:
        # nearest remaining pad to the tree (by centre distance to pad 0 / tree)
        tnodes = [n for _, n in tree]
        def dist(pi):
            cx, cy = pl[pi].c
            return min(math.hypot((n % NX) * G - cx, (n // NX) * G - cy) for n in tnodes[::4] or tnodes)
        remaining.sort(key=dist)
        pi = remaining.pop(0)
        tgt = set((L, n) for n in pl[pi].nodes for L in (0, 1))
        if tgt & tree:
            tree |= tgt
            continue
        cx, cy = pl[pi].c
        path = astar(maps, net, tree, tgt, (cx / G, cy / G), soft)
        if path is None:
            return None
        po = path_objs(path, net)
        stamp(maps, net, po)
        objs += po
        tree |= set(path)
        tree |= tgt
    return objs


def bbox_hp(net):
    xs = [p.c[0] for p in nets[net]]; ys = [p.c[1] for p in nets[net]]
    return (max(xs) - min(xs)) + (max(ys) - min(ys))


order = sorted(nets, key=lambda n: (kind_of(n) != 'pwr', bbox_hp(n)))
order = [n for n in order if len(nets[n]) > 1]

maps = rebuild()
failed = []
t0 = time.time()
for net in order:
    o = route_net(maps, net)
    if o is None:
        failed.append(net)
        maps = rebuild()  # drop partial stamps
    else:
        routes[net] = o
print('first pass %.1fs, failed: %s' % (time.time() - t0, [netname[n] for n in failed]))


# rip-up and reroute
it = 0
queue = list(failed)
ripcount = {}
while queue and it < 200:
    it += 1
    net = queue.pop(0)
    maps = rebuild()
    o = route_net(maps, net)
    if o is not None:
        routes[net] = o
        continue
    # soft route: find nets in the way
    maps = rebuild()
    so = route_net(maps, net, soft=True)
    if so is None:
        print('cannot route even soft:', netname[net])
        continue
    # find victims: nets whose keepout is violated by so
    test = blank()
    stamp(test, net, so)
    victims = set()
    for other, oo in routes.items():
        if kind_of(other) == 'pwr':
            continue
        hw = HW[kind_of(other)]
        for ob in oo:
            if ob[0] == 'via':
                i, j = ob[1]; pts = [(L, 2 * i, 2 * j) for L in (0, 1)]
            else:
                _, L, (i0, j0), (i1, j1) = ob
                n = max(abs(i1 - i0), abs(j1 - j0)) * 2
                pts = [(L, 2 * i0 + (2 * (i1 - i0) * s) // n, 2 * j0 + (2 * (j1 - j0) * s) // n) for s in range(n + 1)]
            if any(test[('sig', L)][fj * FX + fi] not in (0, other) for L, fi, fj in pts):
                victims.add(other)
                break
    for v in victims:
        del routes[v]
        ripcount[v] = ripcount.get(v, 0) + 1
        queue.append(v)
    maps = rebuild()
    o = route_net(maps, net)
    if o is None:
        queue.append(net)
    else:
        routes[net] = o
print('after rip-up: %d iterations, unrouted: %s' % (it, [netname[n] for n in queue]))

# ---- write to board ----------------------------------------------------------
def P(i, j):
    return pcbnew.VECTOR2I(pcbnew.FromMM(OX + i * G), pcbnew.FromMM(OY + j * G))

netinfo = board.GetNetInfo()
for net, objs in routes.items():
    ni = netinfo.GetNetItem(net)
    w = pcbnew.FromMM(2 * HW[kind_of(net)])
    for o in objs:
        if o[0] == 'via':
            v = pcbnew.PCB_VIA(board)
            v.SetPosition(P(*o[1]))
            v.SetWidth(pcbnew.FromMM(0.8)); v.SetDrill(pcbnew.FromMM(0.4))
            v.SetNet(ni)
            board.Add(v)
        else:
            _, L, a, b = o
            t = pcbnew.PCB_TRACK(board)
            t.SetStart(P(*a)); t.SetEnd(P(*b))
            t.SetWidth(w); t.SetLayer(LAYERS[L]); t.SetNet(ni)
            board.Add(t)
pcbnew.SaveBoard(OUT, board)
print('saved', OUT)
