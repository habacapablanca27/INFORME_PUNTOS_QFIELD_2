.pragma library
// informe.js — Lógica pura (sin dependencias de Qt) para el plugin
// "Informe de puntos por horario". Parseo de fechas + generador de PDF.

// ─────────────────────────────────────────────────────────────
// 1. PARSEO DE FECHAS
// ─────────────────────────────────────────────────────────────
var MESES_EN = { jan:0, feb:1, mar:2, apr:3, may:4, jun:5, jul:6, aug:7, sep:8, oct:9, nov:10, dec:11 }

function pad2(n) { return (n < 10 ? "0" : "") + n }

// Devuelve un Date (hora local) o null. Acepta:
//   - Objeto Date (campo tipo DateTime)
//   - "Mon Aug 31 09:50:28 2026"   (formato inglés de Qt / JS)
//   - "2026-08-31 09:50:28" / "2026-08-31T09:50:28"
//   - "31/08/2026 09:50:28" / "31/08/2026 09:50"
function parseFecha(v) {
    if (v === null || v === undefined) return null
    if (typeof v === "object" && typeof v.getTime === "function") {
        return isNaN(v.getTime()) ? null : new Date(v.getTime())
    }
    var s = String(v).trim()
    if (s === "" || s.toUpperCase() === "NULL") return null
    var m

    // Inglés: [Dia] Mes DD HH:MM:SS YYYY   (día de semana opcional)
    m = s.match(/^(?:[A-Za-z]{3,}\.?,?\s+)?([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{1,2}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s+(\d{4})/)
    if (m && MESES_EN.hasOwnProperty(m[1].toLowerCase())) {
        return new Date(+m[6], MESES_EN[m[1].toLowerCase()], +m[2], +m[3], +m[4], +(m[5] || 0))
    }
    // Inglés alternativo: [Dia] Mes DD YYYY HH:MM:SS
    m = s.match(/^(?:[A-Za-z]{3,}\.?,?\s+)?([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?/)
    if (m && MESES_EN.hasOwnProperty(m[1].toLowerCase())) {
        return new Date(+m[3], MESES_EN[m[1].toLowerCase()], +m[2], +m[4], +m[5], +(m[6] || 0))
    }
    // ISO: YYYY-MM-DD[ T]HH:MM[:SS]
    m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?/)
    if (m) return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0))
    // Español: DD/MM/YYYY [HH:MM[:SS]]
    m = s.match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?/)
    if (m) return new Date(+m[3], +m[2] - 1, +m[1], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0))
    return null
}

// "31/08/2026" -> Date a las 00:00 (o null)
function parseDia(s) {
    var m = String(s || "").trim().match(/^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})$/)
    if (!m) return null
    var d = new Date(+m[3], +m[2] - 1, +m[1])
    if (d.getDate() !== +m[1] || d.getMonth() !== +m[2] - 1) return null
    return d
}

// "09:30" -> minutos desde medianoche (o -1)
function parseHora(s) {
    var m = String(s || "").trim().match(/^(\d{1,2})(?::(\d{2}))?$/)
    if (!m) return -1
    var h = +m[1], mi = +(m[2] || 0)
    if (h > 24 || mi > 59 || (h === 24 && mi > 0)) return -1
    return h * 60 + mi
}

function fmtFecha(d)     { return pad2(d.getDate()) + "/" + pad2(d.getMonth() + 1) + "/" + d.getFullYear() }
function fmtHora(d)      { return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds()) }
function fmtFechaHora(d) { return fmtFecha(d) + " " + fmtHora(d) }
function fmtMin(min)     { return pad2(Math.floor(min / 60)) + ":" + pad2(min % 60) }
function claveDia(d)     { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) }

