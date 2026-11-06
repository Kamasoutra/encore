// Injected into the Floorplan viewer by build.mjs.
// A last column much taller than the others shrinks the whole map to fit the screen. Its cards are dealt into two close
// columns, the second one staggered into the gaps of the first: ELK lays out the first column with each card standing
// for itself and the one beside it, then each pair is unfolded and the links to the column are routed again.
async function layoutTwoColumns(graph) {
  const GAP_X = 48, GAP_Y = 44, ELK_GAP = 28, PORT = 14, MARGIN = 40;
  const res = await elk.layout(structuredClone(graph));
  if (state.container !== 'root') return res;
  const cards = res.children || [];
  const last = cards.filter((c) => !cards.some((o) => o.x >= c.x + c.width));
  const inCol = new Set(last.map((c) => c.id));
  const others = cards.filter((c) => !inCol.has(c.id));
  const packed = (cs) => cs.reduce((s, c) => s + c.height, 0) + (cs.length - 1) * ELK_GAP;
  const layers = new Map();
  for (const c of others) layers.set(Math.round(c.x), [...(layers.get(Math.round(c.x)) || []), c]);
  if (last.length < 4 || !others.length || packed(last) < 1.25 * Math.max(...[...layers.values()].map(packed))) return res;
  if (graph.edges.some((e) => inCol.has(e.sources[0]) && inCol.has(e.targets[0]))) return res;

  // Pairs, top to bottom: the first card stays, the second goes right, centred on the gap below the first.
  const order = last.slice().sort((p, q) => p.y - q.y);
  const size = new Map(graph.children.map((c) => [c.id, c]));
  const colEnd = (e) => inCol.has(e.sources[0]) ? e.sources[0] : inCol.has(e.targets[0]) ? e.targets[0] : null;
  const degree = (id) => graph.edges.filter((e) => colEnd(e) === id).length;
  const pairs = [];
  for (let i = 0; i < order.length; i += 2) {
    const A = size.get(order[i].id), B = order[i + 1] && size.get(order[i + 1].id), next = order[i + 2] && size.get(order[i + 2].id);
    const gap = B ? Math.max(GAP_Y, degree(B.id) * PORT + 16, B.height + GAP_Y - Math.min(A.height, next ? next.height : Infinity)) : 0;
    pairs.push({ A, B, gap, height: !B ? A.height : next ? A.height + gap - ELK_GAP : A.height + gap / 2 + B.height / 2 });
  }
  const pairOf = new Map(pairs.flatMap((p) => [[p.A.id, p], ...(p.B ? [[p.B.id, p]] : [])]));
  const second = structuredClone(graph);
  second.children = second.children.filter((c) => !pairs.some((p) => p.B?.id === c.id));
  for (const c of second.children) if (pairOf.has(c.id)) c.height = pairOf.get(c.id).height;
  // Each pair takes its links on ports where they will really be: the first card's on its own side, the second's in the
  // gap it faces, each in the order ELK chose for them alone, a few pixels apart. ELK then draws them straight in.
  const endY = new Map((res.edges || []).map((e) => { const s = e.sections?.[0]; const id = s && colEnd(e); return [e.id, !s ? 0 : id === e.targets[0] ? s.endPoint.y : s.startPoint.y]; }));
  const spread = (list, centre, room) => { const g = Math.min(PORT, room / Math.max(1, list.length - 1)); return list.map((e, j) => [e, centre + (j - (list.length - 1) / 2) * g]); };
  for (const p of pairs) {
    const node = second.children.find((c) => c.id === p.A.id);
    const mine = (card) => second.edges.filter((e) => colEnd(graph.edges.find((x) => x.id === e.id)) === card.id).sort((a, b) => endY.get(a.id) - endY.get(b.id));
    const at = [...spread(mine(p.A), p.A.height / 2, p.A.height - 24), ...(p.B ? spread(mine(p.B), p.A.height + p.gap / 2, p.gap - 12) : [])];
    node.layoutOptions = { ...(node.layoutOptions || {}), 'elk.portConstraints': 'FIXED_POS' };
    node.ports = at.map(([e, y]) => ({ id: 'port:' + e.id, x: -1, y: y - 0.5, width: 1, height: 1, layoutOptions: { 'elk.port.side': 'WEST' } }));
    for (const [e] of at) {
      if (inCol.has(e.targets[0])) e.targets = ['port:' + e.id]; else e.sources = ['port:' + e.id];
    }
  }
  for (const e of second.edges) {
    if (pairOf.has(e.sources[0])) e.sources = [pairOf.get(e.sources[0]).A.id];
    if (pairOf.has(e.targets[0])) e.targets = [pairOf.get(e.targets[0]).A.id];
  }
  const out = await elk.layout(second);

  // Unfold: each card back to its own size, the second of a pair beside the first.
  const at = new Map(out.children.map((c) => [c.id, c]));
  const colX = Math.min(...pairs.map((p) => at.get(p.A.id).x));
  const width = Math.max(...order.map((c) => c.width));
  for (const p of pairs) {
    const a = at.get(p.A.id);
    a.height = p.A.height;
    if (!p.B) continue;
    const mid = a.y + a.height + p.gap / 2;
    p.slot = [a.y + a.height, a.y + a.height + p.gap];
    out.children.push({ ...size.get(p.B.id), x: colX + width + GAP_X, y: mid - p.B.height / 2 });
  }
  const cardOf = new Map(out.children.map((c) => [c.id, c]));

  // Links to a card moved right go on, level, through the gap, to its side.
  for (const e of out.edges || []) {
    const real = graph.edges.find((x) => x.id === e.id), id = colEnd(real), s = e.sections?.[0];
    e.sources = real.sources; e.targets = real.targets;
    if (!id || !s || cardOf.get(id).x === colX) continue;
    if (inCol.has(real.targets[0])) s.endPoint = { x: cardOf.get(id).x, y: s.endPoint.y };
    else s.startPoint = { x: cardOf.get(id).x, y: s.startPoint.y };
  }

  untangle(out);
  const points = (out.edges || []).flatMap((e) => (e.sections || []).flatMap((s) => [s.startPoint, ...(s.bendPoints || []), s.endPoint]));
  out.width = Math.max(...out.children.map((c) => c.x + c.width), ...points.map((p) => p.x)) + MARGIN;
  out.height = Math.max(...out.children.map((c) => c.y + c.height), ...points.map((p) => p.y)) + MARGIN;
  return out;
}

