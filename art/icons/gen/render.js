// Renders svg -> png512, png256 and a contact sheet.
// Usage: node render.js <svgDir> <outDir> <sheetFile> <name,name,...>
const fs = require("fs");
const path = require("path");
const { Resvg } = require("@resvg/resvg-js");
const [svgDir, outDir, sheetFile, list] = process.argv.slice(2);
const NAMES = list.split(",");
function png(svg, width) {
	return new Resvg(svg, { fitTo: { mode: "width", value: width } }).render().asPng();
}
for (const size of [512, 256]) {
	fs.mkdirSync(path.join(outDir, "png" + size), { recursive: true });
	for (const n of NAMES) {
		const svg = fs.readFileSync(path.join(svgDir, n + ".svg"), "utf8");
		fs.writeFileSync(path.join(outDir, "png" + size, n + ".png"), png(svg, size));
	}
}
function inner(n) {
	const svg = fs.readFileSync(path.join(svgDir, n + ".svg"), "utf8");
	return svg.replace(/^<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "");
}
function sheet(sizes, cell, file) {
	const pad = 16;
	const W = pad * 2 + NAMES.length * cell;
	const rowH = sizes.reduce((s, z) => s + z + pad, pad);
	const H = rowH * 2;
	let body = `<rect x="0" y="0" width="${W}" height="${rowH}" fill="#1B2A5C"/><rect x="0" y="${rowH}" width="${W}" height="${rowH}" fill="#FFFFFF"/>`;
	for (let bg = 0; bg < 2; bg++) {
		let y = bg * rowH + pad;
		for (const z of sizes) {
			NAMES.forEach((n, i) => {
				const x = pad + i * cell + Math.round((cell - z) / 2);
				body += `<svg x="${x}" y="${y}" width="${z}" height="${z}" viewBox="0 0 512 512" fill="none">${inner(n)}</svg>`;
			});
			y += z + pad;
		}
	}
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${body}</svg>`;
	fs.writeFileSync(path.join(outDir, file), new Resvg(svg).render().asPng());
}
sheet([32, 64], 96, sheetFile);
sheet([150], 162, "preview_" + sheetFile);
