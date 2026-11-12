// ================================================================ batch C
// Coin face: bevel, inner ring, optional snowflake mark, highlight, outline
function coin(a, cx, cy, r, mark) {
	const d = a.circle(cx, cy, r);
	a.fill(d, a.g(cx - r * 0.7, cy - r * 0.7, cx + r * 0.7, cy + r * 0.7, ["gold-l", "gold-m", "gold-d"]));
	const inner = a.circle(cx, cy, r * 0.68);
	a.fill(inner, a.g(cx - r * 0.5, cy - r * 0.5, cx + r * 0.5, cy + r * 0.5, ["gold-l", "gold-m"]));
	a.stroke(inner, a.s("gold-d"), Math.max(6, r * 0.07));
	if (mark) {
		const m = r * 0.4;
		const h = m * 0.866;
		a.stroke(
			`M${r1(cx)} ${r1(cy - m)}V${r1(cy + m)}M${r1(cx - h)} ${r1(cy - m / 2)}L${r1(cx + h)} ${r1(cy + m / 2)}M${r1(cx - h)} ${r1(cy + m / 2)}L${r1(cx + h)} ${r1(cy - m / 2)}`,
			a.s("gold-d"),
			Math.max(8, r * 0.11)
		);
	}
	a.stroke(
		`M${r1(cx - r * 0.8)} ${r1(cy - r * 0.26)}A${r1(r * 0.85)} ${r1(r * 0.85)} 0 0 1 ${r1(cx - r * 0.3)} ${r1(cy - r * 0.8)}`,
		a.s("hi"),
		Math.max(8, r * 0.09),
		".9"
	);
	a.stroke(d, a.s("outline"), 16);
}
// Stack of n coins seen from the side; baseY is the bottom of the lowest coin
function stack(a, cx, baseY, n, rx) {
	const ry = rx * 0.34;
	const t = 40;
	for (let i = 0; i < n; i++) {
		const y = baseY - ry - t - i * t;
		const side = `M${cx - rx} ${r1(y)}V${r1(y + t)}A${rx} ${r1(ry)} 0 0 0 ${cx + rx} ${r1(y + t)}V${r1(y)}Z`;
		a.fill(side, a.g(cx - rx, y, cx + rx, y, ["gold-m", "gold-d"]));
		a.stroke(side, a.s("outline"), 14);
		const top = a.ellipse(cx, y, rx, ry, 0);
		a.fill(top, a.g(cx - rx, y - ry, cx + rx, y + ry, ["gold-l", "gold-m"]));
		a.stroke(top, a.s("outline"), 14);
	}
}

icon("melter", (a) => {
	a.note("legs");
	a.tube("M160 430V470M352 430V470", a.s("steel-d"), 26, 60);
	a.note("barrel");
	const body = "M112 190V400Q112 440 152 440H360Q400 440 400 400V190Z";
	a.shape(body, a.g(112, 190, 400, 440, ["red-l", "red-m", "red-d"]), 18);
	a.stroke("M146 236V330", a.s("hi"), 14, ".9");
	a.note("flame window");
	a.shape(a.rrect(196, 300, 120, 110, 26), a.s("outline"), 10);
	const flame = "M256 318C290 350 292 386 256 398C220 386 222 350 256 318Z";
	a.fill(flame, a.g(256, 318, 256, 398, ["gold-l", "gold-m", "gold-d"]));
	a.note("rim and snow");
	const rim = a.ellipse(256, 190, 152, 46, 0);
	a.shape(rim, a.g(104, 150, 408, 230, ["steel-l", "steel-m", "steel-d"]), 18);
	const snow = "M150 186C150 120 200 104 236 120C256 80 330 84 340 132C380 136 384 186 362 186Z";
	a.shape(snow, a.g(150, 90, 370, 190, ["hi", "light"]), 16);
});

icon("fx_hand", (a) => {
	const p = turn(0, 256, 256, 1.14, 10, -2);
	mitten(a, p, a.g(150, 90, 380, 400, ["gold-l", "gold-m", "gold-d"]), a.s("hi"));
});

icon("fx_boost", (a) => {
	const bolt = "M306 44L132 290H246L206 468L380 216H268Z";
	round(a, bolt, a.g(150, 50, 370, 460, ["gold-l", "gold-m", "gold-d"]), 26);
	a.stroke("M262 110L196 204", a.s("hi"), 16, ".9");
});

icon("fx_range", (a) => {
	const p = turn(-35, 256, 256);
	const body = `M${p(70, 196)}L${p(442, 196)}L${p(442, 316)}L${p(70, 316)}Z`;
	round(a, body, a.g(120, 120, 400, 400, ["gold-l", "gold-m", "gold-d"]), 22);
	let ticks = "";
	[124, 190, 256, 322, 388].forEach((x, i) => {
		ticks += `M${p(x, 190)}L${p(x, i % 2 === 0 ? 254 : 232)}`;
	});
	a.stroke(ticks, a.s("outline"), 16);
});

