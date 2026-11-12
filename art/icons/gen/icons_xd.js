// ================================================================ batch D: finds
icon("mitten", (a) => {
	const p = turn(-14, 256, 256, 1.14, 6, -2);
	mitten(a, p, a.g(150, 90, 380, 400, ["red-l", "red-m", "red-d"]), a.s("hi"));
});

icon("keys", (a) => {
	const p = turn(40, 256, 256);
	const gold = a.g(140, 100, 380, 420, ["gold-l", "gold-m", "gold-d"]);
	const c = p.xy(256, 150);
	const ring = a.circle(c[0], c[1], 74);
	const shaft = `M${p(256, 226)}L${p(256, 440)}M${p(256, 372)}L${p(322, 372)}M${p(256, 434)}L${p(308, 434)}`;
	a.stroke(ring, a.s("outline"), 84);
	a.stroke(shaft, a.s("outline"), 80);
	a.stroke(ring, gold, 46);
	a.stroke(shaft, gold, 42);
});

icon("teddy", (a) => {
	const fur = a.g(120, 100, 400, 440, ["wood-l", "wood-m", "wood-d"]);
	union(a, [
		{ d: a.circle(140, 150, 62), paint: fur },
		{ d: a.circle(372, 150, 62), paint: fur },
		{ d: a.circle(256, 284, 166), paint: fur },
	]);
	a.fill(a.circle(140, 150, 30), a.s("wood-l"));
	a.fill(a.circle(372, 150, 30), a.s("wood-l"));
	a.note("muzzle, eyes, nose");
	a.fill(a.ellipse(256, 340, 84, 66, 0), a.s("wood-l"));
	a.fill(a.circle(194, 254, 20), a.s("outline"));
	a.fill(a.circle(318, 254, 20), a.s("outline"));
	a.fill(a.ellipse(256, 316, 30, 22, 0), a.s("outline"));
	a.stroke("M256 336V362M226 372Q256 392 286 372", a.s("outline"), 12);
});

icon("scarf", (a) => {
	const blue = a.g(90, 120, 420, 440, ["light", "mid", "dark"]);
	a.note("hanging end");
	const tail = "M286 240H392V420H286Z";
	round(a, tail, blue, 20);
	a.stroke("M300 366H378", a.s("hi"), 18);
	a.stroke("M304 440V460M339 440V460M374 440V460", a.s("outline"), 16);
	a.note("loop");
	const loop = a.rrect(84, 140, 344, 116, 58);
	a.shape(loop, blue, 18);
	a.stroke("M164 150V246M256 150V246M348 150V246", a.s("hi"), 18, ".85");
});

icon("hat", (a) => {
	a.note("crown");
	const crown = "M150 372V150Q256 112 362 150V372Z";
	const dark = a.g(150, 120, 362, 380, ["steel-m", "steel-d"]);
	round(a, crown, dark, 20);
	a.stroke("M176 300H336", a.s("red-m"), 44);
	a.stroke("M186 170V250", a.s("hi"), 14, ".7");
	a.note("brim");
	const brim = a.ellipse(256, 384, 204, 52, 0);
	a.shape(brim, a.g(52, 340, 460, 430, ["steel-m", "steel-d"]), 18);
});

icon("glasses", (a) => {
	const lens = a.g(80, 190, 430, 350, ["hi", "light", "mid"]);
	a.note("arms and bridge");
	a.tube("M70 232L40 200M442 232L472 200", a.s("steel-d"), 22, 56);
	a.tube("M222 262Q256 232 290 262", a.s("steel-d"), 22, 56);
	a.note("lenses");
	for (const x of [150, 362]) {
		const d = a.circle(x, 270, 84);
		a.fill(d, a.s("outline"));
		a.stroke(d, a.s("outline"), 36);
		a.fill(d, a.s("steel-d"));
		a.fill(a.circle(x, 270, 62), lens);
		a.stroke(`M${x - 34} ${262}A40 40 0 0 1 ${x - 6} ${234}`, a.s("hi"), 12, ".9");
	}
});

icon("alarm_clock", (a) => {
	a.note("bells and legs");
	const gold = a.g(90, 60, 420, 200, ["gold-l", "gold-m", "gold-d"]);
	a.shape(a.circle(144, 136, 62), gold, 18);
	a.shape(a.circle(368, 136, 62), gold, 18);
	a.tube("M160 420L130 462M352 420L382 462", a.s("steel-d"), 26, 62);
	a.note("case");
	a.shape(a.circle(256, 292, 168), a.g(120, 150, 390, 440, ["red-l", "red-m", "red-d"]), 18);
	a.note("face");
	a.shape(a.circle(256, 292, 118), a.g(170, 190, 340, 400, ["hi", "steel-l"]), 14);
	a.stroke("M256 292V214M256 292L312 322", a.s("outline"), 22);
	a.stroke("M128 250A136 136 0 0 1 190 172", a.s("hi"), 12, ".9");
});

icon("trumpet", (a) => {
	const p = turn(-18, 256, 256);
	const gold = a.g(60, 140, 460, 400, ["gold-l", "gold-m", "gold-d"]);
	const bell = `M${p(300, 222)}L${p(452, 128)}L${p(452, 384)}L${p(300, 290)}Z`;
	const tubeD = `M${p(64, 256)}L${p(320, 256)}`;
	const loop = `M${p(130, 256)}L${p(130, 336)}L${p(286, 336)}L${p(286, 256)}`;
	const valves = `M${p(160, 256)}L${p(160, 176)}M${p(208, 256)}L${p(208, 176)}M${p(256, 256)}L${p(256, 176)}`;
	union(a, [
		{ d: loop, paint: a.s("gold-d"), w: 24 },
		{ d: valves, paint: a.s("gold-d"), w: 26 },
		{ d: tubeD, paint: gold, w: 48 },
		{ d: bell, paint: gold },
	]);
	a.stroke(bell, gold, 14);
	a.stroke(`M${p(452, 140)}L${p(452, 372)}`, a.s("gold-d"), 22);
	a.stroke(`M${p(52, 232)}L${p(52, 280)}`, a.s("outline"), 30);
	a.stroke(`M${p(52, 236)}L${p(52, 276)}`, a.s("gold-l"), 12);
	a.stroke(`M${p(330, 236)}L${p(420, 180)}`, a.s("hi"), 14, ".9");
});

icon("snowman", (a) => {
	const snow = a.g(120, 120, 400, 480, ["hi", "steel-l", "steel-m"]);
	a.note("body and head");
	union(a, [
		{ d: a.circle(256, 366, 118), paint: snow },
		{ d: a.circle(256, 208, 88), paint: snow },
	]);
	a.note("scarf");
	a.tube("M186 278Q256 304 326 278", a.s("red-m"), 28, 60);
	a.tube("M312 286L324 344", a.s("red-m"), 26, 58);
	a.note("face and buttons");
	a.fill(a.circle(226, 196, 13), a.s("outline"));
	a.fill(a.circle(286, 196, 13), a.s("outline"));
	const carrot = "M250 216L250 240L318 232Z";
	round(a, carrot, a.s("gold-d"), 8, 8);
	a.fill(a.circle(250, 356, 13), a.s("outline"));
	a.fill(a.circle(250, 410, 13), a.s("outline"));
	a.note("hat");
	const hat = "M186 136L256 28L326 136Z";
	round(a, hat, a.g(186, 28, 326, 136, ["red-l", "red-m", "red-d"]), 22);
	a.shape(a.circle(256, 30, 20), a.s("hi"), 12);
});
