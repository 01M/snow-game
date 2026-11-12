// Icon batch A generator: writes art/icons/svg/<name>.svg in the style of the existing nine icons.
// Rules copied from art/icons/svg: 512 viewBox, palette classes on gradient stops, navy #1B2A5C outline,
// paths only, no filters/masks/clips, transparent background, ids prefixed with the icon name.
const fs = require("fs");
const path = require("path");
const OUT = process.argv[2];

const STYLE = `      .c-outline{stop-color:#1B2A5C}.c-light{stop-color:#BFEFFF}.c-mid{stop-color:#5CC8FF}.c-dark{stop-color:#2A7FD6}.c-hi{stop-color:#FFFFFF}
      .c-gold-l{stop-color:#FFF2A8}.c-gold-m{stop-color:#FFC83D}.c-gold-d{stop-color:#E08A00}
      .c-green-l{stop-color:#C9F7A5}.c-green-m{stop-color:#5FD35F}.c-green-d{stop-color:#2E9E44}
      .c-red-l{stop-color:#FFB3A8}.c-red-m{stop-color:#FF6B5C}.c-red-d{stop-color:#C93B3B}
      .c-wood-l{stop-color:#E8B98A}.c-wood-m{stop-color:#B97A4A}.c-wood-d{stop-color:#7A4A2A}
      .c-steel-l{stop-color:#E3EAF2}.c-steel-m{stop-color:#A9B8CC}.c-steel-d{stop-color:#6B7C96}`;

const r1 = (n) => Math.round(n * 10) / 10;

