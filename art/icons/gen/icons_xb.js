// ================================================================ batch B: system glyphs
// Filled shape with rounded corners (stroke of the same paint) and the navy outline around it
function round(a, d, paint, r, edge) {
	const e = edge || 18;
	a.fill(d, a.s("outline"));
	a.stroke(d, a.s("outline"), r + 2 * e);
	a.fill(d, paint);
	a.stroke(d, paint, r);
}
function poly(pts) {
	return "M" + pts.map((q) => `${r1(q[0])} ${r1(q[1])}`).join("L") + "Z";
}

icon("close", (a) => {
	a.tube("M146 146L366 366M366 146L146 366", a.g(140, 140, 370, 370, ["hi", "steel-l"]), 62, 100);
});

icon("check", (a) => {
	a.tube("M112 270L214 370L400 152", a.g(110, 150, 400, 380, ["green-l", "green-m", "green-d"]), 64, 102);
});

icon("lock", (a) => {
	a.note("shackle");
	a.tube("M170 240V176A86 86 0 0 1 342 176V240", a.g(170, 90, 342, 240, ["hi", "steel-l", "steel-m"]), 36, 74);
	a.note("body");
	const body = a.rrect(108, 216, 296, 236, 52);
	a.fill(body, a.g(120, 216, 392, 452, ["gold-l", "gold-m", "gold-d"]));
	a.fill("M108 380V400Q108 452 160 452H352Q404 452 404 400V380Q404 426 352 426H160Q108 426 108 380Z", a.s("gold-d"), ".6");
	a.stroke("M150 262H232", a.s("hi"), 14, ".9");
	a.stroke(body, a.s("outline"), 18);
	a.note("keyhole");
	a.fill(a.circle(256, 316, 28), a.s("outline"));
	a.stroke("M256 322V378", a.s("outline"), 24);
});

icon("star", (a) => {
	const pts = [];
	for (let i = 0; i < 10; i++) {
		const rad = i % 2 === 0 ? 186 : 86;
		const ang = ((i * 36 - 90) * Math.PI) / 180;
		pts.push([256 + Math.cos(ang) * rad, 272 + Math.sin(ang) * rad]);
	}
	const d = poly(pts);
	round(a, d, a.g(120, 90, 390, 450, ["gold-l", "gold-m", "gold-d"]), 34);
	a.fill(poly([pts[4], pts[5], pts[6], [256, 330], pts[3]]), a.s("gold-d"), ".45");
	a.stroke("M206 196L222 150", a.s("hi"), 16, ".9");
});

icon("question", (a) => {
	const badge = a.circle(256, 256, 190);
	a.fill(badge, a.g(120, 80, 390, 440, ["mid", "dark"]));
	a.fill("M434 190A190 190 0 0 1 190 434A256 256 0 0 0 434 190Z", a.s("dark"), ".6");
	a.stroke("M110 206A154 154 0 0 1 190 112", a.s("hi"), 14, ".9");
	a.stroke(badge, a.s("outline"), 18);
	a.stroke("M194 208A62 62 0 1 1 288 262Q256 282 256 314", a.s("hi"), 44);
	a.fill(a.circle(256, 384, 28), a.s("hi"));
});

icon("robux", (a) => {
	const hex = (r, turnDeg) => {
		const pts = [];
		for (let i = 0; i < 6; i++) {
			const ang = ((i * 60 - 90 + turnDeg) * Math.PI) / 180;
			pts.push([256 + Math.cos(ang) * r, 256 + Math.sin(ang) * r]);
		}
		return poly(pts);
	};
	round(a, hex(176, 0), a.g(110, 90, 400, 430, ["hi", "steel-l", "steel-m"]), 30);
	a.stroke(hex(112, 0), a.s("steel-d"), 26);
	a.fill(a.rrect(220, 220, 72, 72, 10), a.s("outline"));
});