// ¿Cae la fecha dentro del filtro?
//   modo "franja":   día entre [dIni, dFin] Y hora entre [hIni, hFin] (cada día)
//   modo "continuo": desde dIni+hIni hasta dFin+hFin (un único intervalo)
// El extremo final es exacto: 10:00 incluye 10:00:00 y excluye 10:00:01 en adelante.
function dentroFiltro(d, f) {
    if (f.modo === "continuo") {
        var t0 = new Date(f.dIni.getFullYear(), f.dIni.getMonth(), f.dIni.getDate(), 0, f.hIni, 0).getTime()
        var t1 = new Date(f.dFin.getFullYear(), f.dFin.getMonth(), f.dFin.getDate(), 0, f.hFin, 59).getTime() + 999
        var t = d.getTime()
        return t >= t0 && t <= t1
    }
    var dia = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
    if (dia < f.dIni.getTime() || dia > f.dFin.getTime()) return false
    // Comparación en SEGUNDOS: "hasta las 10:00" incluye 10:00:00 pero NO 10:00:25.
    // Excepción: 23:59 (Todo el día) incluye hasta 23:59:59.
    var seg = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
    var sIni = f.hIni * 60
    var sFin = f.hFin >= 1439 ? 86399 : f.hFin * 60
    return seg >= sIni && seg <= sFin
}

// ─────────────────────────────────────────────────────────────
// 2. ESTADÍSTICAS
// ─────────────────────────────────────────────────────────────
var NOMBRE_TIPO = { diario: "Diario", semanal: "Semanal", mensual: "Mensual" }
var NOMBRE_COL  = { diario: "Día", semanal: "Semana", mensual: "Mes" }
var DIAS_ES  = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"]
var MESES_ES = ["Enero","Febrero","Marzo","Abril","Mayo","Junio","Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
var MESES_EN_CORTO = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

function lunesDe(d) { var x = new Date(d.getFullYear(), d.getMonth(), d.getDate()); x.setDate(x.getDate() - (x.getDay() + 6) % 7); return x }
function semanaISO(d) {
    var t = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7)            // jueves de esa semana
    var e = new Date(t.getFullYear(), 0, 4)
    return 1 + Math.round(((t.getTime() - e.getTime()) / 86400000 - 3 + (e.getDay() + 6) % 7) / 7)
}
function inicioPeriodo(d, tipo) {
    if (tipo === "semanal") return lunesDe(d)
    if (tipo === "mensual") return new Date(d.getFullYear(), d.getMonth(), 1)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate())
}
function siguientePeriodo(d, tipo) {
    if (tipo === "semanal") return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 7)
    if (tipo === "mensual") return new Date(d.getFullYear(), d.getMonth() + 1, 1)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)
}
function etiquetaPeriodo(d, tipo) {
    if (tipo === "semanal") {
        var fin = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 6)
        return "Semana " + semanaISO(d) + "  (" + pad2(d.getDate()) + "/" + pad2(d.getMonth() + 1) + " - " + fmtFecha(fin) + ")"
    }
    if (tipo === "mensual") return MESES_ES[d.getMonth()] + " " + d.getFullYear() + "  (" + MESES_EN_CORTO[d.getMonth()] + ")"
    return DIAS_ES[d.getDay()] + " " + fmtFecha(d)
}

// registros: [{fecha: Date, fid, vals}]; tipo: diario|semanal|mensual; dIni/dFin: rango pedido
function estadisticas(registros, tipo, dIni, dFin) {
    tipo = tipo || "diario"
    var porHora = [], cuenta = {}, i, dias = {}
    for (i = 0; i < 24; i++) porHora.push(0)
    for (i = 0; i < registros.length; i++) {
        var d = registros[i].fecha
        var k = claveDia(inicioPeriodo(d, tipo))
        cuenta[k] = (cuenta[k] || 0) + 1
        dias[claveDia(d)] = true
        porHora[d.getHours()]++
    }
    // Todos los periodos del rango (también los que tienen 0 puntos)
    var periodos = [], recortado = false
    if (dIni && dFin) {
        var p = inicioPeriodo(dIni, tipo), guard = 0
        while (p.getTime() <= dFin.getTime() && guard < 400) {
            var kk = claveDia(p)
            periodos.push({ etiqueta: etiquetaPeriodo(p, tipo), n: cuenta[kk] || 0 })
            p = siguientePeriodo(p, tipo); guard++
        }
        if (guard >= 400) recortado = true
    }
    if (!dIni || !dFin || recortado) {
        periodos = Object.keys(cuenta).sort().map(function (k) {
            var q = k.split("-"); var f = new Date(+q[0], +q[1] - 1, +q[2])
            return { etiqueta: etiquetaPeriodo(f, tipo), n: cuenta[k] }
        })
    }
    var primero = registros.length ? registros[0].fecha : null
    var ultimo  = registros.length ? registros[registros.length - 1].fecha : null
    var ritmo = ""
    if (registros.length > 1 && Object.keys(dias).length === 1) {
        var mins = (ultimo.getTime() - primero.getTime()) / 60000
        if (mins > 0) ritmo = (registros.length / (mins / 60)).toFixed(1).replace(".", ",") + " puntos/hora"
    }
    return { periodos: periodos, recortado: recortado, porHora: porHora, primero: primero, ultimo: ultimo, ritmo: ritmo }
}

