// Shared visual theme + slide-building helpers for the Oracle Performance
// Tuning course deck series (Days 1-6). One consistent system across all
// six decks: "Ocean Gradient" palette, deep-navy title/section slides,
// white content slides, box-and-arrow shape diagrams built natively
// (no external icons/images), amber tag for LIVE DEMO, teal tag for
// PRODUCTION SCENARIO. Motif: numbered/lettered circles + soft rounded
// cards. No accent stripes, no color bars, per house style rules.

const PptxGenJS = require("pptxgenjs");

const COLOR = {
  navy: "0B2545",      // darkest background (title/section slides)
  deepBlue: "065A82",  // primary
  teal: "1C7293",      // secondary / PRODUCTION SCENARIO tag
  midnight: "21295C",  // accent structural color (boxes, borders)
  ice: "CFE8F3",       // light text on dark bg
  white: "FFFFFF",
  offwhite: "F4F8FB",  // very light panel fill on white slides
  ink: "17324A",       // body text on white
  muted: "5B7286",     // secondary/muted text
  amber: "C97A1A",     // LIVE DEMO tag + warm accent
  amberLight: "FBEBD5",
  tealLight: "DCEEF2",
  redFalse: "B23A2E",  // false-lead "ruled out" callouts
  greenGood: "2C6E49", // validated / correct outcome
  cardBorder: "D8E3EA",
};

const FONT_HEAD = "Cambria";
const FONT_BODY = "Calibri";

function xmlSafe(s) {
  return String(s).replace(/&/g, "and");
}

function newDeck(dayLabel) {
  const pres = new PptxGenJS();
  pres.layout = "LAYOUT_WIDE"; // 13.3 x 7.5 in
  pres.author = "Amit Pawar";
  pres.company = "Oracle Database Performance Tuning and Troubleshooting";
  pres.subject = xmlSafe(dayLabel);
  pres.title = xmlSafe(dayLabel);
  return pres;
}

function footer(slide, dayNum, slideLabel) {
  slide.addText(
    `Oracle Performance Tuning & Troubleshooting  •  Day ${dayNum}`,
    {
      x: 0.5, y: 7.12, w: 8.0, h: 0.3,
      fontFace: FONT_BODY, fontSize: 9, color: COLOR.muted, isTextBox: true, margin: 0,
    }
  );
  slide.addText(slideLabel || "", {
    x: 10.3, y: 7.12, w: 2.5, h: 0.3, align: "right",
    fontFace: FONT_BODY, fontSize: 9, color: COLOR.muted, isTextBox: true, margin: 0,
  });
}

// ---------- Title slide (dark, full-bleed) ----------
function addTitleSlide(pres, { dayNum, title, subtitle, instructor = "Amit Pawar" }) {
  const slide = pres.addSlide();
  slide.background = { color: COLOR.navy };

  slide.addShape(pres.ShapeType.rect, {
    x: 0, y: 0, w: 13.33, h: 7.5, fill: { color: COLOR.navy }, line: { type: "none" },
  });
  // Subtle depth: one large soft translucent circle, lower-right, no stripes.
  slide.addShape(pres.ShapeType.ellipse, {
    x: 9.6, y: 3.6, w: 6.5, h: 6.5, fill: { color: COLOR.deepBlue, transparency: 70 }, line: { type: "none" },
  });

  slide.addText(`DAY ${dayNum}`, {
    x: 0.9, y: 1.55, w: 4, h: 0.5, fontFace: FONT_BODY, fontSize: 15, bold: true,
    color: COLOR.amber, charSpacing: 3, isTextBox: true, margin: 0,
  });
  slide.addText(title, {
    x: 0.9, y: 2.05, w: 11.2, h: 2.2, fontFace: FONT_HEAD, fontSize: 40, bold: true,
    color: COLOR.white, isTextBox: true, margin: 0, valign: "top", lineSpacingMultiple: 1.05,
  });
  if (subtitle) {
    slide.addText(subtitle, {
      x: 0.9, y: 4.15, w: 10.5, h: 0.8, fontFace: FONT_BODY, italic: true, fontSize: 18,
      color: COLOR.ice, isTextBox: true, margin: 0,
    });
  }
  slide.addText("Oracle Database Performance Tuning & Troubleshooting", {
    x: 0.9, y: 6.55, w: 8, h: 0.4, fontFace: FONT_BODY, fontSize: 12,
    color: COLOR.ice, isTextBox: true, margin: 0,
  });
  slide.addText(`Instructor: ${instructor}`, {
    x: 0.9, y: 6.9, w: 8, h: 0.4, fontFace: FONT_BODY, fontSize: 12,
    color: COLOR.muted, isTextBox: true, margin: 0,
  });
  return slide;
}