icon("fx_width", (a) => {
	a.tube(
		"M96 256H416M176 176L96 256L176 336M336 176L416 256L336 336",
		a.g(96, 176, 416, 336, ["light", "mid", "dark"]),
		52,
		90
	);
});

icon("autosell", (a) => {
	a.note("circular arrow");
	const green = a.g(96, 96, 416, 416, ["green-l", "green-m", "green-d"]);
	const R = 164;
	const pt = (deg) => [256 + Math.cos((deg * Math.PI) / 180) * R, 256 + Math.sin((deg * Math.PI) / 180) * R];
	const s0 = pt(-140);
	const e0 = pt(160);
	const arc = `M${r1(s0[0])} ${r1(s0[1])}A${R} ${R} 0 1 1 ${r1(e0[0])} ${r1(e0[1])}`;
	// arrow head at the end of the arc (moving clockwise there)
	const dir = [-Math.sin((160 * Math.PI) / 180), Math.cos((160 * Math.PI) / 180)];
	const back = (deg) => {
		const b = (deg * Math.PI) / 180;
		const x = -dir[0] * Math.cos(b) + dir[1] * Math.sin(b);
		const y = -dir[0] * Math.sin(b) - dir[1] * Math.cos(b);
		return [e0[0] + dir[0] * 34 + x * 92, e0[1] + dir[1] * 34 + y * 92];
	};
	const tip = [e0[0] + dir[0] * 34, e0[1] + dir[1] * 34];
	const h1 = back(42);
	const h2 = back(-42);
	const head = `M${r1(h1[0])} ${r1(h1[1])}L${r1(tip[0])} ${r1(tip[1])}L${r1(h2[0])} ${r1(h2[1])}`;
	a.tube(arc + head, green, 46, 84);
	a.note("coin");
	coin(a, 256, 256, 84, true);
});

icon("vip", (a) => {
	const crown = "M96 400L72 170L180 262L256 110L332 262L440 170L416 400Z";
	round(a, crown, a.g(90, 110, 420, 410, ["gold-l", "gold-m", "gold-d"]), 30);
	a.stroke("M112 366H400", a.s("gold-d"), 26);
	a.stroke("M118 250L130 320", a.s("hi"), 14, ".9");
	a.shape(a.circle(256, 300, 34), a.g(226, 270, 286, 330, ["red-l", "red-m", "red-d"]), 14);
});

icon("cash_s", (a) => {
	coin(a, 256, 262, 170, true);
	a.sparkle(416, 92, 40);
});

icon("cash_m", (a) => {
	stack(a, 176, 440, 3, 112);
	stack(a, 346, 440, 5, 112);
	a.sparkle(150, 150, 40);
});

icon("cash_l", (a) => {
	a.note("sack");
	const sack =
		"M196 150C150 190 84 270 84 350C84 430 150 460 256 460C362 460 428 430 428 350C428 270 362 190 316 150Z";
	const neck = "M190 150L160 84Q256 120 352 84L322 150Z";
	const wood = a.g(110, 120, 410, 460, ["wood-l", "wood-m", "wood-d"]);
	union(a, [
		{ d: neck, paint: wood },
		{ d: sack, paint: wood },
	]);
	a.fill("M428 350C428 430 362 460 256 460C150 460 84 430 84 350C110 410 180 426 256 426C332 426 402 410 428 350Z", a.s("wood-d"), ".6");
	a.tube("M190 152H322", a.s("red-m"), 22, 54);
	a.stroke("M140 290Q150 240 190 206", a.s("hi"), 14, ".9");
	a.note("coin emblem");
	coin(a, 256, 316, 84, true);
	a.sparkle(424, 110, 40);
});

icon("blizzard", (a) => {
	a.note("cloud");
	const cloud = a.g(100, 80, 420, 320, ["hi", "steel-l", "steel-m"]);
	union(a, [
		{ d: a.circle(176, 220, 84), paint: cloud },
		{ d: a.circle(284, 176, 108), paint: cloud },
		{ d: a.circle(376, 236, 70), paint: cloud },
		{ d: a.rrect(110, 228, 320, 78, 38), paint: cloud },
	]);
	a.stroke("M214 130A76 76 0 0 1 268 96", a.s("hi"), 14, ".9");
	a.note("snowflakes");
	const flake = (cx, cy, m) => {
		const h = m * 0.866;
		return `M${cx} ${cy - m}V${cy + m}M${r1(cx - h)} ${r1(cy - m / 2)}L${r1(cx + h)} ${r1(cy + m / 2)}M${r1(cx - h)} ${r1(cy + m / 2)}L${r1(cx + h)} ${r1(cy - m / 2)}`;
	};
	a.tube(flake(160, 400, 40) + flake(264, 426, 44) + flake(366, 396, 40), a.g(120, 360, 400, 470, ["hi", "light", "mid"]), 20, 52);
});