// ─────────────────────────────────────────────────────────────
// 3. GENERADOR DE PDF (PDF 1.4 mínimo, fuentes Helvetica estándar)
//    Todo el fichero se genera en ASCII puro: los acentos se escriben
//    como escapes octales WinAnsi, así longitud en caracteres = bytes.
// ─────────────────────────────────────────────────────────────
var W = 595.28, H = 841.89, MX = 40     // A4 vertical, margen

// Anchos Helvetica (1/1000 em) para ASCII 32..126, para medir texto
var HELV = [278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584]
var HELVB = [278,333,474,556,556,889,722,238,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,333,333,584,584,584,611,975,722,722,722,722,667,611,778,722,278,556,722,611,833,722,778,667,778,722,667,611,722,667,944,667,667,611,333,278,333,584,556,333,556,611,556,611,556,333,611,611,278,278,556,278,889,611,611,611,611,389,556,333,611,556,778,556,556,500,389,280,389,584]

function anchoTexto(s, size, bold) {
    var t = bold ? HELVB : HELV, w = 0
    s = String(s)
    for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i)
        w += (c >= 32 && c <= 126) ? t[c - 32] : 556
    }
    return w * size / 1000
}

function recortar(s, size, bold, maxW) {
    s = String(s === null || s === undefined ? "" : s)
    if (anchoTexto(s, size, bold) <= maxW) return s
    while (s.length > 1 && anchoTexto(s + "...", size, bold) > maxW) s = s.substring(0, s.length - 1)
    return s + "..."
}

// Parte un texto en líneas que quepan en maxW (máx. maxLineas; la última se recorta con "...")
function partirTexto(s, size, bold, maxW, maxLineas) {
    s = String(s === null || s === undefined ? "" : s).replace(/\s+/g, " ").trim()
    if (s === "") return [""]
    var palabras = s.split(" "), lineas = [], actual = ""
    for (var i = 0; i < palabras.length; i++) {
        var w = palabras[i]
        while (anchoTexto(w, size, bold) > maxW && w.length > 1) {      // palabra más larga que la celda
            var corte = w.length
            while (corte > 1 && anchoTexto(w.substring(0, corte), size, bold) > maxW) corte--
            if (actual) { lineas.push(actual); actual = "" }
            lineas.push(w.substring(0, corte)); w = w.substring(corte)
        }
        var prueba = actual ? actual + " " + w : w
        if (anchoTexto(prueba, size, bold) <= maxW) actual = prueba
        else { lineas.push(actual); actual = w }
    }
    if (actual) lineas.push(actual)
    if (lineas.length > maxLineas) {
        var resto = lineas.slice(maxLineas - 1).join(" ")
        lineas = lineas.slice(0, maxLineas - 1)
        lineas.push(recortar(resto, size, bold, maxW))
    }
    return lineas
}

