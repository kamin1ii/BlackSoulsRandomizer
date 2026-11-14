// The game writes state.js in this folder, loading it as a script works from a local file in OBS and in a browser
(function () {
  var POLL_MS = 400;
  var STALE_SECONDS = 6;
  var SUITS = [["♠︎", false], ["♥︎", true], ["♣︎", false], ["♦︎", true]];
  var listeners = [];
  var sheets = {};
  var trims = {};
  var pending = false;

  window.RandoOverlay = {
    onState: function (fn) { listeners.push(fn); },
    suit: function (i) { return SUITS[i % SUITS.length]; },
    clock: clock,
    drawSprite: drawSprite,
    staleSeconds: STALE_SECONDS
  };

  window.__randoState = function (state) {
    listeners.forEach(function (fn) { fn(state); });
  };

  function poll() {
    if (pending) return;
    pending = true;
    var tag = document.createElement("script");
    tag.src = "state.js?t=" + Date.now();
    tag.onload = tag.onerror = function () {
      pending = false;
      tag.remove();
    };
    document.head.appendChild(tag);
  }

  function pad(n) { return n < 10 ? "0" + n : String(n); }

  function clock(seconds) {
    var s = Math.max(0, Math.floor(seconds));
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    return (h > 0 ? h + ":" + pad(m) : String(m)) + ":" + pad(s % 60);
  }

  // a $ sheet holds one character, any other sheet holds eight, the front facing row is drawn
  function drawSprite(canvas, who, step, maxHeight, grow) {
    var info = (window.RANDO_SPRITES || {})[who];
    if (!info) {
      canvas.width = canvas.height = 0;
      return;
    }
    var img = sheets[info.file];
    if (!img) {
      img = sheets[info.file] = new Image();
      img.onload = function () { drawSprite(canvas, who, step, maxHeight, grow); };
      img.src = "img/" + info.file;
    }
    if (!img.complete || !img.naturalWidth) return;
    var fw = img.naturalWidth / (info.big ? 3 : 12);
    var fh = img.naturalHeight / (info.big ? 4 : 8);
    var col = (info.big ? 0 : (info.index % 4) * 3) + [0, 1, 2, 1][step % 4];
    var row = info.big ? 0 : (info.index >= 4 ? 4 : 0);
    var ctx;
    if (grow) {
      // only the drawn pixels count, a sheet with empty space around the character still fills the card
      var t = trimOf(info, img, fw, fh, row, col - [0, 1, 2, 1][step % 4]);
      var room = canvas.parentNode.clientWidth || t[2] * grow;
      var z = Math.min(grow, maxHeight / t[3], room / t[2]);
      canvas.width = t[2];
      canvas.height = t[3];
      ctx = canvas.getContext("2d");
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(img, col * fw + t[0], row * fh + t[1], t[2], t[3], 0, 0, t[2], t[3]);
      canvas.style.width = t[2] * z + "px";
      canvas.style.height = t[3] * z + "px";
      return;
    }
    var zoom = Math.max(1, Math.floor(maxHeight / fh));
    canvas.width = fw * zoom;
    canvas.height = fh * zoom;
    ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(img, col * fw, row * fh, fw, fh, 0, 0, canvas.width, canvas.height);
    canvas.style.width = canvas.style.height = "";
  }

  // the box around every pixel of the three walking frames, so the character does not shift between steps
  function trimOf(info, img, fw, fh, row, col0) {
    var key = info.file + ":" + row + ":" + col0;
    if (trims[key]) return trims[key];
    var box = [0, 0, fw, fh];
    try {
      var c = document.createElement("canvas");
      c.width = fw * 3;
      c.height = fh;
      var x = c.getContext("2d");
      x.drawImage(img, col0 * fw, row * fh, fw * 3, fh, 0, 0, fw * 3, fh);
      var d = x.getImageData(0, 0, fw * 3, fh).data;
      var x0 = fw, y0 = fh, x1 = -1, y1 = -1;
      for (var y = 0; y < fh; y++) {
        for (var i = 0; i < fw * 3; i++) {
          if (!d[(y * fw * 3 + i) * 4 + 3]) continue;
          var px = i % fw;
          if (px < x0) x0 = px;
          if (px > x1) x1 = px;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
      if (x1 >= 0) box = [x0, y0, x1 - x0 + 1, y1 - y0 + 1];
    } catch (e) {
      // a browser that will not read the pixels of a local file draws the whole frame
    }
    trims[key] = box;
    return box;
  }

  poll();
  setInterval(poll, POLL_MS);
})();
