function drawFrame(ctx, w, h) {
  ctx.clear(#FFFFFF);
  ctx.strokeRect(0, 0, w, h, 1, #C8D2DC);
  ctx.strokeLine(32, 12, 32, h - 24, 1, #D8E0E8);
  ctx.strokeLine(32, h - 24, w - 10, h - 24, 1, #D8E0E8);
}

function drawTraffic(ctx, data) {
  let w = 400;
  let h = 180;
  drawFrame(ctx, w, h);

  let left = 36;
  let base = h - 28;
  let step = 34;
  let maxBar = 120;

  for (let i = 0; i < data.length; i = i + 1) {
    let v = data[i];
    let bar = v * maxBar div 100;
    let x = left + i * step;
    let y = base - bar;
    ctx.fillRect(x, y, 20, bar, #2F6F9F);
    ctx.strokeRect(x, y, 20, bar, 1, #194B72);
  }

  ctx.fillText("requests", 8, 12, font=default-mono-10, color=#617080);
}

exports { drawTraffic };