// Escapa texto para un literal PDF ( ... ) en WinAnsiEncoding
function esc(s) {
    s = String(s === null || s === undefined ? "" : s)
    var out = ""
    for (var i = 0; i < s.length; i++) {
        var ch = s.charAt(i), c = s.charCodeAt(i)
        if (ch === "\\" || ch === "(" || ch === ")") out += "\\" + ch
        else if (c >= 32 && c <= 126) out += ch
        else if (c === 8364) out += "\\200"                       // €
        else if (c >= 160 && c <= 255) out += "\\" + c.toString(8) // á é í ó ú ñ º ª ...
        else if (c === 8211 || c === 8212) out += "-"
        else if (c === 9 || c === 10 || c === 13) out += " "
        else out += "?"
    }
    return out
}

function num(v) { return (Math.round(v * 100) / 100).toString() }

function Pagina() { this.ops = [] }
Pagina.prototype.texto = function (x, y, s, size, bold, rgb) {
    var c = rgb || [0.1, 0.1, 0.18]
    this.ops.push(num(c[0]) + " " + num(c[1]) + " " + num(c[2]) + " rg BT /" + (bold ? "F2" : "F1") + " " + num(size) +
                  " Tf " + num(x) + " " + num(H - y) + " Td (" + esc(s) + ") Tj ET")
}
Pagina.prototype.textoCursiva = function (x, y, s, size, rgb) {   // Helvetica-Oblique (F3)
    var c = rgb || [0.1, 0.1, 0.18]
    this.ops.push(num(c[0]) + " " + num(c[1]) + " " + num(c[2]) + " rg BT /F3 " + num(size) +
                  " Tf " + num(x) + " " + num(H - y) + " Td (" + esc(s) + ") Tj ET")
}
Pagina.prototype.textoDer = function (xDer, y, s, size, bold, rgb) {
    this.texto(xDer - anchoTexto(s, size, bold), y, s, size, bold, rgb)
}
Pagina.prototype.rect = function (x, y, w, h, rgb) {   // y = borde superior
    this.ops.push(num(rgb[0]) + " " + num(rgb[1]) + " " + num(rgb[2]) + " rg " + num(x) + " " + num(H - y - h) + " " + num(w) + " " + num(h) + " re f")
}
Pagina.prototype.linea = function (x1, y1, x2, y2, rgb, grosor) {
    var c = rgb || [0.8, 0.82, 0.86]
    this.ops.push(num(c[0]) + " " + num(c[1]) + " " + num(c[2]) + " RG " + num(grosor || 0.5) + " w " +
                  num(x1) + " " + num(H - y1) + " m " + num(x2) + " " + num(H - y2) + " l S")
}

var AZUL   = [0, 0.373, 0.557]   // #005F8E (mismo color que el plugin de campo)
var CIAN   = [0, 0.706, 0.847]   // #00B4D8
var GRIS   = [0.42, 0.45, 0.5]
var FONDO  = [0.94, 0.96, 0.97]
var BLANCO = [1, 1, 1]