// ---------- Tag chip (LIVE DEMO / PRODUCTION SCENARIO) ----------
function addTag(slide, pres, kind) {
  if (!kind || kind === "none") return;
  const isDemo = kind === "demo";
  const label = isDemo ? "LIVE DEMO" : "PRODUCTION SCENARIO";
  const fill = isDemo ? COLOR.amberLight : COLOR.tealLight;
  const txt = isDemo ? COLOR.amber : COLOR.teal;
  const w = isDemo ? 1.7 : 2.75;
  slide.addShape(pres.ShapeType.roundRect, {
    x: 10.05, y: 0.42, w, h: 0.42, rectRadius: 0.08,
    fill: { color: fill }, line: { type: "none" },
  });
  slide.addText(label, {
    x: 10.05, y: 0.42, w, h: 0.42, align: "center", valign: "middle",
    fontFace: FONT_BODY, fontSize: 11, bold: true, color: txt, isTextBox: true, margin: 0, charSpacing: 1,
  });
}

// ---------- Generic content slide shell ----------
function baseContentSlide(pres, dayNum, { title, kicker, tag, slideLabel }) {
  const slide = pres.addSlide();
  slide.background = { color: COLOR.white };
  if (kicker) {
    slide.addText(kicker.toUpperCase(), {
      x: 0.6, y: 0.35, w: 9, h: 0.35, fontFace: FONT_BODY, fontSize: 12, bold: true,
      color: COLOR.teal, charSpacing: 2, isTextBox: true, margin: 0,
    });
  }
  slide.addText(title, {
    x: 0.6, y: kicker ? 0.68 : 0.42, w: 9.2, h: 0.9, fontFace: FONT_HEAD, fontSize: 27, bold: true,
    color: COLOR.navy, isTextBox: true, margin: 0, valign: "top",
  });
  addTag(slide, pres, tag);
  footer(slide, dayNum, slideLabel);
  return slide;
}

function addBullets(slide, items, { x, y, w, h, fontSize = 14 } = {}) {
  const paras = items.map((t, i) => ({
    text: t,
    options: {
      bullet: { code: "25AA", indent: 18 },
      color: COLOR.ink, fontFace: FONT_BODY, fontSize,
      breakLine: i < items.length - 1, paraSpaceAfter: 10,
    },
  }));
  slide.addText(paras, { x, y, w, h, isTextBox: true, margin: 0, valign: "top" });
}

function addKeyTakeaway(slide, pres, dayNum, text) {
  const y = 6.35;
  slide.addShape(pres.ShapeType.roundRect, {
    x: 0.6, y, w: 12.1, h: 0.62, rectRadius: 0.06,
    fill: { color: COLOR.offwhite }, line: { color: COLOR.cardBorder, width: 0.75 },
  });
  slide.addText([
    { text: "KEY TAKEAWAY   ", options: { bold: true, color: COLOR.teal, fontSize: 11, charSpacing: 1 } },
    { text: text, options: { color: COLOR.ink, fontSize: 12.5, italic: true } },
  ], { x: 0.85, y, w: 11.6, h: 0.62, valign: "middle", isTextBox: true, margin: 0, fontFace: FONT_BODY });
}

// ---------- Diagram: horizontal box chain with arrows ----------
// items: [{label, caption}], optional highlightIndex to color one box amber
function drawBoxChain(slide, pres, items, { x = 0.6, y = 2.3, totalW = 12.1, boxH = 0.9, highlightIndex = -1, small = false } = {}) {
  const n = items.length;
  const gap = 0.35;
  const boxW = (totalW - gap * (n - 1)) / n;
  items.forEach((item, i) => {
    const bx = x + i * (boxW + gap);
    const fill = i === highlightIndex ? COLOR.amberLight : COLOR.offwhite;
    const lineColor = i === highlightIndex ? COLOR.amber : COLOR.midnight;
    slide.addShape(pres.ShapeType.roundRect, {
      x: bx, y, w: boxW, h: boxH, rectRadius: 0.06,
      fill: { color: fill }, line: { color: lineColor, width: 1.25 },
    });
    slide.addText(item.label, {
      x: bx + 0.05, y: y + 0.06, w: boxW - 0.1, h: boxH - 0.12, align: "center", valign: "middle",
      fontFace: FONT_BODY, fontSize: small ? 10.5 : 12, bold: true, color: COLOR.navy,
      isTextBox: true, margin: 0, autoFit: true,
    });
    if (item.caption) {
      slide.addText(item.caption, {
        x: bx - 0.1, y: y + boxH + 0.08, w: boxW + 0.2, h: 0.55, align: "center", valign: "top",
        fontFace: FONT_BODY, fontSize: 9.5, color: COLOR.muted, isTextBox: true, margin: 0,
      });
    }
    if (i < n - 1) {
      slide.addText("→", {
        x: bx + boxW, y: y - 0.04, w: gap, h: boxH, align: "center", valign: "middle",
        fontFace: FONT_BODY, fontSize: 20, bold: true, color: COLOR.midnight, isTextBox: true, margin: 0,
      });
    }
  });
}

