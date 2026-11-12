// ================================================================ shared helpers for the later batches
// Affine helper: rotate local coordinates by deg around (cx, cy); returns a point formatter.
function turn(deg, cx, cy, scale, dx, dy) {
	const a = (deg * Math.PI) / 180;
	const k = scale || 1;
	const f = (x, y) => {
		const X = (dx || 0) + cx + k * ((x - cx) * Math.cos(a) - (y - cy) * Math.sin(a));
		const Y = (dy || 0) + cy + k * ((x - cx) * Math.sin(a) + (y - cy) * Math.cos(a));
		return [r1(X), r1(Y)];
	};
	const p = (x, y) => f(x, y).join(" ");
	p.xy = f;
	p.deg = deg;
	p.k = k;
	return p;
}
// Several shapes with one navy outline around their union: navy underlay, then the paint on top.
// item: { d, paint, w } where w is a stroke width for line shapes (omit for filled shapes)
function union(a, items, edge) {
	const e = edge || 18;
	for (const it of items) {
		if (it.w) {
			a.stroke(it.d, a.s("outline"), it.w + 2 * e);
		} else {
			a.fill(it.d, a.s("outline"));
			a.stroke(it.d, a.s("outline"), 2 * e);
		}
	}
	for (const it of items) {
		if (it.w) {
			a.stroke(it.d, it.paint, it.w);
		} else {
			a.fill(it.d, it.paint);
		}
	}
}
// Mitten, cuff at the bottom, drawn through a point formatter p
function mitten(a, p, body, cuff) {
	const palm = `M${p(176, 336)}L${p(176, 180)}C${p(176, 128)} ${p(212, 92)} ${p(256, 92)}C${p(300, 92)} ${p(336, 128)} ${p(336, 180)}L${p(336, 336)}Z`;
	const c = p.xy(142, 262);
	const thumb = a.ellipse(c[0], c[1], 44 * p.k, 74 * p.k, -22 + p.deg);
	union(a, [
		{ d: thumb, paint: body },
		{ d: palm, paint: body },
	]);
	a.stroke(`M${p(206, 200)}L${p(206, 150)}`, a.s("hi"), 14, ".9");
	const cuffD = `M${p(164, 336)}L${p(348, 336)}L${p(348, 420)}L${p(164, 420)}Z`;
	a.fill(cuffD, a.s("outline"));
	a.stroke(cuffD, a.s("outline"), 52);
	a.fill(cuffD, cuff);
	a.stroke(cuffD, cuff, 16);
	a.stroke(`M${p(210, 356)}L${p(210, 400)}M${p(256, 356)}L${p(256, 400)}M${p(302, 356)}L${p(302, 400)}`, a.s("steel-m"), 10);
}

// ---------------------------------------------------------------- tool_hand: blue mitten
icon("tool_hand", (a) => {
	const p = turn(18, 256, 256, 1.18, 8, -4);
	mitten(a, p, a.g(150, 90, 380, 400, ["light", "mid", "dark"]), a.s("hi"));
});

// ---------------------------------------------------------------- tool_shovel: snow shovel
icon("tool_shovel", (a) => {
	const p = turn(35, 256, 256, 0.98, -14, 10);
	a.note("handle");
	const wood = a.g(150, 420, 330, 200, ["wood-l", "wood-m"]);
	a.tube(`M${p(256, 470)}L${p(256, 236)}`, wood, 30, 66);
	a.tube(`M${p(212, 474)}L${p(300, 474)}`, wood, 30, 66);
	a.note("blade");
	const blade = `M${p(140, 40)}L${p(372, 40)}L${p(350, 236)}Q${p(256, 262)} ${p(162, 236)}Z`;
	a.fill(blade, a.g(250, 20, 420, 260, ["hi", "steel-l", "steel-m"]));
	a.stroke(`M${p(214, 76)}L${p(222, 206)}M${p(298, 76)}L${p(290, 206)}`, a.s("steel-d"), 12, ".7");
	a.stroke(`M${p(168, 66)}L${p(182, 190)}`, a.s("hi"), 14, ".9");
	a.stroke(blade, a.s("outline"), 18);
});

// ---------------------------------------------------------------- tool_snow_pusher: wide scraper with a U handle
icon("tool_snow_pusher", (a) => {
	const p = turn(28, 256, 262, 0.82, -6, 0);
	a.note("handle");
	const handle = `M${p(172, 180)}L${p(172, 400)}Q${p(172, 460)} ${p(256, 460)}Q${p(340, 460)} ${p(340, 400)}L${p(340, 180)}`;
	a.tube(handle, a.s("steel-l"), 26, 62);
	a.tube(`M${p(196, 462)}L${p(316, 462)}`, a.s("red-m"), 30, 66);
	a.note("blade");
	const blade = `M${p(72, 70)}L${p(440, 70)}L${p(440, 196)}L${p(72, 196)}Z`;
	const gold = a.g(200, 20, 380, 240, ["gold-l", "gold-m", "gold-d"]);
	a.fill(blade, a.s("outline"));
	a.stroke(blade, a.s("outline"), 56);
	a.fill(blade, gold);
	a.stroke(blade, gold, 20);
	a.stroke(`M${p(76, 190)}L${p(436, 190)}`, a.s("steel-d"), 26);
	a.stroke(`M${p(96, 92)}L${p(220, 92)}`, a.s("hi"), 14, ".9");
});

// ---------------------------------------------------------------- tool_snowblower: machine, side view
icon("tool_snowblower", (a) => {
	a.note("handle");
	a.tube("M356 262L452 118", a.s("steel-l"), 24, 60);
	a.tube("M430 104L476 134", a.s("steel-d"), 26, 62);
	a.note("chute");
	const red = a.g(120, 100, 400, 400, ["red-l", "red-m", "red-d"]);
	a.tube("M262 236V150Q262 96 196 92", red, 44, 80);
	a.note("body");
	a.shape(a.rrect(170, 214, 220, 150, 34), red, 18);
	a.stroke("M206 244H300", a.s("hi"), 14, ".9");
	a.note("wheel");
	a.shape(a.circle(344, 392, 64), a.s("steel-d"), 18);
	a.fill(a.circle(344, 392, 24), a.s("steel-l"));
	a.note("auger housing");
	a.shape(a.circle(152, 334, 110), a.g(60, 240, 240, 440, ["red-m", "red-d"]), 18);
	a.shape(a.circle(152, 334, 70), a.g(90, 270, 210, 400, ["hi", "steel-l", "steel-m"]), 14);
	a.stroke("M108 300L196 368M108 368L196 300", a.s("steel-d"), 16);
	a.note("snow");
	a.fill(a.circle(128, 64, 22), a.s("hi"));
	a.stroke(a.circle(128, 64, 22), a.s("outline"), 10);
	a.fill(a.circle(74, 110, 16), a.s("hi"));
	a.stroke(a.circle(74, 110, 16), a.s("outline"), 10);
});
