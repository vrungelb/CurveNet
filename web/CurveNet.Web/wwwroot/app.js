(() => {
  const LIM_MIN = -10;
  const LIM_MAX = 10;
  const SPAN = LIM_MAX - LIM_MIN; // 20
  const API_BASE = window.location.protocol === "file:" ? "http://localhost:5000" : "";

  const drawCanvas = document.getElementById("drawCanvas");
  const ctx = drawCanvas.getContext("2d");
  const canvasStage = document.getElementById("canvasStage");
  const coordReadout = document.getElementById("coordReadout");

  const previewCanvas = document.getElementById("previewCanvas");
  const prevCtx = previewCanvas.getContext("2d");

  const btnRecognize = document.getElementById("btnRecognize");
  const btnUndo = document.getElementById("btnUndo");
  const btnClear = document.getElementById("btnClear");
  const btnSave = document.getElementById("btnSave");
  const btnCopyEq = document.getElementById("btnCopyEq");
  const btnTheme = document.getElementById("btnTheme");
  const themeIcon = document.getElementById("themeIcon");
  const themeText = document.getElementById("themeText");
  const katexScript = document.getElementById("katexScript");

  const ddSaveClass = document.getElementById("ddSaveClass");

  const lblAns = document.getElementById("lblAns");
  const lblConf = document.getElementById("lblConf");
  const lblStatus = document.getElementById("lblStatus");
  const lblSaved = document.getElementById("lblSaved");
  const topTableBody = document.getElementById("topTableBody");
  const eqLatexBox = document.getElementById("eqLatexBox");

  let strokes = [];
  let currentStroke = [];
  let idealPoints = [];
  let exactEquation = "";
  let lastLatexEquation = "";
  let isDrawing = false;
  let canvasCssSize = 600;
  let activePredictAbort = null;
  let resizeRaf = 0;
  const PAD_PX = 34; // Отступ под подписи осей [-10..10]

  // --- Управление темой (светлая / тёмная) ---
  function isDarkTheme() {
    return document.documentElement.getAttribute("data-theme") === "dark";
  }

  function applyTheme(theme) {
    const dark = theme === "dark";
    if (dark) {
      document.documentElement.setAttribute("data-theme", "dark");
      themeIcon.textContent = "☀️";
      themeText.textContent = "Светлая";
    } else {
      document.documentElement.removeAttribute("data-theme");
      themeIcon.textContent = "🌙";
      themeText.textContent = "Тёмная";
    }
    try {
      localStorage.setItem("curvenet-theme", dark ? "dark" : "light");
    } catch {
      // Игнорируем ограничения localStorage в приватном режиме
    }
    renderCanvas();
  }

  function initTheme() {
    let saved = null;
    try {
      saved = localStorage.getItem("curvenet-theme");
    } catch {
      saved = null;
    }
    if (saved === "dark" || saved === "light") {
      applyTheme(saved);
    } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
      applyTheme("dark");
    } else {
      applyTheme("light");
    }
  }

  btnTheme.addEventListener("click", () => {
    applyTheme(isDarkTheme() ? "light" : "dark");
  });

  // --- Вспомогательный fetch с таймаутом и поддержкой отмены ---
  async function fetchWithTimeout(url, options = {}, timeoutMs = 10000) {
    const controller = new AbortController();
    const extSignal = options.signal;
    if (extSignal) {
      if (extSignal.aborted) controller.abort();
      else extSignal.addEventListener("abort", () => controller.abort(), { once: true });
    }
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetch(url, { ...options, signal: controller.signal });
      return res;
    } finally {
      clearTimeout(timer);
    }
  }

  // Загрузка списка классов с бэкенда
  async function loadClasses() {
    try {
      const res = await fetchWithTimeout(`${API_BASE}/api/classes`, {}, 6000);
      if (!res.ok) return;
      const classes = await res.json();
      ddSaveClass.innerHTML = "";
      for (const c of classes) {
        const optSave = document.createElement("option");
        optSave.value = c.key;
        optSave.textContent = c.name;
        ddSaveClass.appendChild(optSave);
      }
    } catch (err) {
      console.error("Не удалось загрузить словарь классов:", err);
    }
  }

  // Подгонка квадратного холста под размер контейнера
  function resizeCanvas() {
    const rect = canvasStage.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    const size = Math.max(260, Math.floor(Math.min(rect.width, rect.height) - 4));
    canvasCssSize = size;

    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    drawCanvas.style.width = `${size}px`;
    drawCanvas.style.height = `${size}px`;
    drawCanvas.width = Math.round(size * dpr);
    drawCanvas.height = Math.round(size * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    renderCanvas();
  }

  function scheduleResize() {
    if (resizeRaf) cancelAnimationFrame(resizeRaf);
    resizeRaf = requestAnimationFrame(() => {
      resizeRaf = 0;
      resizeCanvas();
    });
  }

  function worldToScreen(wx, wy) {
    const plotSize = canvasCssSize - 2 * PAD_PX;
    const sx = PAD_PX + ((wx - LIM_MIN) / SPAN) * plotSize;
    const sy = PAD_PX + ((LIM_MAX - wy) / SPAN) * plotSize;
    return [sx, sy];
  }

  function screenToWorld(sx, sy) {
    const plotSize = canvasCssSize - 2 * PAD_PX;
    const wx = LIM_MIN + ((sx - PAD_PX) / plotSize) * SPAN;
    const wy = LIM_MAX - ((sy - PAD_PX) / plotSize) * SPAN;
    return [wx, wy];
  }

  function isInPlot(wx, wy) {
    return wx >= LIM_MIN && wx <= LIM_MAX && wy >= LIM_MIN && wy <= LIM_MAX;
  }

  function renderCanvas() {
    const S = canvasCssSize;
    const plotSize = S - 2 * PAD_PX;
    const dark = isDarkTheme();

    ctx.clearRect(0, 0, S, S);

    // Фон всего холста и области графика
    ctx.fillStyle = dark ? "#15171d" : "#ffffff";
    ctx.fillRect(0, 0, S, S);

    // Сетка с шагом 2 от -10 до 10
    ctx.lineWidth = 1;
    ctx.font = "11px -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif";
    ctx.fillStyle = dark ? "#989aa6" : "#66666e";

    const axisStroke = dark ? "rgba(210, 214, 230, 0.65)" : "rgba(70, 70, 75, 0.85)";
    const gridStroke = dark ? "rgba(130, 136, 160, 0.16)" : "rgba(150, 150, 160, 0.28)";

    for (let v = LIM_MIN; v <= LIM_MAX; v += 2) {
      const [sx, sy] = worldToScreen(v, v);

      ctx.strokeStyle = v === 0 ? axisStroke : gridStroke;
      ctx.lineWidth = v === 0 ? 1.3 : 1;

      // Вертикальная линия сетки
      ctx.beginPath();
      ctx.moveTo(sx, PAD_PX);
      ctx.lineTo(sx, S - PAD_PX);
      ctx.stroke();

      // Горизонтальная линия сетки
      ctx.beginPath();
      ctx.moveTo(PAD_PX, sy);
      ctx.lineTo(S - PAD_PX, sy);
      ctx.stroke();

      // Подписи по X
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(String(v), sx, S - PAD_PX + 6);

      // Подписи по Y
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(String(v), PAD_PX - 6, sy);
    }

    // Рамка графика
    ctx.strokeStyle = dark ? "#383c4a" : "#888892";
    ctx.lineWidth = 1.2;
    ctx.strokeRect(PAD_PX, PAD_PX, plotSize, plotSize);

    // Отсечение по области [-10, 10]
    ctx.save();
    ctx.beginPath();
    ctx.rect(PAD_PX, PAD_PX, plotSize, plotSize);
    ctx.clip();

    // Отрисовка завершённых штрихов пользователя (красные)
    ctx.strokeStyle = dark ? "#ff4747" : "#d91919";
    ctx.lineWidth = 2.6;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    for (const st of strokes) {
      drawPolyline(st);
    }

    // Текущий рисуемый штрих
    if (currentStroke.length >= 2) {
      drawPolyline(currentStroke);
    }

    // Отрисовка восстановленной кривой (зелёная)
    if (idealPoints && idealPoints.length >= 2) {
      ctx.strokeStyle = dark ? "#2ee653" : "#26b340";
      ctx.lineWidth = 3.5;
      ctx.beginPath();
      let penDown = false;
      for (const pt of idealPoints) {
        if (!pt || pt[0] === null || pt[1] === null || !Number.isFinite(pt[0]) || !Number.isFinite(pt[1])) {
          penDown = false;
          continue;
        }
        const [sx, sy] = worldToScreen(pt[0], pt[1]);
        if (!penDown) {
          ctx.moveTo(sx, sy);
          penDown = true;
        } else {
          ctx.lineTo(sx, sy);
        }
      }
      ctx.stroke();
    }

    ctx.restore();
  }

  function drawPolyline(pts) {
    if (!pts || pts.length < 2) return;
    ctx.beginPath();
    const [x0, y0] = worldToScreen(pts[0][0], pts[0][1]);
    ctx.moveTo(x0, y0);
    for (let i = 1; i < pts.length; i++) {
      const [xi, yi] = worldToScreen(pts[i][0], pts[i][1]);
      ctx.lineTo(xi, yi);
    }
    ctx.stroke();
  }

  function renderLatexEquation(latexStr, fallbackExact) {
    exactEquation = fallbackExact || "";
    lastLatexEquation = latexStr || "";
    if (!latexStr) {
      eqLatexBox.textContent = "Здесь появится уравнение кривой...";
      eqLatexBox.classList.add("is-empty");
      return;
    }

    eqLatexBox.classList.remove("is-empty");

    if (window.katex) {
      try {
        window.katex.render(latexStr, eqLatexBox, {
          displayMode: true,
          throwOnError: false
        });
        return;
      } catch (e) {
        console.warn("Ошибка рендеринга KaTeX:", e);
      }
    }
    eqLatexBox.textContent = fallbackExact || latexStr;
  }

  if (katexScript) {
    katexScript.addEventListener("load", () => {
      if (lastLatexEquation) {
        renderLatexEquation(lastLatexEquation, exactEquation);
      }
    });
  }

  function cancelActivePredict() {
    if (activePredictAbort) {
      activePredictAbort.abort();
      activePredictAbort = null;
    }
    btnRecognize.disabled = false;
  }

  function clearAnswerUI() {
    lblAns.textContent = "—";
    lblAns.classList.remove("is-scribble");
    lblConf.textContent = "";
    lblStatus.textContent = "";
    lblSaved.textContent = "";
    idealPoints = [];
    renderLatexEquation("", "");
    topTableBody.innerHTML = `
      <tr class="empty-row">
        <td colspan="2">Нарисуйте кривую и нажмите «Распознать»</td>
      </tr>`;
  }

  function clearPreviewCanvas() {
    prevCtx.fillStyle = "#000000";
    prevCtx.fillRect(0, 0, 160, 160);
  }

  function renderPreviewPixels(bytes) {
    if (!bytes || bytes.length !== 160 * 160) {
      clearPreviewCanvas();
      return;
    }
    const imgData = prevCtx.createImageData(160, 160);
    const data = imgData.data;
    for (let i = 0; i < 160 * 160; i++) {
      const v = bytes[i];
      const off = i * 4;
      data[off] = v;
      data[off + 1] = v;
      data[off + 2] = v;
      data[off + 3] = 255;
    }
    prevCtx.putImageData(imgData, 0, 0);
  }

  function decodePreviewPixels(val) {
    if (!val) return null;
    if (Array.isArray(val)) return val;
    if (typeof val === "string") {
      try {
        const bin = atob(val);
        const arr = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
        return arr;
      } catch {
        return null;
      }
    }
    return null;
  }

  // Обработчики рисования мышью / тачем
  function getPointerWorld(e) {
    const rect = drawCanvas.getBoundingClientRect();
    const sx = e.clientX - rect.left;
    const sy = e.clientY - rect.top;
    return screenToWorld(sx, sy);
  }

  drawCanvas.addEventListener("pointerdown", (e) => {
    if (e.button !== undefined && e.button !== 0) return;
    const [wx, wy] = getPointerWorld(e);
    if (!isInPlot(wx, wy)) return;

    try {
      drawCanvas.setPointerCapture(e.pointerId);
    } catch {
      // Игнорируем, если браузер не поддерживает захват для данного события
    }
    cancelActivePredict();
    clearAnswerUI();
    isDrawing = true;
    currentStroke = [[wx, wy]];
    renderCanvas();
  });

  drawCanvas.addEventListener("pointermove", (e) => {
    const [wx, wy] = getPointerWorld(e);
    if (isInPlot(wx, wy)) {
      coordReadout.textContent = `x: ${wx.toFixed(2)}, y: ${wy.toFixed(2)}`;
    }
    if (!isDrawing) return;
    if (!isInPlot(wx, wy)) return;

    const last = currentStroke[currentStroke.length - 1];
    if (!last || Math.hypot(wx - last[0], wy - last[1]) < 1e-6) return;

    currentStroke.push([wx, wy]);
    renderCanvas();
  });

  function finishStroke() {
    if (!isDrawing) return;
    isDrawing = false;
    if (currentStroke.length >= 2) {
      strokes.push(currentStroke);
    }
    currentStroke = [];
    renderCanvas();
  }

  drawCanvas.addEventListener("pointerup", finishStroke);
  drawCanvas.addEventListener("pointercancel", finishStroke);
  window.addEventListener("blur", finishStroke);

  // Кнопки управления
  function doUndo() {
    cancelActivePredict();
    if (strokes.length === 0) return;
    strokes.pop();
    clearAnswerUI();
    renderCanvas();
  }

  function doClear() {
    cancelActivePredict();
    strokes = [];
    currentStroke = [];
    isDrawing = false;
    clearAnswerUI();
    clearPreviewCanvas();
    renderCanvas();
  }

  async function doRecognize() {
    if (strokes.length === 0) {
      lblStatus.textContent = "Нарисуйте фигуру.";
      return;
    }

    cancelActivePredict();
    clearAnswerUI();
    renderCanvas();

    const abortController = new AbortController();
    activePredictAbort = abortController;
    btnRecognize.disabled = true;

    try {
      const payload = {
        strokes,
        canvasSpan: SPAN
      };

      const res = await fetchWithTimeout(
        `${API_BASE}/api/predict`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
          signal: abortController.signal
        },
        10000
      );

      const R = await res.json();
      if (abortController.signal.aborted) return;

      const pixels = decodePreviewPixels(R.previewPixels);
      if (pixels && pixels.length === 160 * 160) {
        renderPreviewPixels(pixels);
      }

      if (!R.ok) {
        lblAns.textContent = "Не распознано";
        lblAns.classList.add("is-scribble");
        lblStatus.textContent = R.message || "Ошибка входных данных.";
        return;
      }

      lblAns.textContent = R.displayTitle || R.name;
      if (R.class === "scribble") {
        lblAns.classList.add("is-scribble");
      } else {
        lblAns.classList.remove("is-scribble");
        if (ddSaveClass.querySelector(`option[value="${R.class}"]`)) {
          ddSaveClass.value = R.class;
        }
      }

      let confStr = `Уверенность: ${(100 * R.confidence).toFixed(1)}%`;
      if (typeof R.residual === "number" && Number.isFinite(R.residual)) {
        confStr += `  •  Невязка: ${(100 * R.residual).toFixed(1)}%`;
      }
      lblConf.textContent = confStr;
      lblStatus.textContent = R.warning || "";

      // Топ-3 таблицы
      if (Array.isArray(R.top) && R.top.length > 0) {
        topTableBody.innerHTML = "";
        for (const row of R.top) {
          const tr = document.createElement("tr");
          const tdName = document.createElement("td");
          tdName.textContent = row.name;
          const tdPct = document.createElement("td");
          tdPct.className = "col-pct";
          tdPct.textContent = Number(row.probability || 0).toFixed(1);
          tr.appendChild(tdName);
          tr.appendChild(tdPct);
          topTableBody.appendChild(tr);
        }
      }

      // Восстановленная кривая и LaTeX-уравнение (с сохранением точного для копирования)
      idealPoints = R.idealPoints || [];
      renderLatexEquation(R.equationLatex, R.equation);
      renderCanvas();
    } catch (err) {
      if (abortController.signal.aborted) return;
      lblAns.textContent = "Ошибка";
      lblStatus.textContent = "Не удалось получить ответ от сервера.";
      console.error(err);
    } finally {
      if (activePredictAbort === abortController) {
        activePredictAbort = null;
        btnRecognize.disabled = false;
      }
    }
  }

  async function doSave() {
    if (strokes.length === 0) {
      lblSaved.textContent = "Холст пуст.";
      return;
    }
    btnSave.disabled = true;
    try {
      const res = await fetchWithTimeout(
        `${API_BASE}/api/save-sample`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            strokes,
            classKey: ddSaveClass.value,
            canvasSpan: SPAN
          })
        },
        6000
      );
      const data = await res.json();
      if (data.ok) {
        lblSaved.textContent = `Сохранено: ${data.className} (${data.total})`;
      } else {
        lblSaved.textContent = data.message || "Ошибка сохранения.";
      }
    } catch {
      lblSaved.textContent = "Ошибка соединения с сервером.";
    } finally {
      btnSave.disabled = false;
    }
  }

  btnRecognize.addEventListener("click", doRecognize);
  btnUndo.addEventListener("click", doUndo);
  btnClear.addEventListener("click", doClear);
  btnSave.addEventListener("click", doSave);

  btnCopyEq.addEventListener("click", async () => {
    if (!exactEquation) return;
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(exactEquation);
      } else {
        const tmp = document.createElement("textarea");
        tmp.value = exactEquation;
        tmp.style.position = "fixed";
        tmp.style.opacity = "0";
        document.body.appendChild(tmp);
        tmp.select();
        document.execCommand("copy");
        document.body.removeChild(tmp);
      }
      const orig = btnCopyEq.textContent;
      btnCopyEq.textContent = "Скопировано!";
      setTimeout(() => (btnCopyEq.textContent = orig), 1200);
    } catch (e) {
      console.warn("Не удалось скопировать:", e);
    }
  });

  window.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
      e.preventDefault();
      doUndo();
    } else if (e.key === "Escape") {
      doClear();
    } else if (e.key === "Enter" && document.activeElement.tagName !== "SELECT") {
      doRecognize();
    }
  });

  window.addEventListener("resize", scheduleResize);
  if (window.ResizeObserver) {
    new ResizeObserver(scheduleResize).observe(canvasStage);
  }

  initTheme();
  loadClasses();
  clearPreviewCanvas();
  resizeCanvas();
})();
