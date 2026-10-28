"""Add GND pours on both layers, fill them and write a DRC report."""
import sys
import pcbnew

IN, OUT, RPT = sys.argv[1:4]
OX, OY, W, H = 50.0, 50.0, 175.0, 125.0
b = pcbnew.LoadBoard(IN)
gnd = b.FindNet('GND')

for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
    z = pcbnew.ZONE(b)
    z.SetLayer(layer)
    z.SetNet(gnd)
    z.SetLocalClearance(pcbnew.FromMM(0.3))
    z.SetMinThickness(pcbnew.FromMM(0.25))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
    z.SetThermalReliefGap(pcbnew.FromMM(0.4))
    z.SetThermalReliefSpokeWidth(pcbnew.FromMM(0.5))
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    o = z.Outline()
    o.NewOutline()
    for x, y in [(0, 0), (W, 0), (W, H), (0, H)]:
        o.Append(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))
    b.Add(z)

pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(OUT, b)
pcbnew.WriteDRCReport(b, RPT, pcbnew.EDA_UNITS_MILLIMETRES, True)
print('saved', OUT)