// Anchos de columna según el CONTENIDO real de cada columna:
//  - cada columna pide su ancho "natural" (cabecera o texto más largo, con tope)
//  - si sobra espacio, se reparte en proporción a ese ancho (la Dirección, que es
//    la más larga, recibe más); las columnas fijas (#, Fecha/hora, FID) no crecen
//  - si falta espacio, las columnas cortas conservan su ancho y las largas se
//    reparten el resto (esas son las que pasan a varias líneas)
function calcularColumnas(registros, extras, fs, disponible) {
    var PAD = 8, TOPE = 300, MIN = 34, i, r
    var cols = [{ t: "#", fijo: true }, { t: "Fecha / hora", fijo: true }, { t: "FID", fijo: true }]
    for (i = 0; i < extras.length; i++) cols.push({ t: extras[i], fijo: false })
    var n = cols.length, nat = []
    for (i = 0; i < n; i++) nat.push(anchoTexto(cols[i].t, fs + 0.5, true) + PAD)
    for (r = 0; r < registros.length; r++) {
        var reg = registros[r]
        var vals = [String(r + 1), reg.fecha ? fmtFechaHora(reg.fecha) : "Sin fecha", reg.fid].concat(reg.vals || [])
        for (i = 0; i < n; i++) {
            var w = anchoTexto(String(vals[i] === undefined || vals[i] === null ? "" : vals[i]), fs, false) + PAD
            if (w > nat[i]) nat[i] = w
        }
    }
    for (i = 0; i < n; i++) nat[i] = Math.max(MIN, Math.min(TOPE, nat[i]))
    var suma = 0
    for (i = 0; i < n; i++) suma += nat[i]
    var ancho = nat.slice()
    if (suma <= disponible) {
        // Sobra espacio: se reparte entre las columnas de datos según su ancho natural
        // (peso = ancho natural al cuadrado: la columna con textos largos, p.ej. Direccion, se lleva casi todo)
        var sumaVar = 0
        for (i = 0; i < n; i++) if (!cols[i].fijo) sumaVar += nat[i] * nat[i]
        var sobra = disponible - suma
        if (sumaVar > 0) { for (i = 0; i < n; i++) if (!cols[i].fijo) ancho[i] += sobra * nat[i] * nat[i] / sumaVar }
        else ancho[n - 1] += sobra
    } else {
        // Falta espacio: reparto "por niveles" (las cortas se quedan como están)
        // #, Fecha/hora y FID nunca se estrechan; entre las columnas de datos, las que caben
        // en una cuota equitativa se quedan como están y las largas se reparten el resto
        // en proporción a su ancho natural (la Direccion se lleva la mayor parte)
        var pend = [], resto = disponible, j, sumaPend
        for (i = 0; i < n; i++) { if (cols[i].fijo) resto -= nat[i]; else pend.push(i) }
        var cambio = true
        while (cambio && pend.length) {
            cambio = false
            var cuota = resto / pend.length
            for (j = pend.length - 1; j >= 0; j--) {
                if (nat[pend[j]] <= cuota) { ancho[pend[j]] = nat[pend[j]]; resto -= nat[pend[j]]; pend.splice(j, 1); cambio = true }
            }
        }
        sumaPend = 0
        for (j = 0; j < pend.length; j++) sumaPend += nat[pend[j]]
        for (j = 0; j < pend.length; j++) ancho[pend[j]] = Math.max(MIN, resto * nat[pend[j]] / sumaPend)
    }
    for (i = 0; i < n; i++) cols[i].w = ancho[i]
    return cols
}