// ---------- Diagram: two boxes side by side (compare/contrast) ----------
function drawTwoBox(slide, pres, { leftTitle, leftLines, rightTitle, rightLines, x = 0.6, y = 2.15, w = 12.1, h = 3.6, leftColor = COLOR.deepBlue, rightColor = COLOR.teal }) {
  const colW = (w - 0.4) / 2;
  [ [leftTitle, leftLines, x, leftColor], [rightTitle, rightLines, x + colW + 0.4, rightColor] ]
    .forEach(([hd, lines, bx, color]) => {
      slide.addShape(pres.ShapeType.roundRect, {
        x: bx, y, w: colW, h, rectRadius: 0.08,
        fill: { color: COLOR.offwhite }, line: { color: COLOR.cardBorder, width: 1 },
      });
      slide.addShape(pres.ShapeType.roundRect, {
        x: bx, y, w: colW, h: 0.55, rectRadius: 0.08,
        fill: { color }, line: { type: "none" },
      });
      slide.addText(hd, {
        x: bx, y, w: colW, h: 0.55, align: "center", valign: "middle",
        fontFace: FONT_BODY, fontSize: 14, bold: true, color: COLOR.white, isTextBox: true, margin: 0,
      });
      const paras = lines.map((t, i) => ({
        text: t,
        options: { bullet: { code: "2013", indent: 14 }, color: COLOR.ink, fontFace: FONT_BODY, fontSize: 12.5, breakLine: i < lines.length - 1, paraSpaceAfter: 8 },
      }));
      slide.addText(paras, { x: bx + 0.25, y: y + 0.75, w: colW - 0.5, h: h - 1.0, isTextBox: true, margin: 0, valign: "top" });
    });
}

// ---------- Diagram: big stat comparison (e.g. 4 min vs 45 min) ----------
function drawStatCompare(slide, pres, { leftStat, leftLabel, rightStat, rightLabel, x = 1.3, y = 2.6, w = 10.7 }) {
  const colW = (w - 1.2) / 2;
  [[leftStat, leftLabel, x, COLOR.greenGood], [rightStat, rightLabel, x + colW + 1.2, COLOR.redFalse]].forEach(([stat, label, bx, color]) => {
    slide.addShape(pres.ShapeType.roundRect, { x: bx, y, w: colW, h: 2.4, rectRadius: 0.1, fill: { color: COLOR.offwhite }, line: { color, width: 1.5 } });
    slide.addText(stat, { x: bx, y: y + 0.25, w: colW, h: 1.3, align: "center", fontFace: FONT_HEAD, fontSize: 54, bold: true, color, isTextBox: true, margin: 0 });
    slide.addText(label, { x: bx, y: y + 1.65, w: colW, h: 0.6, align: "center", fontFace: FONT_BODY, fontSize: 13, color: COLOR.ink, isTextBox: true, margin: 0 });
  });
  slide.addText("VS", { x: x + colW, y: y + 0.85, w: 1.2, h: 0.7, align: "center", valign: "middle", fontFace: FONT_HEAD, fontSize: 20, bold: true, color: COLOR.muted, isTextBox: true, margin: 0 });
}

// ---------- Numbered/lettered circle row (motif) ----------
function drawCircleSteps(slide, pres, labels, { x = 0.6, y = 2.3, w = 12.1, d = 0.55 } = {}) {
  const n = labels.length;
  const gap = (w - n * d) / (n - 1);
  labels.forEach((t, i) => {
    const cx = x + i * (d + gap);
    slide.addShape(pres.ShapeType.ellipse, { x: cx, y, w: d, h: d, fill: { color: COLOR.deepBlue }, line: { type: "none" } });
    slide.addText(String(i + 1), { x: cx, y, w: d, h: d, align: "center", valign: "middle", fontFace: FONT_BODY, bold: true, fontSize: 15, color: COLOR.white, isTextBox: true, margin: 0 });
    slide.addText(t, { x: cx - 0.55, y: y + d + 0.08, w: d + 1.1, h: 0.6, align: "center", fontFace: FONT_BODY, fontSize: 9.5, color: COLOR.muted, isTextBox: true, margin: 0 });
  });
}