icon("gear", (a) => {
	let teeth = "";
	for (let i = 0; i < 8; i++) {
		const ang = (i * 45 * Math.PI) / 180;
		teeth += `M${r1(256 + Math.cos(ang) * 120)} ${r1(256 + Math.sin(ang) * 120)}L${r1(256 + Math.cos(ang) * 184)} ${r1(256 + Math.sin(ang) * 184)}`;
	}
	const steel = a.g(110, 90, 400, 430, ["hi", "steel-l", "steel-m"]);
	union(a, [
		{ d: teeth, paint: steel, w: 60 },
		{ d: a.circle(256, 256, 138), paint: steel },
	]);
	a.fill("M384 204A138 138 0 0 1 204 384A190 190 0 0 0 384 204Z", a.s("steel-m"), ".7");
	a.fill(a.circle(256, 256, 58), a.s("outline"));
	a.fill(a.circle(256, 256, 30), a.s("steel-d"));
});

icon("map", (a) => {
	const left = "M60 150L186 104V394L60 440Z";
	const mid = "M186 104L326 150V440L186 394Z";
	const right = "M326 150L452 104V394L326 440Z";
	const whole = "M60 150L186 104L326 150L452 104V394L326 440L186 394L60 440Z";
	a.fill(whole, a.s("outline"));
	a.stroke(whole, a.s("outline"), 36);
	a.fill(left, a.g(60, 104, 186, 440, ["green-l", "green-m"]));
	a.fill(mid, a.g(186, 104, 326, 440, ["green-m", "green-d"]));
	a.fill(right, a.g(326, 104, 452, 440, ["green-l", "green-m"]));
	a.stroke("M96 330Q150 280 186 310Q250 360 326 300Q380 260 420 280", a.s("mid"), 22);
	a.note("pin");
	const pin = "M296 300L250 214A52 52 0 1 1 342 214Z";
	round(a, pin, a.g(244, 130, 348, 300, ["red-l", "red-m", "red-d"]), 10, 14);
	a.fill(a.circle(296, 190, 18), a.s("hi"));
});

icon("tasks", (a) => {
	a.note("pole");
	a.tube("M142 452V76", a.g(120, 76, 164, 452, ["hi", "steel-l", "steel-m"]), 26, 62);
	a.note("flag");
	const flag = "M172 96H420L366 184L420 272H172Z";
	round(a, flag, a.g(172, 96, 400, 272, ["green-l", "green-m", "green-d"]), 16);
	a.stroke("M196 124H286", a.s("hi"), 14, ".9");
	a.note("base");
	a.tube("M92 452H192", a.s("steel-d"), 24, 60);
});

icon("tips", (a) => {
	a.note("rays");
	let rays = "";
	for (const deg of [-150, -90, -30]) {
		const ang = (deg * Math.PI) / 180;
		rays += `M${r1(256 + Math.cos(ang) * 176)} ${r1(246 + Math.sin(ang) * 176)}L${r1(256 + Math.cos(ang) * 214)} ${r1(246 + Math.sin(ang) * 214)}`;
	}
	a.tube(rays, a.s("gold-m"), 20, 52);
	a.note("bulb");
	const gold = a.g(160, 130, 350, 380, ["gold-l", "gold-m", "gold-d"]);
	union(a, [
		{ d: a.circle(256, 246, 124), paint: gold },
		{ d: "M204 330H308V392H204Z", paint: gold },
	]);
	a.stroke("M176 222A84 84 0 0 1 226 166", a.s("hi"), 14, ".9");
	a.stroke("M226 262L256 300L286 262", a.s("gold-d"), 14);
	a.note("base");
	a.shape(a.rrect(196, 384, 120, 72, 22), a.g(196, 384, 316, 456, ["steel-l", "steel-m", "steel-d"]), 18);
	a.stroke("M216 420H296", a.s("steel-d"), 12);
});

icon("leave", (a) => {
	a.note("door frame");
	const frame = a.rrect(84, 60, 232, 400, 30);
	a.shape(frame, a.g(84, 60, 316, 460, ["wood-l", "wood-m"]), 18);
	a.fill("M128 104H272V460H128Z", a.s("wood-d"));
	a.stroke("M128 460V104H272V460", a.s("outline"), 14);
	a.fill(a.circle(160, 280, 16), a.s("gold-m"));
	a.note("arrow out");
	a.tube("M214 280H436M366 204L442 280L366 356", a.g(214, 204, 442, 356, ["green-l", "green-m", "green-d"]), 50, 88);
});