// datos = { titulo, capa, campo, filtroTxt, total, totalCapa, sinFecha,
//           generado, registros:[{fecha,fid,vals:[..]}], etiquetas:[..hasta 5], stats,
//           tipo: diario|semanal|mensual, responsable, tablet,
//           sinFechaRegs:[{fecha:null,fid,vals}] }
function generarPDF(datos) {
    var paginas = [], pg, y
    var st = datos.stats

    function cabecera(p, primera) {
        p.rect(0, 0, W, primera ? 78 : 40, AZUL)
        if (primera) {
            p.texto(MX, 34, datos.titulo, 20, true, BLANCO)
            p.texto(MX, 56, "Capa: " + datos.capa + "   |   Campo: " + datos.campo, 10, false, [0.7, 0.9, 0.99])
        } else {
            p.texto(MX, 25, datos.titulo + " - " + datos.capa, 11, true, BLANCO)
        }
    }
    function nuevaPagina() {
        pg = new Pagina(); paginas.push(pg)
        cabecera(pg, paginas.length === 1)
        y = paginas.length === 1 ? 100 : 62
    }

    nuevaPagina()

    var sinF = datos.sinFechaRegs || []          // puntos con FecHoraLec vacío y alguna foto
    var nSF = sinF.length
    var gran = datos.total + nSF

    // ── Resumen ──
    var altoRes = 124
    pg.rect(MX, y, W - 2 * MX, altoRes, FONDO)
    pg.rect(MX, y, 6, altoRes, CIAN)
    pg.texto(MX + 18, y + 20, "Responsable:", 9, true, GRIS)
    pg.texto(MX + 84, y + 20, recortar(datos.responsable || "-", 10, false, 230), 10, false)
    pg.texto(MX + 18, y + 36, "Tablet:", 9, true, GRIS)
    pg.texto(MX + 84, y + 36, recortar(datos.tablet || "-", 10, false, 230), 10, false)
    pg.linea(MX + 18, y + 45, W - MX - 150, y + 45, [0.82, 0.85, 0.89], 0.5)
    pg.texto(MX + 18, y + 60, "Filtro aplicado  |  Análisis " + (NOMBRE_TIPO[datos.tipo] || "diario").toLowerCase(), 9, true, GRIS)
    pg.texto(MX + 18, y + 76, recortar(datos.filtroTxt, 10.5, false, W - 2 * MX - 170), 10.5, false)
    pg.texto(MX + 18, y + 96, "Generado: " + datos.generado, 9, false, GRIS)
    var lineaReg = "Registros en la capa: " + datos.totalCapa
    if (datos.sinFecha > 0) lineaReg += "   (sin fecha: " + datos.sinFecha + ")"
    pg.texto(MX + 18, y + 112, recortar(lineaReg, 9, false, W - 2 * MX - 170), 9, false, GRIS)
    pg.textoDer(W - MX - 18, y + 30, "PUNTOS EN EL RANGO", 9, true, GRIS)
    pg.textoDer(W - MX - 18, y + 76, String(gran), 40, true, AZUL)
    if (nSF > 0) pg.textoDer(W - MX - 18, y + 94, datos.total + " con fecha + " + nSF + " sin fecha", 8.5, false, GRIS)
    y += altoRes + 18

    // Dibuja una tabla de puntos (listado con fecha o listado de puntos sin fecha)
    function dibujarListado(titulo, registros, nota) {
        var extras = datos.etiquetas || []
        var fs = extras.length <= 3 ? 8 : 7            // tamaño de letra de la tabla
        var cols = calcularColumnas(registros, extras, fs, W - 2 * MX)
        function cabTabla() {
            pg.rect(MX, y, W - 2 * MX, 18, AZUL)
            var cx = MX
            for (var c = 0; c < cols.length; c++) {
                pg.texto(cx + 3, y + 12.5, recortar(cols[c].t, fs + 0.5, true, cols[c].w - 6), fs + 0.5, true, BLANCO)
                cx += cols[c].w
            }
            y += 18
        }
        if (y > H - 110) nuevaPagina()
        pg.texto(MX, y, titulo, 12, true, AZUL)
        if (nota) pg.textoDer(W - MX, y, nota, 8.5, false, GRIS)
        y += 8
        cabTabla()
        var lh = fs + 2.5                                 // alto de línea
        for (var r = 0; r < registros.length; r++) {
            var reg = registros[r]
            var vals = [String(r + 1), reg.fecha ? fmtFechaHora(reg.fecha) : "Sin fecha", reg.fid].concat(reg.vals || [])
            var lineas = [], maxL = 1
            for (var c1 = 0; c1 < cols.length; c1++) {
                var ls = partirTexto(vals[c1], fs, false, cols[c1].w - 6, 3)
                lineas.push(ls); if (ls.length > maxL) maxL = ls.length
            }
            var altoFila = maxL * lh + 5
            if (y + altoFila > H - 50) { nuevaPagina(); cabTabla() }
            if (r % 2 === 1) pg.rect(MX, y, W - 2 * MX, altoFila, FONDO)
            var cx2 = MX
            for (var c2 = 0; c2 < cols.length; c2++) {
                var gris = !reg.fecha && c2 === 1
                for (var l = 0; l < lineas[c2].length; l++) {
                    if (gris) pg.textoCursiva(cx2 + 3, y + 3 + fs + l * lh, lineas[c2][l], fs, GRIS)
                    else pg.texto(cx2 + 3, y + 3 + fs + l * lh, lineas[c2][l], fs, false)
                }
                cx2 += cols[c2].w
            }
            y += altoFila
        }
        y += 26
    }

    if (gran > 0) {
        if (datos.total > 0) {
            pg.texto(MX, y, "Primer punto: " + fmtFechaHora(st.primero) + "     Último punto: " + fmtFechaHora(st.ultimo) +
                     (st.ritmo ? "     Ritmo medio: " + st.ritmo : ""), 9.5, false)
            y += 24
        }

        // ── Resumen por periodo (diario / semanal / mensual) + fila "Puntos sin fecha" ──
        // Sólo se muestran los periodos con puntos (los de 0 se omiten)
        var totalPeriodos = st.periodos.length
        var per = st.periodos.filter(function (q) { return q.n > 0 })
        var conPuntos = per.length, mejor = null, p2
        for (p2 = 0; p2 < per.length; p2++) if (!mejor || per[p2].n > mejor.n) mejor = per[p2]
        var maxP = Math.max(nSF, mejor ? mejor.n : 0)          // escala de las barras
        var nombreP = { diario: "día", semanal: "semana", mensual: "mes" }[datos.tipo] || "día"
        pg.texto(MX, y, "Resumen " + (NOMBRE_TIPO[datos.tipo] || "Diario").toLowerCase(), 12, true, AZUL)
        if (datos.total > 0)
            pg.textoDer(W - MX, y, "Media: " + (datos.total / Math.max(conPuntos, 1)).toFixed(1).replace(".", ",") + " puntos/" + nombreP + " trabajado" +
                        "   |   " + ({ "día": "Días", "semana": "Semanas", "mes": "Meses" }[nombreP]) + " con puntos: " + conPuntos + " de " + totalPeriodos, 8.5, false, GRIS)
        y += 8
        var wPer = 215, wN = 60, wPct = 50, wBar = W - 2 * MX - wPer - wN - wPct
        function cabPer() {
            pg.rect(MX, y, W - 2 * MX, 18, AZUL)
            pg.texto(MX + 8, y + 12.5, NOMBRE_COL[datos.tipo] || "Día", 9, true, BLANCO)
            pg.textoDer(MX + wPer + wN - 8, y + 12.5, "Nº puntos", 9, true, BLANCO)
            pg.texto(MX + wPer + wN + 8, y + 12.5, "Distribución", 9, true, BLANCO)
            pg.textoDer(W - MX - 8, y + 12.5, "%", 9, true, BLANCO)
            y += 18
        }
        function filaPer(i, etiqueta, n, destacar, cursiva) {
            if (y > H - 60) { nuevaPagina(); cabPer() }
            if (i % 2 === 1) pg.rect(MX, y, W - 2 * MX, 16, FONDO)
            if (cursiva) pg.textoCursiva(MX + 8, y + 11.5, etiqueta, 9, null)
            else pg.texto(MX + 8, y + 11.5, recortar(etiqueta, 9, destacar, wPer - 12), 9, destacar)
            pg.textoDer(MX + wPer + wN - 8, y + 11.5, String(n), 9, true)
            var lb = maxP ? (wBar - 16) * n / maxP : 0
            if (lb > 0) pg.rect(MX + wPer + wN + 8, y + 4, lb, 8, cursiva ? GRIS : (destacar ? AZUL : CIAN))
            pg.textoDer(W - MX - 8, y + 11.5, (100 * n / gran).toFixed(1).replace(".", ",") + "%", 8.5, false)
            y += 16
        }
        cabPer()
        for (var i = 0; i < per.length; i++) filaPer(i, per[i].etiqueta, per[i].n, per[i] === mejor && per.length > 1, false)
        if (nSF > 0) filaPer(per.length, "Puntos sin fecha", nSF, false, true)
        pg.linea(MX, y, W - MX, y, AZUL, 0.8)
        pg.texto(MX + 8, y + 12, "TOTAL", 9, true)
        pg.textoDer(MX + wPer + wN - 8, y + 12, String(gran), 9, true, AZUL)
        pg.textoDer(W - MX - 8, y + 12, "100%", 8.5, true)
        y += 34

        // ── Gráfico por hora (sólo puntos con fecha) ──
        if (datos.total > 0) {
            if (y > H - 200) nuevaPagina()
            var hMin = 24, hMax = -1, maxN = 0, h
            for (h = 0; h < 24; h++) if (st.porHora[h] > 0) { hMin = Math.min(hMin, h); hMax = Math.max(hMax, h); maxN = Math.max(maxN, st.porHora[h]) }
            pg.texto(MX, y, "Puntos por hora", 12, true, AZUL); y += 10
            var nb = hMax - hMin + 1, chartH = 110, anchoUtil = W - 2 * MX
            var bw = Math.min(40, anchoUtil / nb), x0 = MX + (anchoUtil - bw * nb) / 2
            var base = y + 16 + chartH
            pg.linea(MX, base, W - MX, base, GRIS, 0.6)
            for (h = hMin; h <= hMax; h++) {
                var n = st.porHora[h], bh = maxN ? chartH * n / maxN : 0, bx = x0 + (h - hMin) * bw
                if (n > 0) {
                    pg.rect(bx + bw * 0.15, base - bh, bw * 0.7, bh, CIAN)
                    var lbl = String(n)
                    pg.texto(bx + bw / 2 - anchoTexto(lbl, 8, true) / 2, base - bh - 4, lbl, 8, true, AZUL)
                }
                var hl = pad2(h) + "h"
                pg.texto(bx + bw / 2 - anchoTexto(hl, 7, false) / 2, base + 11, hl, 7, false, GRIS)
            }
            y = base + 34

            dibujarListado("Listado de puntos", datos.registros, "")
        }

        // ── Listado de puntos sin fecha ──
        if (nSF > 0)
            dibujarListado("Puntos sin fecha", sinF, "FecHoraLec vacío, con al menos una foto")
    } else {
        pg.texto(MX, y + 10, "No se han encontrado puntos en el rango indicado.", 12, false, GRIS)
    }

    // Pies de página
    for (var p = 0; p < paginas.length; p++) {
        paginas[p].textoCursiva(MX, H - 38, "Informe Generado: " + datos.generado, 7.5, GRIS)
        paginas[p].linea(MX, H - 32, W - MX, H - 32, [0.85, 0.87, 0.9], 0.5)
        paginas[p].texto(MX, H - 20, "Digitalización del Agua - Informe de puntos", 7.5, false, GRIS)
        paginas[p].textoDer(W - MX, H - 20, "Página " + (p + 1) + " de " + paginas.length, 7.5, false, GRIS)
    }

    return ensamblar(paginas)
}