// ---------- High-level: standard "content" slide (title + bullets [+ diagram]) ----------
function addContentSlide(pres, dayNum, opts) {
  const { title, kicker, tag = "none", bullets, diagram, keyTakeaway, notes, slideLabel } = opts;
  const slide = baseContentSlide(pres, dayNum, { title, kicker, tag, slideLabel });

  const hasBullets = bullets && bullets.length > 0;
  const hasDiagram = !!diagram;

  if (hasBullets && hasDiagram) {
    addBullets(slide, bullets, { x: 0.6, y: 1.75, w: 4.6, h: 4.3, fontSize: 13.5 });
    renderDiagram(slide, pres, diagram, { x: 5.55, y: 1.9, w: 7.15 });
  } else if (hasBullets) {
    addBullets(slide, bullets, { x: 0.7, y: 1.85, w: 11.6, h: 4.3, fontSize: 15 });
  } else if (hasDiagram) {
    renderDiagram(slide, pres, diagram, { x: 0.6, y: 1.9, w: 12.1 });
  }

  if (keyTakeaway) addKeyTakeaway(slide, pres, dayNum, keyTakeaway);
  if (notes) slide.addNotes(notes);
  return slide;
}

function renderDiagram(slide, pres, diagram, region) {
  const { type } = diagram;
  if (type === "chain") {
    drawBoxChain(slide, pres, diagram.items, { x: region.x, y: region.y + 0.6, totalW: region.w, boxH: diagram.boxH || 0.85, highlightIndex: diagram.highlightIndex ?? -1, small: !!diagram.small });
  } else if (type === "twobox") {
    drawTwoBox(slide, pres, { ...diagram, x: region.x, y: region.y + 0.15, w: region.w, h: diagram.h || 3.9 });
  } else if (type === "stat") {
    drawStatCompare(slide, pres, { ...diagram, x: region.x + (region.w - 10.7 > 0 ? (region.w - 10.7) / 2 : 0), y: region.y + 0.3, w: Math.min(region.w, 10.7) });
  } else if (type === "circles") {
    drawCircleSteps(slide, pres, diagram.labels, { x: region.x, y: region.y + 0.6, w: region.w });
  } else if (type === "quote") {
    slide.addText(diagram.text, {
      x: region.x, y: region.y + 0.5, w: region.w, h: 2.2, align: "center", valign: "middle",
      fontFace: FONT_HEAD, italic: true, fontSize: 26, bold: true, color: COLOR.midnight, isTextBox: true, margin: 0,
    });
  } else if (type === "table") {
    const rows = [diagram.header.map(h => ({ text: h, options: { bold: true, color: COLOR.white, fill: { color: COLOR.deepBlue }, fontSize: 12 } }))]
      .concat(diagram.rows.map(r => r.map(c => ({ text: c, options: { color: COLOR.ink, fontSize: 11.5, fill: { color: COLOR.offwhite } } }))));
    slide.addTable(rows, { x: region.x, y: region.y + 0.35, w: region.w, colW: diagram.colW, fontFace: FONT_BODY, border: { type: "solid", color: COLOR.cardBorder, pt: 0.75 }, autoPage: false, valign: "middle" });
  }
}

// ---------- Recap / homework closing slide ----------
function addRecapSlide(pres, dayNum, { title = "Recap & Homework", bullets, homework, nextUp }) {
  const slide = pres.addSlide();
  slide.background = { color: COLOR.navy };
  slide.addText(title, { x: 0.9, y: 0.6, w: 11, h: 0.8, fontFace: FONT_HEAD, fontSize: 30, bold: true, color: COLOR.white, isTextBox: true, margin: 0 });

  const paras = bullets.map((t, i) => ({
    text: t,
    options: { bullet: { code: "25AA", indent: 18 }, color: COLOR.ice, fontFace: FONT_BODY, fontSize: 16, breakLine: i < bullets.length - 1, paraSpaceAfter: 12 },
  }));
  slide.addText(paras, { x: 0.9, y: 1.7, w: 11.2, h: 2.6, isTextBox: true, margin: 0, valign: "top" });

  slide.addShape(pres.ShapeType.roundRect, { x: 0.9, y: 4.55, w: 11.2, h: 1.15, rectRadius: 0.08, fill: { color: COLOR.deepBlue, transparency: 25 }, line: { type: "none" } });
  slide.addText([{ text: "HOMEWORK   ", options: { bold: true, color: COLOR.amber, fontSize: 12, charSpacing: 1 } }, { text: homework, options: { color: COLOR.white, fontSize: 13.5 } }], {
    x: 1.15, y: 4.55, w: 10.7, h: 1.15, valign: "middle", isTextBox: true, margin: 0, fontFace: FONT_BODY,
  });

  if (nextUp) {
    slide.addText(nextUp, { x: 0.9, y: 6.0, w: 11.2, h: 0.6, italic: true, fontFace: FONT_BODY, fontSize: 13, color: COLOR.ice, isTextBox: true, margin: 0 });
  }
  footer(slide, dayNum, "Recap");
  return slide;
}

module.exports = {
  COLOR, FONT_HEAD, FONT_BODY, newDeck, addTitleSlide, addContentSlide, addRecapSlide,
};