// Two links swap the heights of their starting points, or of two of their horizontal runs between two turns, while that
// removes crossings without running through a card: the order ELK chose no longer matches once the column is unfolded.
function untangle(res) {
  const paths = (res.edges || []).map((e) => e.sections?.[0]).filter(Boolean).map((s) => [s.startPoint, ...(s.bendPoints || []), s.endPoint]);
  const segs = (pts) => pts.slice(1).map((p, i) => [pts[i], p]);
  const cross = ([a, b], [c, d]) => {
    const h = a.y === b.y ? [a, b] : c.y === d.y ? [c, d] : null, v = h && (h[0] === a ? [c, d] : [a, b]);
    if (!h || v[0].x !== v[1].x) return 0;
    const [x0, x1] = [Math.min(h[0].x, h[1].x), Math.max(h[0].x, h[1].x)], [y0, y1] = [Math.min(v[0].y, v[1].y), Math.max(v[0].y, v[1].y)];
    return v[0].x > x0 + 0.5 && v[0].x < x1 - 0.5 && h[0].y > y0 + 0.5 && h[0].y < y1 - 0.5 ? 1 : 0;
  };
  const hits = ([a, b]) => res.children.filter((c) => Math.max(a.x, b.x) > c.x + 1 && Math.min(a.x, b.x) < c.x + c.width - 1 && Math.max(a.y, b.y) > c.y + 1 && Math.min(a.y, b.y) < c.y + c.height - 1).length;
  const cost = () => {
    const all = paths.map(segs); let n = 0;
    for (let i = 0; i < all.length; i++) { for (const s of all[i]) n += 100 * hits(s); for (let j = i + 1; j < all.length; j++) for (const s of all[i]) for (const t of all[j]) n += cross(s, t); }
    return n;
  };
  // What can move: a start or end followed by a turn, and a horizontal run with a turn at each end.
  const runs = [];
  for (const pts of paths) {
    const n = pts.length - 1;
    if (n >= 3 && pts[1].y === pts[0].y && pts[2].x === pts[1].x) runs.push({ pts: [pts[0], pts[1]], side: pts[0], lane: [pts[1], pts[2]] });
    if (n >= 3 && pts[n - 1].y === pts[n].y && pts[n - 2].x === pts[n - 1].x) runs.push({ pts: [pts[n - 1], pts[n]], side: pts[n], lane: [pts[n - 1], pts[n - 2]] });
    for (let i = 1; i + 2 <= n - 1; i++) if (pts[i].y === pts[i + 1].y && pts[i - 1].x === pts[i].x && pts[i + 2].x === pts[i + 1].x) runs.push({ pts: [pts[i], pts[i + 1]] });
  }
  // Starts only swap on the same side of the same card, so that every link still leaves from where it did.
  const card = (p) => res.children.find((c) => (Math.abs(p.x - c.x) < 1 || Math.abs(p.x - c.x - c.width) < 1) && p.y >= c.y && p.y <= c.y + c.height);
  for (const r of runs) if (r.side) r.at = card(r.side) && `${card(r.side).id}|${Math.round(r.side.x)}`;
  const set = (r, y) => { for (const p of r.pts) p.y = y; };
  const setX = (r, x) => { for (const p of r.lane) p.x = x; };
  // Two links from the same side may need to trade their start, their lane beside the card, or both at once.
  const moves = (a, b) => {
    const ya = a.pts[0].y, yb = b.pts[0].y, xa = a.lane?.[0].x, xb = b.lane?.[0].x;
    const list = [[() => { set(a, yb); set(b, ya); }, () => { set(a, ya); set(b, yb); }]];
    if (a.side && xa !== xb) {
      list.push([() => { setX(a, xb); setX(b, xa); }, () => { setX(a, xa); setX(b, xb); }]);
      list.push([() => { set(a, yb); set(b, ya); setX(a, xb); setX(b, xa); }, () => { set(a, ya); set(b, yb); setX(a, xa); setX(b, xb); }]);
    }
    return list;
  };
  let best = cost();
  for (let round = 0, better = true; better && round < 20; round++) {
    better = false;
    for (let i = 0; i < runs.length; i++) for (let j = i + 1; j < runs.length; j++) {
      const a = runs[i], b = runs[j];
      if (!!a.side !== !!b.side || (a.side && (!a.at || a.at !== b.at)) || a.pts[0].y === b.pts[0].y) continue;
      for (const [go, back] of moves(a, b)) {
        go();
        const n = cost();
        if (n < best) { best = n; better = true; break; } else back();
      }
    }
  }
}