// Construye el fichero PDF con tabla xref correcta
function ensamblar(paginas) {
    var objs = []   // objs[i] = cuerpo del objeto (i+1)
    // 1 Catalog, 2 Pages, 3 F1, 4 F2, 5 F3 (cursiva), luego pares (Page, Contents)
    var kids = []
    for (var i = 0; i < paginas.length; i++) kids.push((6 + i * 2) + " 0 R")
    objs.push("<< /Type /Catalog /Pages 2 0 R >>")
    objs.push("<< /Type /Pages /Kids [" + kids.join(" ") + "] /Count " + paginas.length + " >>")
    objs.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    objs.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
    objs.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>")
    for (i = 0; i < paginas.length; i++) {
        var nPage = 6 + i * 2, nCont = nPage + 1
        var stream = paginas[i].ops.join("\n")
        objs.push("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " + num(W) + " " + num(H) + "] " +
                  "/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> /Contents " + nCont + " 0 R >>")
        objs.push("<< /Length " + stream.length + " >>\nstream\n" + stream + "\nendstream")
    }
    var out = "%PDF-1.4\n", offs = []
    for (i = 0; i < objs.length; i++) {
        offs.push(out.length)
        out += (i + 1) + " 0 obj\n" + objs[i] + "\nendobj\n"
    }
    var xref = out.length
    out += "xref\n0 " + (objs.length + 1) + "\n0000000000 65535 f \n"
    for (i = 0; i < offs.length; i++) out += ("0000000000" + offs[i]).slice(-10) + " 00000 n \n"
    out += "trailer\n<< /Size " + (objs.length + 1) + " /Root 1 0 R >>\nstartxref\n" + xref + "\n%%EOF\n"
    return out
}
