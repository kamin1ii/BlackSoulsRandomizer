// The game writes state.js in this folder, loading it as a script works from a local file in OBS and in a browser
(function () {
  var POLL_MS = 400;
  var STALE_SECONDS = 6;
  var SUITS = [["♠︎", false], ["♥︎", true], ["♣︎", false], ["♦︎", true]];
  var listeners = [];
  var sheets = {};
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
  function drawSprite(canvas, who, step, maxHeight) {
    var info = (window.RANDO_SPRITES || {})[who];
    if (!info) {
      canvas.width = canvas.height = 0;
      return;
    }
    var img = sheets[info.file];
    if (!img) {
      img = sheets[info.file] = new Image();
      img.onload = function () { drawSprite(canvas, who, step, maxHeight); };
      img.src = "img/" + info.file;
    }
    if (!img.complete || !img.naturalWidth) return;
    var fw = img.naturalWidth / (info.big ? 3 : 12);
    var fh = img.naturalHeight / (info.big ? 4 : 8);
    var col = (info.big ? 0 : (info.index % 4) * 3) + [0, 1, 2, 1][step % 4];
    var row = info.big ? 0 : (info.index >= 4 ? 4 : 0);
    var zoom = Math.max(1, Math.floor(maxHeight / fh));
    canvas.width = fw * zoom;
    canvas.height = fh * zoom;
    var ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(img, col * fw, row * fh, fw, fh, 0, 0, canvas.width, canvas.height);
  }

  poll();
  setInterval(poll, POLL_MS);
})();