function icon(name, build) {
	const defs = [];
	const body = [];
	const solids = {};
	let gn = 0;
	const api = {
		// solid colour by palette class name ("outline", "hi", "gold-d", ...)
		s(cls) {
			if (!solids[cls]) {
				solids[cls] = `${name}-s-${cls}`;
				defs.push(
					`    <linearGradient id="${solids[cls]}" gradientUnits="userSpaceOnUse"><stop class="c-${cls}"/></linearGradient>`
				);
			}
			return `url(#${solids[cls]})`;
		},
		// linear gradient in user space
		g(x1, y1, x2, y2, classes) {
			gn += 1;
			const id = `${name}-g${gn}`;
			const stops = classes
				.map((c, i) => {
					const off = i === 0 ? "" : ` offset="${r1(i / (classes.length - 1))}"`;
					return `<stop${off} class="c-${c}"/>`;
				})
				.join("");
			defs.push(
				`    <linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops}</linearGradient>`
			);
			return `url(#${id})`;
		},
		note(text) {
			body.push(`  <!-- ${text} -->`);
		},
		fill(d, paint, opacity) {
			body.push(`  <path fill="${paint}"${opacity ? ` opacity="${opacity}"` : ""} d="${d}"/>`);
		},
		stroke(d, paint, width, opacity) {
			body.push(
				`  <path stroke="${paint}" stroke-width="${width}" stroke-linejoin="round" stroke-linecap="round"${opacity ? ` opacity="${opacity}"` : ""} d="${d}"/>`
			);
		},
		// filled shape with the navy outline on top
		shape(d, paint, width) {
			api.fill(d, paint);
			api.stroke(d, api.s("outline"), width || 16);
		},
		// tube: navy line with a coloured line inside
		tube(d, paint, inner, outer) {
			api.stroke(d, api.s("outline"), outer);
			api.stroke(d, paint, inner);
		},
		circle(cx, cy, r) {
			return `M${r1(cx - r)} ${r1(cy)}a${r} ${r} 0 1 0 ${r1(2 * r)} 0a${r} ${r} 0 1 0 ${r1(-2 * r)} 0Z`;
		},
		rrect(x, y, w, h, r) {
			return `M${x + r} ${y}H${x + w - r}Q${x + w} ${y} ${x + w} ${y + r}V${y + h - r}Q${x + w} ${y + h} ${x + w - r} ${y + h}H${x + r}Q${x} ${y + h} ${x} ${y + h - r}V${y + r}Q${x} ${y} ${x + r} ${y}Z`;
		},
		// ellipse rotated by deg, as four cubic arcs
		ellipse(cx, cy, rx, ry, deg) {
			const a = (deg * Math.PI) / 180;
			const k = 0.5523;
			const pt = (x, y) => {
				const X = cx + x * Math.cos(a) - y * Math.sin(a);
				const Y = cy + x * Math.sin(a) + y * Math.cos(a);
				return `${r1(X)} ${r1(Y)}`;
			};
			return (
				`M${pt(rx, 0)}C${pt(rx, ry * k)} ${pt(rx * k, ry)} ${pt(0, ry)}` +
				`C${pt(-rx * k, ry)} ${pt(-rx, ry * k)} ${pt(-rx, 0)}` +
				`C${pt(-rx, -ry * k)} ${pt(-rx * k, -ry)} ${pt(0, -ry)}` +
				`C${pt(rx * k, -ry)} ${pt(rx, -ry * k)} ${pt(rx, 0)}Z`
			);
		},
		sparkle(cx, cy, r) {
			const q = r * 0.175;
			const d = `M${cx} ${cy - r}Q${r1(cx + q)} ${r1(cy - q)} ${cx + r} ${cy} ${r1(cx + q)} ${r1(cy + q)} ${cx} ${cy + r} ${r1(cx - q)} ${r1(cy + q)} ${cx - r} ${cy} ${r1(cx - q)} ${r1(cy - q)} ${cx} ${cy - r}Z`;
			api.fill(d, api.s("hi"));
			api.stroke(d, api.s("outline"), 10);
		},
	};
	build(api);
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" fill="none">
  <defs>
    <style>
${STYLE}
    </style>
${defs.join("\n")}
  </defs>
${body.join("\n")}
</svg>
`;
	fs.writeFileSync(path.join(OUT, name + ".svg"), svg);
}

// ---------------------------------------------------------------- shop: cart with a gold coin
icon("shop", (a) => {
	a.note("handle and frame");
	a.tube("M40 116H112L150 300", a.s("steel-l"), 24, 58);
	a.tube("M164 318L182 376H400", a.s("steel-l"), 24, 58);
	a.note("basket");
	const basket = "M122 170H430L394 318H160Z";
	a.shape(basket, a.g(140, 170, 400, 318, ["light", "mid", "dark"]), 18);
	a.stroke("M232 196L240 292M322 196L314 292", a.s("dark"), 12);
	a.stroke("M152 194H212", a.s("hi"), 12, ".9");
	a.note("wheels");
	for (const x of [204, 376]) {
		a.shape(a.circle(x, 436, 38), a.s("steel-m"), 18);
		a.fill(a.circle(x, 436, 12), a.s("outline"));
	}
	a.note("coin");
	a.shape(a.circle(404, 122, 66), a.g(358, 76, 450, 168, ["gold-l", "gold-m", "gold-d"]), 18);
	a.stroke(a.circle(404, 122, 38), a.s("gold-d"), 10);
	a.stroke("M356 100A52 52 0 0 1 384 72", a.s("hi"), 10, ".9");
});

// ---------------------------------------------------------------- invite: two friends and a plus
icon("invite", (a) => {
	a.note("back friend");
	const backPaint = a.g(90, 120, 270, 400, ["mid", "dark"]);
	a.shape("M62 404C62 310 110 262 172 262C234 262 282 310 282 404Z", backPaint, 18);
	a.shape(a.circle(172, 176, 58), backPaint, 18);
	a.note("front friend");
	const frontPaint = a.g(190, 130, 410, 450, ["light", "mid", "dark"]);
	a.shape("M160 452C160 340 220 288 296 288C372 288 432 340 432 452Z", frontPaint, 18);
	a.shape(a.circle(296, 196, 70), frontPaint, 18);
	a.stroke("M246 176A54 54 0 0 1 276 146", a.s("hi"), 12, ".9");
	a.note("plus badge");
	a.shape(a.circle(416, 104, 64), a.g(370, 58, 462, 150, ["green-l", "green-m", "green-d"]), 18);
	a.stroke("M416 72V136M384 104H448", a.s("hi"), 20);
});

// ---------------------------------------------------------------- upgrade: green chevrons on a blue badge
icon("upgrade", (a) => {
	a.note("badge");
	const badge = a.rrect(56, 56, 400, 400, 104);
	a.fill(badge, a.g(96, 56, 416, 456, ["mid", "dark"]));
	a.fill("M56 300V352Q56 456 160 456H352Q456 456 456 352V300Q456 404 352 404H160Q56 404 56 300Z", a.s("dark"), ".6");
	a.stroke("M104 168Q104 104 168 104H232", a.s("hi"), 14, ".9");
	a.stroke(badge, a.s("outline"), 18);
	a.note("chevrons");
	const green = a.g(256, 130, 256, 400, ["green-l", "green-m", "green-d"]);
	a.tube("M152 378L256 278L360 378", green, 46, 82);
	a.tube("M152 262L256 162L360 262", green, 46, 82);
});

// ---------------------------------------------------------------- play: rounded green triangle
icon("play", (a) => {
	const tri = "M158 112L400 256L158 400Z";
	a.note("outline under the rounded triangle");
	a.fill(tri, a.s("outline"));
	a.stroke(tri, a.s("outline"), 108);
	a.note("triangle");
	const green = a.g(140, 100, 330, 410, ["green-l", "green-m", "green-d"]);
	a.fill(tri, green);
	a.stroke(tri, green, 72);
	a.fill("M158 400L400 256L400 256L300 256L158 340Z", a.s("green-d"), ".55");
	a.stroke("M142 128V214", a.s("hi"), 18, ".9");
});

// ---------------------------------------------------------------- music: gold beamed note
icon("music", (a) => {
	const head1 = a.ellipse(146, 392, 66, 50, -18);
	const head2 = a.ellipse(350, 352, 66, 50, -18);
	const beam = "M196 126L428 82V150L196 194Z";
	const stems = "M210 384V152M414 344V112";
	a.note("outline under the whole note");
	for (const d of [head1, head2, beam]) {
		a.fill(d, a.s("outline"));
		a.stroke(d, a.s("outline"), 36);
	}
	a.stroke(stems, a.s("outline"), 64);
	a.note("note");
	const gold = a.g(120, 90, 400, 430, ["gold-l", "gold-m", "gold-d"]);
	a.fill(head1, gold);
	a.fill(head2, gold);
	a.fill(beam, gold);
	a.stroke(stems, gold, 28);
	a.fill("M196 164L428 120V150L196 194Z", a.s("gold-d"), ".6");
	a.stroke("M104 380A40 30 -18 0 1 136 356", a.s("hi"), 11, ".9");
	a.stroke("M308 340A40 30 -18 0 1 340 316", a.s("hi"), 11, ".9");
});

// ---------------------------------------------------------------- snow: ice-blue snowflake
icon("snow", (a) => {
	const cx = 256;
	const cy = 256;
	const arm = 190;
	const at = 0.6;
	const twig = 60;
	let arms = "";
	let twigs = "";
	for (let i = 0; i < 6; i++) {
		const ang = ((i * 60 - 90) * Math.PI) / 180;
		const ex = cx + Math.cos(ang) * arm;
		const ey = cy + Math.sin(ang) * arm;
		if (i < 3) {
			arms += `M${r1(2 * cx - ex)} ${r1(2 * cy - ey)}L${r1(ex)} ${r1(ey)}`;
		}
		const bx = cx + Math.cos(ang) * arm * at;
		const by = cy + Math.sin(ang) * arm * at;
		for (const side of [-1, 1]) {
			const ta = ang + (side * 50 * Math.PI) / 180;
			twigs += `M${r1(bx)} ${r1(by)}L${r1(bx + Math.cos(ta) * twig)} ${r1(by + Math.sin(ta) * twig)}`;
		}
	}
	a.note("outline");
	a.stroke(arms, a.s("outline"), 90);
	a.stroke(twigs, a.s("outline"), 78);
	a.note("ice");
	const ice = a.g(120, 80, 400, 440, ["hi", "light", "mid"]);
	a.stroke(arms, ice, 56);
	a.stroke(twigs, ice, 44);
	a.fill(a.circle(cx, cy, 20), a.s("hi"));
});

// ---------------------------------------------------------------- clock: stopwatch
icon("clock", (a) => {
	a.note("crown and side button");
	a.shape(a.rrect(220, 40, 72, 80, 20), a.g(220, 40, 292, 120, ["gold-l", "gold-m", "gold-d"]), 18);
	a.tube("M388 150L412 126", a.s("gold-m"), 22, 58);
	a.note("case");
	a.shape(a.circle(256, 292, 172), a.g(130, 150, 380, 440, ["mid", "dark"]), 18);
	a.fill("M418 234A172 172 0 0 1 198 454A232 232 0 0 0 418 234Z", a.s("dark"), ".6");
	a.note("face");
	a.shape(a.circle(256, 292, 122), a.g(170, 190, 340, 400, ["hi", "steel-l"]), 14);
	a.stroke("M256 190V212M256 372V394M154 292H176M336 292H358", a.s("steel-d"), 14);
	a.note("hand");
	a.tube("M256 292L318 222", a.s("red-m"), 20, 44);
	a.fill(a.circle(256, 292, 20), a.s("outline"));
	a.stroke("M124 250A140 140 0 0 1 190 168", a.s("hi"), 12, ".9");
});

// ---------------------------------------------------------------- journal: wooden clipboard
icon("journal", (a) => {
	a.note("board");
	const board = a.rrect(88, 84, 336, 384, 44);
	a.fill(board, a.g(110, 84, 400, 468, ["wood-l", "wood-m"]));
	a.fill("M88 404V424Q88 468 132 468H380Q424 468 424 424V404Q424 448 380 448H132Q88 448 88 404Z", a.s("wood-d"), ".6");
	a.stroke(board, a.s("outline"), 18);
	a.note("paper");
	a.shape(a.rrect(132, 148, 248, 276, 16), a.g(140, 148, 370, 424, ["hi", "steel-l"]), 14);
	a.note("check line and text lines");
	a.tube("M164 262L204 300L262 226", a.g(164, 226, 262, 300, ["green-m", "green-d"]), 26, 54);
	a.stroke("M298 264H346", a.s("steel-m"), 20);
	a.stroke("M170 352H346M170 396H290", a.s("steel-m"), 20);
	a.note("clip");
	a.shape(a.rrect(176, 44, 160, 92, 28), a.g(176, 44, 336, 136, ["steel-l", "steel-m", "steel-d"]), 18);
	a.stroke("M206 76H306", a.s("hi"), 12, ".9");
});
