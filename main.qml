// main.qml — Informe de puntos por horario (Plugin QField)
// Versión 1.6.0 — compatible QField 3.x (incluye "Puntos sin fecha"; excluye los marcados "Se borra?")
//   capa activa por defecto, opciones persistentes, avisos de fechas, columnas en blanco
// Genera un PDF con los puntos de una capa cuyo campo de fecha/hora
// (por defecto "FecHoraLec", formato "Mon Aug 31 09:50:28 2026")
// cae dentro de un rango de fechas y un rango horario.

import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12
import org.qfield 1.0
import Theme 1.0
import "informe.js" as Inf

Item {
    id: pluginRoot

    property var mapCanvas:  iface.mapCanvas()
    property var mainWindow: iface.mainWindow()
    property bool panelVisible: false

    // Estado
    property var  capas: []            // [{nombre, capa}]
    property var  campos: []           // nombres de campo de la capa elegida
    property string resultado: ""      // texto de la última búsqueda
    property string ultimoPdf: ""
    property string avisos: ""         // avisos / incongruencias detectadas
    property string tipoAnalisis: "diario"   // diario | semanal | mensual
    property bool   usarCapaActiva: true     // "Trabajar sobre la capa activa"
    property bool   incluirSinFecha: true    // "Incluir puntos sin fecha"
    // Un punto sin fecha cuenta si tiene AL MENOS UNA de estas fotos (si las 4 están vacías, no cuenta)
    readonly property var camposFoto: ["Situacion", "FInmueble", "FContador", "FArqueta"]
    // Los puntos con este campo booleano en TRUE no se contabilizan como punto cogido
    readonly property string campoSeBorra: "Se borra?"

    // Selecciones recordadas por NOMBRE (se mantienen al cerrar/abrir el panel)
    property string selCapaNombre: ""
    property string selCampo: ""
    property var    selCols: ["Direccion", "NContador", "Observacio", "", ""]
    property bool   restaurado: false

    // Colores (mismos que "Digitalización del Agua")
    readonly property color cPrimary:   "#005F8E"
    readonly property color cSecondary: "#00B4D8"
    readonly property color cBg:        "#F0F4F8"
    readonly property color cCard:      "#FFFFFF"
    readonly property color cText:      "#1A1A2E"
    readonly property color cMuted:     "#6B7280"
    readonly property color cDanger:    "#EF4444"
    readonly property color cOk:        "#2E7D32"

    readonly property string campoPorDefecto: "FecHoraLec"
    readonly property var colsPorDefecto: ["Direccion", "NContador", "Observacio", "", ""]

    // Meses: se muestran en español con su abreviatura inglesa (la que usa FecHoraLec)
    readonly property var mesesES:  ["Enero","Febrero","Marzo","Abril","Mayo","Junio","Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
    readonly property var mesesCortosES: ["ene.","feb.","mar.","abr.","may.","jun.","jul.","ago.","sep.","oct.","nov.","dic."]
    readonly property var mesesEN:  ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

    // Estado del calendario
    property bool calAbierto: false
    property string calVista: "dias"    // "dias" | "meses"
    property int calAnio: 2026
    property int calMes: 0
    property var selIni: null
    property var selFin: null

    // Estado del reloj
    property bool relojAbierto: false
    property string tpObjetivo: "ini"   // "ini" | "fin"
    property string tpModo: "h"         // "h" | "m"
    property int tpIniH: 8
    property int tpIniM: 0
    property int tpFinH: 15
    property int tpFinM: 0

    function toast(msg) { mainWindow.displayToast(msg) }

    // ─────────────────────────────────────────────
    // PERSISTENCIA (configuración interna de QField; si no existe, sólo sesión)
    // ─────────────────────────────────────────────
    readonly property string pref: "informe_puntos/"
    function leerAjuste(k, def) {
        try { var v = settings.value(pref + k, def); return (v === undefined || v === null) ? def : v } catch (e) { return def }
    }
    function guardarAjuste(k, v) { try { settings.setValue(pref + k, v) } catch (e) {} }

    function restaurarAjustes() {
        if (restaurado) return
        restaurado = true
        fResponsable.text = String(leerAjuste("responsable", ""))
        fTablet.text      = String(leerAjuste("tablet", ""))
        fDesde.text       = String(leerAjuste("desde", hoyTxt(0)))
        fHasta.text       = String(leerAjuste("hasta", hoyTxt(0)))
        fHoraIni.text     = String(leerAjuste("horaIni", "08:00"))
        fHoraFin.text     = String(leerAjuste("horaFin", "15:00"))
        tipoAnalisis      = String(leerAjuste("tipo", "diario"))
        var ua = leerAjuste("usarCapaActiva", true)
        usarCapaActiva    = !(ua === false || ua === "false")
        var isf = leerAjuste("incluirSinFecha", true)
        incluirSinFecha   = !(isf === false || isf === "false")
        selCapaNombre     = String(leerAjuste("capa", ""))
        selCampo          = String(leerAjuste("campo", ""))
        var c = String(leerAjuste("columnas", "Direccion|NContador|Observacio||"))
        var arr = c.split("|"); while (arr.length < 5) arr.push("")
        selCols = arr.slice(0, 5)
    }

    function guardarAjustes() {
        guardarAjuste("responsable", fResponsable.text)
        guardarAjuste("tablet", fTablet.text)
        guardarAjuste("desde", fDesde.text)
        guardarAjuste("hasta", fHasta.text)
        guardarAjuste("horaIni", fHoraIni.text)
        guardarAjuste("horaFin", fHoraFin.text)
        guardarAjuste("tipo", tipoAnalisis)
        guardarAjuste("usarCapaActiva", usarCapaActiva)
        guardarAjuste("incluirSinFecha", incluirSinFecha)
        guardarAjuste("capa", selCapaNombre)
        guardarAjuste("campo", selCampo)
        guardarAjuste("columnas", selCols.join("|"))
    }

    // ─────────────────────────────────────────────
    // CAPAS Y CAMPOS
    // ─────────────────────────────────────────────
    // Capa activa en QField (la resaltada en la leyenda)
    function capaActivaQField() {
        try { if (typeof dashBoard !== "undefined" && dashBoard && dashBoard.activeLayer) return dashBoard.activeLayer } catch (e) {}
        try {
            var d = iface.findItemByObjectName("dashBoard")
            if (d && d.activeLayer) return d.activeLayer
        } catch (e2) {}
        return null
    }

    // Se llama cada vez que se abre el panel
    function cargarCapas() {
        var lista = []
        try {
            var mapa = ProjectUtils.mapLayers(qgisProject)
            for (var id in mapa) {
                var l = mapa[id]
                // type 0 = capa vectorial (si la propiedad no existe, se incluye igualmente)
                if (l && (l.type === 0 || l.type === undefined)) lista.push({ nombre: l.name, capa: l })
            }
        } catch (e) {}
        var activa = capaActivaQField()
        if (activa) {
            var esta = false
            for (var j = 0; j < lista.length; j++) if (lista[j].capa === activa) { esta = true; break }
            if (!esta) lista.push({ nombre: activa.name, capa: activa })
        }
        lista.sort(function (a, b) { return a.nombre.localeCompare(b.nombre) })
        capas = lista

        var idx = -1, i
        if (usarCapaActiva && activa) {
            for (i = 0; i < lista.length; i++) if (lista[i].capa === activa) { idx = i; break }
        } else {
            for (i = 0; i < lista.length; i++) if (lista[i].nombre === selCapaNombre) { idx = i; break }
            if (idx < 0 && activa)
                for (i = 0; i < lista.length; i++) if (lista[i].capa === activa) { idx = i; break }
        }
        if (usarCapaActiva && !activa) toast("⚠ No se detecta la capa activa: elige la capa en la lista")
        cbCapa.currentIndex = idx
        if (idx >= 0) selCapaNombre = lista[idx].nombre
        cargarCampos()
    }

    function capaActual() {
        return (cbCapa.currentIndex >= 0 && cbCapa.currentIndex < capas.length) ? capas[cbCapa.currentIndex].capa : null
    }

    // Lee los campos de la capa y aplica las selecciones recordadas (por nombre)
    function cargarCampos() {
        var capa = capaActual()
        var nombres = []
        if (capa) {
            try {
                var it = LayerUtils.createFeatureIteratorFromExpression(capa, "TRUE")
                if (it.hasNext()) {
                    var n = it.next().fields.names
                    for (var i = 0; i < n.length; i++) nombres.push(n[i])
                }
                it.close()
            } catch (e) { toast("⚠ No se pudieron leer los campos: " + e) }
        }
        campos = nombres
        avisos = ""; resultado = ""

        // Campo de fecha: el recordado; si no, FecHoraLec; si no existe, en blanco
        var iF = nombres.indexOf(selCampo)
        if (iF < 0) iF = nombres.indexOf(campoPorDefecto)
        cbCampo.currentIndex = iF
        selCampo = iF >= 0 ? nombres[iF] : ""

        // Columnas: índice 0 = en blanco
        var cbs = selectoresColumnas()
        for (var c = 0; c < cbs.length; c++) {
            var k = selCols[c] ? nombres.indexOf(selCols[c]) : -1
            cbs[c].currentIndex = k >= 0 ? k + 1 : 0
        }
    }

    function selectoresColumnas() { return [cbCol1, cbCol2, cbCol3, cbCol4, cbCol5] }

    function recordarColumnas() {
        var cbs = selectoresColumnas(), out = []
        for (var i = 0; i < cbs.length; i++) out.push(cbs[i].currentIndex > 0 ? cbs[i].currentText : "")
        selCols = out
    }

    // Campos elegidos para el listado (las columnas en blanco no se imprimen)
    function columnasElegidas() {
        var cbs = selectoresColumnas(), out = []
        for (var i = 0; i < cbs.length; i++) if (cbs[i].currentIndex > 0) out.push(cbs[i].currentText)
        return out
    }

    // ─────────────────────────────────────────────
    // FILTRO Y VALIDACIONES
    // ─────────────────────────────────────────────
    function error(msg) { toast("⚠ " + msg); avisos = "⛔ " + msg; resultado = ""; return null }

    function leerFiltro() {
        avisos = ""
        var lista = []
        var tD = fDesde.text.trim(), tH = fHasta.text.trim()
        var dIni = Inf.parseDia(tD), dFin = Inf.parseDia(tH)
        if (!dIni) return error("Fecha 'Desde' no válida: '" + tD + "'. Formato dd/mm/aaaa y que el día exista (p.ej. no 31/02).")
        if (!dFin) return error("Fecha 'Hasta' no válida: '" + tH + "'. Formato dd/mm/aaaa y que el día exista (p.ej. no 31/02).")
        var hoy = new Date(); hoy.setHours(0, 0, 0, 0)
        var anioHoy = hoy.getFullYear()
        if (dIni.getFullYear() < 2000 || dIni.getFullYear() > anioHoy + 1) return error("El año de 'Desde' (" + dIni.getFullYear() + ") no parece correcto.")
        if (dFin.getFullYear() < 2000 || dFin.getFullYear() > anioHoy + 1) return error("El año de 'Hasta' (" + dFin.getFullYear() + ") no parece correcto.")
        if (dFin.getTime() < dIni.getTime()) return error("La fecha 'Hasta' (" + tH + ") es anterior a 'Desde' (" + tD + ").")
        if (dIni.getTime() > hoy.getTime()) return error("La fecha 'Desde' (" + tD + ") es posterior a hoy (" + Inf.fmtFecha(hoy) + "): no puede haber puntos.")
        if (dFin.getTime() > hoy.getTime()) lista.push("La fecha 'Hasta' (" + tH + ") es posterior a hoy; se contará hasta el momento actual.")
        var nDias = Math.round((dFin.getTime() - dIni.getTime()) / 86400000) + 1
        if (nDias > 366) lista.push("El rango de fechas es muy amplio (" + nDias + " días).")
        if (tipoAnalisis === "semanal" && nDias < 7) lista.push("Análisis semanal con un rango de sólo " + nDias + " día(s).")
        if (tipoAnalisis === "mensual" && nDias < 28) lista.push("Análisis mensual con un rango de sólo " + nDias + " día(s).")

        var hIni = Inf.parseHora(fHoraIni.text), hFin = Inf.parseHora(fHoraFin.text)
        if (hIni < 0 || hIni >= 1440) return error("Hora de inicio no válida: '" + fHoraIni.text + "' (hh:mm, 00:00 a 23:59).")
        if (hFin < 0) return error("Hora de fin no válida: '" + fHoraFin.text + "' (hh:mm, 00:00 a 23:59).")
        if (hFin === 1440) hFin = 1439
        if (hFin < hIni) return error("La hora de fin (" + fHoraFin.text + ") es anterior a la de inicio (" + fHoraIni.text + ").")
        if (hFin === hIni) lista.push("La hora de inicio y la de fin son iguales: sólo se cuenta ese minuto.")

        avisos = lista.length ? "⚠ " + lista.join("\n⚠ ") : ""
        var txt = (dIni.getTime() === dFin.getTime() ? "Día " + Inf.fmtFecha(dIni) : "Del " + Inf.fmtFecha(dIni) + " al " + Inf.fmtFecha(dFin)) +
                  ", de " + Inf.fmtMin(hIni) + " a " + Inf.fmtMin(hFin) + (dIni.getTime() === dFin.getTime() ? "" : " cada día")
        return { modo: "franja", dIni: dIni, dFin: dFin, hIni: hIni, hFin: hFin, texto: txt }
    }

    // Los periodos del resumen no pasan de hoy
    function finHastaHoy(d) { var h = new Date(); h.setHours(0, 0, 0, 0); return d.getTime() > h.getTime() ? h : d }

    function valorTexto(f, campo) {
        if (!campo) return ""
        var v = f.attribute(campo)
        if (v === null || v === undefined) return ""
        if (typeof v === "boolean") return v ? "Sí" : "No"
        if (typeof v === "object" && typeof v.getTime === "function") return Inf.fmtFechaHora(v)
        var s = String(v)
        return s === "NULL" ? "" : s
    }

    function vacio(v) {
        if (v === null || v === undefined) return true
        var t = String(v).trim()
        return t === "" || t.toUpperCase() === "NULL"
    }
    // TRUE en cualquiera de sus formas (booleano, 1, "true", "t", "verdadero", "sí"...)
    function esVerdadero(v) {
        if (v === true || v === 1) return true
        if (v === null || v === undefined || v === false || v === 0) return false
        var t = String(v).trim().toLowerCase()
        return t === "true" || t === "t" || t === "1" || t === "verdadero" || t === "si" || t === "sí" || t === "yes" || t === "y"
    }
    function tieneFoto(f, fotos) {
        for (var i = 0; i < fotos.length; i++) if (!vacio(f.attribute(fotos[i]))) return true
        return false
    }

    // Recorre la capa y devuelve {registros, sinFechaRegs, totalCapa, sinFecha, ...}
    function buscar(filtro) {
        var capa = capaActual()
        if (!capa) return error("Selecciona una capa.")
        var campo = cbCampo.currentIndex >= 0 ? cbCampo.currentText : ""
        if (!campo) return error("La capa no tiene el campo '" + campoPorDefecto + "'. Elige el campo de fecha/hora en la lista.")
        var cols = columnasElegidas()

        // Campos de foto presentes en la capa
        var fotos = []
        for (var q = 0; q < camposFoto.length; q++) if (campos.indexOf(camposFoto[q]) >= 0) fotos.push(camposFoto[q])

        var hayBorra = campos.indexOf(campoSeBorra) >= 0
        var excluidos = 0        // puntos que habrían contado pero tienen "Se borra?" = TRUE
        var regs = [], sinFRegs = [], total = 0, vacios = 0, ilegibles = 0, fMin = null, fMax = null, futuras = 0
        var limiteFuturo = new Date().getTime() + 3600000       // 1 h de margen
        var it
        try { it = LayerUtils.createFeatureIteratorFromExpression(capa, "TRUE") }
        catch (e) { return error("La capa seleccionada no es vectorial.") }
        while (it.hasNext()) {
            var f = it.next()
            total++
            var raw = f.attribute(campo), k, vals
            var borrar = hayBorra && esVerdadero(f.attribute(campoSeBorra))
            if (vacio(raw)) {
                vacios++
                // Punto sin fecha: sólo si tiene al menos una foto
                if (incluirSinFecha && fotos.length > 0 && tieneFoto(f, fotos)) {
                    if (borrar) { excluidos++; continue }
                    vals = []
                    for (k = 0; k < cols.length; k++) vals.push(valorTexto(f, cols[k]))
                    sinFRegs.push({ fecha: null, fid: String(f.id), vals: vals })
                }
                continue
            }
            var d = Inf.parseFecha(raw)
            if (!d) { ilegibles++; continue }
            if (!fMin || d < fMin) fMin = d
            if (!fMax || d > fMax) fMax = d
            if (d.getTime() > limiteFuturo) futuras++
            if (!Inf.dentroFiltro(d, filtro)) continue
            if (borrar) { excluidos++; continue }
            vals = []
            for (k = 0; k < cols.length; k++) vals.push(valorTexto(f, cols[k]))
            regs.push({ fecha: d, fid: String(f.id), vals: vals })
        }
        it.close()
        regs.sort(function (a, b) { return a.fecha.getTime() - b.fecha.getTime() })
        sinFRegs.sort(function (a, b) { return Number(a.fid) - Number(b.fid) })

        // Incongruencias detectadas en los datos
        var extra = []
        if (total > 0 && !fMin && sinFRegs.length === 0)
            return error("Ningún registro tiene una fecha legible en el campo '" + campo + "'. ¿Es el campo correcto?")
        if (incluirSinFecha && fotos.length === 0)
            extra.push("La capa no tiene los campos de foto (" + camposFoto.join(", ") + "): no se pueden incluir puntos sin fecha.")
        else if (incluirSinFecha && fotos.length < camposFoto.length)
            extra.push("Para los puntos sin fecha sólo se han revisado las fotos: " + fotos.join(", ") + ".")
        if (!hayBorra) extra.push("La capa no tiene el campo '" + campoSeBorra + "': no se ha podido excluir ningún punto marcado para borrar.")
        if (ilegibles > 0) extra.push(ilegibles + " registro(s) tienen en '" + campo + "' un valor que no es una fecha: no se incluyen.")
        if (futuras > 0) extra.push(futuras + " punto(s) tienen fecha/hora futura: revisa la hora de la tablet.")
        if (regs.length === 0 && fMin)
            extra.push("No hay puntos con fecha en el rango. La capa tiene puntos entre el " + Inf.fmtFechaHora(fMin) + " y el " + Inf.fmtFechaHora(fMax) + ".")
        if (extra.length) avisos = (avisos ? avisos + "\n" : "") + "⚠ " + extra.join("\n⚠ ")
        return { registros: regs, sinFechaRegs: sinFRegs, totalCapa: total, sinFecha: vacios + ilegibles, fMin: fMin, fMax: fMax, excluidos: excluidos }
    }

    function contar() {
        var filtro = leerFiltro(); if (!filtro) return
        var r = buscar(filtro); if (!r) return
        guardarAjustes()
        var st = Inf.estadisticas(r.registros, tipoAnalisis, filtro.dIni, finHastaHoy(filtro.dFin))
        var lineas = []
        for (var i = 0; i < st.periodos.length && lineas.length < 8; i++)
            if (st.periodos[i].n > 0) lineas.push("• " + st.periodos[i].etiqueta + ": " + st.periodos[i].n)
        var nSF = r.sinFechaRegs.length
        if (nSF > 0) lineas.push("• Puntos sin fecha: " + nSF)
        resultado = (r.registros.length + nSF) + " puntos en el rango" +
                    (nSF > 0 ? " (" + r.registros.length + " con fecha + " + nSF + " sin fecha)" : "") + "\n" + filtro.texto +
                    (lineas.length ? "\n\n" + lineas.join("\n") : "") +
                    (r.excluidos > 0 ? "\n\n(No contados por '" + campoSeBorra + "' = TRUE: " + r.excluidos + ")" : "")
        if (avisos) toast("⚠ Revisa los avisos del panel")
    }

    // ─────────────────────────────────────────────
    // PDF
    // ─────────────────────────────────────────────
    function guardarFichero(ruta, contenido) {
        // Contenido 100% ASCII → se pasa como ArrayBuffer (QByteArray exacto)
        var bytes = new Uint8Array(contenido.length)
        for (var i = 0; i < contenido.length; i++) bytes[i] = contenido.charCodeAt(i) & 0xFF
        try {
            if (FileUtils.writeFileContent(ruta, bytes.buffer)) return true
        } catch (e) {}
        try { return FileUtils.writeFileContent(ruta, contenido) } catch (e2) { return false }
    }

    function nombreSeguro(s) { return String(s).replace(/[^A-Za-z0-9_\-]+/g, "_").substring(0, 60) }

    function generar() {
        var filtro = leerFiltro(); if (!filtro) return
        var r = buscar(filtro); if (!r) return
        if (fResponsable.text.trim() === "" || fTablet.text.trim() === "")
            avisos = (avisos ? avisos + "\n" : "") + "ℹ Responsable o Tablet vacíos: salen como '-' en el PDF."
        guardarAjustes()
        var capa = capaActual()
        var ahora = new Date()
        var etq = columnasElegidas()

        var pdf = Inf.generarPDF({
            titulo:    "Informe de puntos",
            capa:      capa.name,
            campo:     selCampo,
            filtroTxt: filtro.texto,
            total:     r.registros.length,
            totalCapa: r.totalCapa,
            sinFecha:  r.sinFecha,
            sinFechaRegs: r.sinFechaRegs,
            excluidos:    r.excluidos,
            campoSeBorra: campoSeBorra,
            generado:  Inf.fmtFechaHora(ahora).substring(0, 16),
            registros: r.registros,
            etiquetas: etq,
            stats:     Inf.estadisticas(r.registros, tipoAnalisis, filtro.dIni, finHastaHoy(filtro.dFin)),
            tipo:        tipoAnalisis,
            responsable: fResponsable.text.trim(),
            tablet:      fTablet.text.trim()
        })

        var sello = ahora.getFullYear() + Inf.pad2(ahora.getMonth() + 1) + Inf.pad2(ahora.getDate()) + "_" +
                    Inf.pad2(ahora.getHours()) + Inf.pad2(ahora.getMinutes()) + Inf.pad2(ahora.getSeconds())
        var ruta = qgisProject.homePath + "/Informe_" + nombreSeguro(capa.name) + "_" + sello + ".pdf"

        if (!guardarFichero(ruta, pdf)) { toast("⚠ No se pudo escribir el PDF en " + ruta); return }
        ultimoPdf = ruta
        var nTot = r.registros.length + r.sinFechaRegs.length
        resultado = nTot + " puntos en el rango" + (r.sinFechaRegs.length ? " (" + r.sinFechaRegs.length + " sin fecha)" : "") +
                    "\n" + filtro.texto +
                    (r.excluidos > 0 ? "\n(No contados por '" + campoSeBorra + "' = TRUE: " + r.excluidos + ")" : "") +
                    "\nPDF: " + ruta.split("/").pop()
        toast(avisos ? "✔ PDF generado (" + nTot + " puntos) — revisa los avisos" : "✔ PDF generado (" + nTot + " puntos)")
        abrirPdf()
    }

    function abrirPdf() {
        if (!ultimoPdf) return
        try { platformUtilities.open(ultimoPdf); return } catch (e) {}
        try { Qt.openUrlExternally("file://" + ultimoPdf) } catch (e2) { toast("PDF guardado en: " + ultimoPdf) }
    }

    // ── Calendario ──
    function abrirCalendario() {
        selIni = Inf.parseDia(fDesde.text) || new Date(new Date().setHours(0, 0, 0, 0))
        selFin = Inf.parseDia(fHasta.text) || selIni
        calAnio = selIni.getFullYear(); calMes = selIni.getMonth()
        calVista = "dias"
        Qt.inputMethod.hide()
        calAbierto = true
    }
    function diaCelda(i) {
        var primero = new Date(calAnio, calMes, 1)
        var off = (primero.getDay() + 6) % 7          // lunes = 0
        return new Date(calAnio, calMes, 1 - off + i)
    }
    function mismoDia(a, b) { return a && b && a.getTime() === b.getTime() }
    function tocarDia(d) {
        if (!selIni || selFin) { selIni = d; selFin = null }
        else if (d.getTime() < selIni.getTime()) { selFin = selIni; selIni = d }
        else selFin = d
        if (d.getMonth() !== calMes) { calAnio = d.getFullYear(); calMes = d.getMonth() }
    }
    function moverCal(delta) {
        if (calVista === "meses") { calAnio += delta; return }
        var m = calMes + delta
        calAnio += Math.floor(m / 12); calMes = ((m % 12) + 12) % 12
    }
    function aceptarCalendario() {
        if (!selIni) { calAbierto = false; return }
        fDesde.text = Inf.fmtFecha(selIni)
        fHasta.text = Inf.fmtFecha(selFin || selIni)
        calAbierto = false
    }

    // ── Reloj ──
    function abrirReloj() {
        var a = Inf.parseHora(fHoraIni.text), b = Inf.parseHora(fHoraFin.text)
        if (a >= 0) { tpIniH = Math.floor(a / 60) % 24; tpIniM = a % 60 }
        if (b >= 0) { tpFinH = Math.floor(b / 60) % 24; tpFinM = b % 60 }
        tpObjetivo = "ini"; tpModo = "h"
        Qt.inputMethod.hide()
        relojAbierto = true
    }
    function tpH() { return tpObjetivo === "ini" ? tpIniH : tpFinH }
    function tpM() { return tpObjetivo === "ini" ? tpIniM : tpFinM }
    function fijarValorReloj(v) {
        if (tpModo === "h") { if (tpObjetivo === "ini") tpIniH = v; else tpFinH = v }
        else                { if (tpObjetivo === "ini") tpIniM = v; else tpFinM = v }
    }
    function aceptarReloj() {
        fHoraIni.text = Inf.pad2(tpIniH) + ":" + Inf.pad2(tpIniM)
        fHoraFin.text = Inf.pad2(tpFinH) + ":" + Inf.pad2(tpFinM)
        relojAbierto = false
    }

    function hoyTxt(offsetDias) {
        var d = new Date(); d.setDate(d.getDate() + (offsetDias || 0)); return Inf.fmtFecha(d)
    }

    // ─────────────────────────────────────────────
    // INTERFAZ
    // ─────────────────────────────────────────────
    component Etiqueta: Text { font.pixelSize: 11; font.bold: true; color: pluginRoot.cMuted }

    component Campo: TextField {
        height: 38; font.pixelSize: 14; leftPadding: 8
        horizontalAlignment: Text.AlignHCenter
        inputMethodHints: Qt.ImhPreferNumbers
        color: pluginRoot.cText                    // texto negro (independiente del tema de QField)
        placeholderTextColor: "#9CA3AF"
        selectionColor: pluginRoot.cSecondary
        selectedTextColor: "white"
        background: Rectangle { color: "#F9FAFB"; radius: 7; border.color: parent.activeFocus ? pluginRoot.cSecondary : "#D1D5DB"; border.width: 1 }
    }

    // Campo de texto libre (teclado normal, texto negro, alineado a la izquierda)
    component CampoTexto: TextField {
        id: ct
        property string pista: ""          // texto gris de ayuda: sólo visible con la casilla vacía
        height: 38; font.pixelSize: 14; leftPadding: 10
        inputMethodHints: Qt.ImhNone
        color: pluginRoot.cText
        placeholderText: ""                 // se usa "pista" (evita la etiqueta flotante del tema de QField)
        Text {
            anchors { left: parent.left; leftMargin: ct.leftPadding; right: parent.right; verticalCenter: parent.verticalCenter }
            text: ct.pista
            visible: ct.text.length === 0 && ct.preeditText.length === 0
            font.pixelSize: 14; color: "#9CA3AF"; elide: Text.ElideRight
        }
        selectionColor: pluginRoot.cSecondary
        selectedTextColor: "white"
        background: Rectangle { color: "white"; radius: 7; border.color: parent.activeFocus ? pluginRoot.cSecondary : "#D1D5DB"; border.width: 1 }
    }

    component Selector: ComboBox {
        id: sel
        height: 40; font.pixelSize: 13
        background: Rectangle { color: "#F9FAFB"; radius: 7; border.color: "#D1D5DB"; border.width: 1 }
        contentItem: Text {
            leftPadding: 10; rightPadding: sel.indicator ? sel.indicator.width + 6 : 10
            text: sel.displayText; font: sel.font
            color: pluginRoot.cText
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
        delegate: ItemDelegate {
            width: sel.popup.width
            highlighted: sel.highlightedIndex === index
            contentItem: Text {
                text: modelData === "" ? "— en blanco —" : modelData; font.pixelSize: 13
                font.italic: modelData === ""
                color: modelData === "" ? pluginRoot.cMuted : pluginRoot.cText
                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
            }
            background: Rectangle { color: highlighted ? "#E0F2FE" : "white" }
        }
        popup.background: Rectangle { color: "white"; radius: 7; border.color: "#D1D5DB"; border.width: 1 }
    }

    component Chip: Rectangle {
        property string texto: ""
        property bool destacado: false
        signal pulsado()
        height: 28; width: chipTxt.implicitWidth + 20; radius: 14
        color: destacado ? pluginRoot.cPrimary : "#E0F2FE"; border.color: destacado ? pluginRoot.cPrimary : pluginRoot.cSecondary; border.width: 1
        Text { id: chipTxt; anchors.centerIn: parent; text: parent.texto; font.pixelSize: 11; color: parent.destacado ? "white" : pluginRoot.cPrimary; font.bold: true }
        MouseArea { anchors.fill: parent; onClicked: parent.pulsado() }
    }

    component Tarjeta: Rectangle {
        id: tarjeta
        default property alias contenido: cuerpo.data
        property string titulo: ""
        property color colorTitulo: pluginRoot.cPrimary
        property bool plegable: false      // si true, la cabecera abre/cierra la sección
        property bool abierta: true
        width: parent ? parent.width : 0; height: col.height + 16
        radius: 10; color: pluginRoot.cCard
        border.color: "#E5E7EB"; border.width: 1
        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6
            Rectangle {
                width: parent.width; height: 28; radius: 8; color: tarjeta.colorTitulo
                Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: tarjeta.titulo; font.pixelSize: 12; font.bold: true; color: "white" }
                Text { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    visible: tarjeta.plegable
                    text: tarjeta.abierta ? "▲" : "▼"; font.pixelSize: 12; color: "white" }
                MouseArea { anchors.fill: parent; enabled: tarjeta.plegable; onClicked: tarjeta.abierta = !tarjeta.abierta }
            }
            Column {
                id: cuerpo
                width: parent.width; spacing: 6
                visible: tarjeta.abierta
            }
        }
    }

    // ── BOTÓN EN LA BARRA DE PLUGINS (columna derecha, bajo la lupa) ──
    QfToolButton {
        id: botonInforme
        iconSource: Qt.resolvedUrl("icon_toolbar.svg")
        iconColor: Theme.mainColor
        bgcolor: Theme.darkGray
        round: true
        onClicked: { pluginRoot.restaurarAjustes(); pluginRoot.cargarCapas(); pluginRoot.panelVisible = true }
    }

    // ── OVERLAY ──
    Rectangle {
        parent: mainWindow.contentItem
        anchors.fill: parent
        color: "#CC000000"
        visible: pluginRoot.panelVisible
        z: 10000

        MouseArea { anchors.fill: parent; onClicked: {} }

        Rectangle {
            id: panel
            width:  Math.min(parent.width  * 0.92, 460)
            height: Math.min(parent.height * 0.92, 800)
            anchors.centerIn: parent
            radius: 18
            color: pluginRoot.cBg
            clip: true

            // Cabecera
            Rectangle {
                id: hdr
                width: parent.width; height: 60
                color: pluginRoot.cOk
                radius: 18
                Rectangle { width: parent.width; height: 18; anchors.bottom: parent.bottom; color: parent.color }
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    spacing: 8
                    Text { text: "📄"; font.pixelSize: 20; color: "white" }
                    Column {
                        Layout.fillWidth: true
                        Text { text: "Informe de puntos por horario"; font.pixelSize: 15; font.bold: true; color: "white" }
                        Text { text: "Genera un PDF con el recuento"; font.pixelSize: 10; color: "#C8E6C9" }
                    }
                    Rectangle {
                        width: 30; height: 30; radius: 15; color: "#22FFFFFF"
                        Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 15 }
                        MouseArea { anchors.fill: parent; onClicked: { pluginRoot.guardarAjustes(); pluginRoot.panelVisible = false } }
                    }
                }
            }

            ScrollView {
                anchors { top: hdr.bottom; left: parent.left; right: parent.right; bottom: barAcciones.top }
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Column {
                    width: panel.width - 24
                    x: 12; y: 10
                    spacing: 10

                    // ── RESPONSABLE ──
                    Tarjeta {
                        titulo: "👤 Responsable"
                        colorTitulo: "#37474F"
                        RowLayout {
                            width: parent.width; spacing: 8
                            Text { text: "Responsable :"; font.pixelSize: 13; font.bold: true; color: pluginRoot.cText; Layout.preferredWidth: 100 }
                            CampoTexto { id: fResponsable; objectName: "fResponsable"; Layout.fillWidth: true; pista: "Nombre y apellidos" }
                        }
                        RowLayout {
                            width: parent.width; spacing: 8
                            Text { text: "Tablet :"; font.pixelSize: 13; font.bold: true; color: pluginRoot.cText; Layout.preferredWidth: 100 }
                            CampoTexto { id: fTablet; objectName: "fTablet"; Layout.fillWidth: true; pista: "Ej. TABLET 4" }
                        }
                    }

                    // ── CAPA ──
                    Tarjeta {
                        titulo: "🗂️ Capa y campo"

                        // Check: trabajar sobre la capa activa
                        Rectangle {
                            width: parent.width; height: 44; radius: 8
                            color: pluginRoot.usarCapaActiva ? "#E0F2FE" : "#F9FAFB"
                            border.color: pluginRoot.usarCapaActiva ? pluginRoot.cSecondary : "#E5E7EB"; border.width: 1
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 10
                                Rectangle {
                                    width: 22; height: 22; radius: 5
                                    color: pluginRoot.usarCapaActiva ? pluginRoot.cPrimary : "white"
                                    border.color: pluginRoot.usarCapaActiva ? pluginRoot.cPrimary : "#9CA3AF"; border.width: 2
                                    Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.bold: true; visible: pluginRoot.usarCapaActiva }
                                }
                                Text { text: "Trabajar sobre la capa activa"; font.pixelSize: 13; color: pluginRoot.cText; Layout.fillWidth: true }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    pluginRoot.usarCapaActiva = !pluginRoot.usarCapaActiva
                                    if (pluginRoot.usarCapaActiva) pluginRoot.cargarCapas()
                                    pluginRoot.guardarAjuste("usarCapaActiva", pluginRoot.usarCapaActiva)
                                }
                            }
                        }

                        Etiqueta { text: pluginRoot.usarCapaActiva ? "Capa (la activa en QField)" : "Capa (elegida manualmente)" }
                        Selector {
                            id: cbCapa; width: parent.width
                            enabled: !pluginRoot.usarCapaActiva
                            opacity: enabled ? 1 : 0.75
                            model: pluginRoot.capas.map(function (c) { return c.nombre })
                            onActivated: {
                                pluginRoot.selCapaNombre = currentText
                                pluginRoot.cargarCampos()
                                pluginRoot.guardarAjuste("capa", pluginRoot.selCapaNombre)
                            }
                        }
                        Etiqueta { text: "Campo de fecha/hora" }
                        Selector {
                            id: cbCampo; width: parent.width; model: pluginRoot.campos
                            onActivated: { pluginRoot.selCampo = currentText; pluginRoot.avisos = "" }
                        }
                        Text {
                            visible: cbCampo.currentIndex < 0 && pluginRoot.campos.length > 0
                            width: parent.width; wrapMode: Text.WordWrap
                            font.pixelSize: 11; color: pluginRoot.cDanger
                            text: "Esta capa no tiene el campo '" + pluginRoot.campoPorDefecto + "'. Elige el campo de fecha/hora."
                        }
                    }

                    // ── FECHAS ──
                    Tarjeta {
                        titulo: "📅 Fechas"
                        colorTitulo: "#0077B6"
                        RowLayout {
                            width: parent.width; spacing: 8
                            Column {
                                Layout.fillWidth: true; spacing: 4
                                Etiqueta { text: "Desde (dd/mm/aaaa)" }
                                Campo { id: fDesde; objectName: "fDesde"; width: parent.width; text: pluginRoot.hoyTxt(0) }
                            }
                            Column {
                                Layout.fillWidth: true; spacing: 4
                                Etiqueta { text: "Hasta (dd/mm/aaaa)" }
                                Campo { id: fHasta; objectName: "fHasta"; width: parent.width; text: pluginRoot.hoyTxt(0) }
                            }
                        }
                        Flow {
                            width: parent.width; spacing: 6
                            Chip { texto: "Hoy";  onPulsado: { fDesde.text = pluginRoot.hoyTxt(0);  fHasta.text = pluginRoot.hoyTxt(0) } }
                            Chip { texto: "Ayer"; onPulsado: { fDesde.text = pluginRoot.hoyTxt(-1); fHasta.text = pluginRoot.hoyTxt(-1) } }
                            Chip { texto: "Últimos 7 días"; onPulsado: { fDesde.text = pluginRoot.hoyTxt(-6); fHasta.text = pluginRoot.hoyTxt(0) } }
                            Chip { texto: "📅 Calendario"; destacado: true; onPulsado: pluginRoot.abrirCalendario() }
                        }

                        // Check: incluir puntos sin fecha
                        Rectangle {
                            width: parent.width; height: txtSF.implicitHeight + 22; radius: 8
                            color: pluginRoot.incluirSinFecha ? "#E0F2FE" : "#F9FAFB"
                            border.color: pluginRoot.incluirSinFecha ? pluginRoot.cSecondary : "#E5E7EB"; border.width: 1
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 10
                                Rectangle {
                                    width: 22; height: 22; radius: 5
                                    color: pluginRoot.incluirSinFecha ? pluginRoot.cPrimary : "white"
                                    border.color: pluginRoot.incluirSinFecha ? pluginRoot.cPrimary : "#9CA3AF"; border.width: 2
                                    Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.bold: true; visible: pluginRoot.incluirSinFecha }
                                }
                                Column {
                                    id: txtSF
                                    Layout.fillWidth: true
                                    Text { text: "Incluir puntos sin fecha"; font.pixelSize: 13; color: pluginRoot.cText }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 10; color: pluginRoot.cMuted
                                        text: "Puntos con " + pluginRoot.campoPorDefecto + " vacío que tengan al menos una foto (Situacion, FInmueble, FContador o FArqueta)."
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { pluginRoot.incluirSinFecha = !pluginRoot.incluirSinFecha; pluginRoot.guardarAjuste("incluirSinFecha", pluginRoot.incluirSinFecha) }
                            }
                        }
                    }

                    // ── HORAS ──
                    Tarjeta {
                        titulo: "🕒 Rango horario"
                        colorTitulo: "#00897B"
                        RowLayout {
                            width: parent.width; spacing: 8
                            Column {
                                Layout.fillWidth: true; spacing: 4
                                Etiqueta { text: "Hora inicio (hh:mm)" }
                                Campo { id: fHoraIni; objectName: "fHoraIni"; width: parent.width; text: "08:00" }
                            }
                            Column {
                                Layout.fillWidth: true; spacing: 4
                                Etiqueta { text: "Hora fin (hh:mm)" }
                                Campo { id: fHoraFin; objectName: "fHoraFin"; width: parent.width; text: "15:00" }
                            }
                        }
                        Flow {
                            width: parent.width; spacing: 6
                            Chip { texto: "Mañana 08-15"; onPulsado: { fHoraIni.text = "08:00"; fHoraFin.text = "15:00" } }
                            Chip { texto: "Tarde 15-22";  onPulsado: { fHoraIni.text = "15:00"; fHoraFin.text = "22:00" } }
                            Chip { texto: "Todo el día";  onPulsado: { fHoraIni.text = "00:00"; fHoraFin.text = "23:59" } }
                            Chip { texto: "🕒 Reloj"; destacado: true; onPulsado: pluginRoot.abrirReloj() }
                        }

                        // Tipo de análisis
                        Text { text: "Tipo de análisis"; font.pixelSize: 11; font.bold: true; color: pluginRoot.cMuted; topPadding: 4 }
                        Row {
                            width: parent.width; spacing: 6
                            Repeater {
                                model: [{ k: "diario", l: "📆 Diario" }, { k: "semanal", l: "🗓️ Semanal" }, { k: "mensual", l: "📊 Mensual" }]
                                Rectangle {
                                    width: (parent.width - 12) / 3; height: 40; radius: 8
                                    color: pluginRoot.tipoAnalisis === modelData.k ? pluginRoot.cPrimary : "#F9FAFB"
                                    border.color: pluginRoot.tipoAnalisis === modelData.k ? pluginRoot.cPrimary : "#D1D5DB"; border.width: 1
                                    Text {
                                        anchors.centerIn: parent; text: modelData.l; font.pixelSize: 13; font.bold: true
                                        color: pluginRoot.tipoAnalisis === modelData.k ? "white" : pluginRoot.cText
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: pluginRoot.tipoAnalisis = modelData.k }
                                }
                            }
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 10; color: pluginRoot.cMuted
                            text: pluginRoot.tipoAnalisis === "diario"  ? "El PDF resume los puntos de cada día del rango de fechas."
                                : pluginRoot.tipoAnalisis === "semanal" ? "El PDF resume los puntos por semana (lunes a domingo) del rango de fechas."
                                :                                          "El PDF resume los puntos por mes del rango de fechas."
                        }

                    }

                    // ── COLUMNAS DEL LISTADO ──
                    Tarjeta {
                        titulo: "📋 Columnas del listado (PDF)"
                        colorTitulo: "#5C6BC0"
                        plegable: true
                        abierta: true
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            font.pixelSize: 11; color: pluginRoot.cMuted
                            text: "Campos que aparecerán en la tabla de puntos del PDF, además de la fecha/hora y el FID. Deja en blanco las que no necesites: no se imprimen."
                        }
                        Etiqueta { text: "Columna 1" }
                        Selector { id: cbCol1; objectName: "cbCol1"; width: parent.width; model: [""].concat(pluginRoot.campos); onActivated: pluginRoot.recordarColumnas() }
                        Etiqueta { text: "Columna 2" }
                        Selector { id: cbCol2; objectName: "cbCol2"; width: parent.width; model: [""].concat(pluginRoot.campos); onActivated: pluginRoot.recordarColumnas() }
                        Etiqueta { text: "Columna 3" }
                        Selector { id: cbCol3; objectName: "cbCol3"; width: parent.width; model: [""].concat(pluginRoot.campos); onActivated: pluginRoot.recordarColumnas() }
                        Etiqueta { text: "Columna 4" }
                        Selector { id: cbCol4; objectName: "cbCol4"; width: parent.width; model: [""].concat(pluginRoot.campos); onActivated: pluginRoot.recordarColumnas() }
                        Etiqueta { text: "Columna 5" }
                        Selector { id: cbCol5; objectName: "cbCol5"; width: parent.width; model: [""].concat(pluginRoot.campos); onActivated: pluginRoot.recordarColumnas() }
                    }

                    // ── AVISOS ──
                    Rectangle {
                        width: parent.width; height: txtAvisos.height + 24
                        visible: pluginRoot.avisos !== ""
                        radius: 10
                        color: pluginRoot.avisos.indexOf("⛔") === 0 ? "#FEE2E2" : "#FFF7E6"
                        border.color: pluginRoot.avisos.indexOf("⛔") === 0 ? pluginRoot.cDanger : "#F59E0B"; border.width: 1
                        Text {
                            id: txtAvisos
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            text: pluginRoot.avisos; wrapMode: Text.WordWrap
                            font.pixelSize: 12; color: pluginRoot.cText
                        }
                    }

                    // ── RESULTADO ──
                    Rectangle {
                        width: parent.width; height: txtRes.height + 24
                        visible: pluginRoot.resultado !== ""
                        radius: 10; color: "#E8F5E9"
                        border.color: pluginRoot.cOk; border.width: 1
                        Text {
                            id: txtRes
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            text: pluginRoot.resultado; wrapMode: Text.WordWrap
                            font.pixelSize: 13; color: pluginRoot.cText
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 40; radius: 10
                        visible: pluginRoot.ultimoPdf !== ""
                        color: "#E0F2FE"; border.color: pluginRoot.cSecondary; border.width: 1
                        Text { anchors.centerIn: parent; text: "📂 Abrir último PDF"; color: pluginRoot.cPrimary; font.pixelSize: 13; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: pluginRoot.abrirPdf() }
                    }

                    Item { width: 1; height: 8 }
                }
            }

            // ── BARRA DE ACCIONES ──
            Rectangle {
                id: barAcciones
                width: parent.width; height: 58
                anchors.bottom: parent.bottom
                color: "white"; radius: 18
                Rectangle { width: parent.width; height: 18; anchors.top: parent.top; color: parent.color }

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 6; bottomMargin: 6 }
                    spacing: 8

                    Button {
                        Layout.preferredWidth: 110; height: 42
                        background: Rectangle { color: "#E0F2FE"; radius: 10 }
                        contentItem: Text { text: "🔢 Contar"; color: pluginRoot.cPrimary; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: pluginRoot.contar()
                    }
                    Button {
                        Layout.fillWidth: true; height: 42
                        background: Rectangle { color: pluginRoot.cOk; radius: 10 }
                        contentItem: Text { text: "📄  Generar PDF"; color: "white"; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: pluginRoot.generar()
                    }
                }
            }
        }
    }

    // ═════════════════════════════════════════════
    // CALENDARIO (rango de fechas)
    // ═════════════════════════════════════════════
    Rectangle {
        parent: mainWindow.contentItem
        anchors.fill: parent
        color: "#99000000"
        visible: pluginRoot.calAbierto
        z: 10001
        MouseArea { anchors.fill: parent; onClicked: pluginRoot.calAbierto = false }

        Rectangle {
            id: calCard
            width: Math.min(parent.width * 0.92, 400)
            height: calCol.height + 24
            anchors.centerIn: parent
            radius: 16; color: "white"
            MouseArea { anchors.fill: parent; onClicked: {} }     // no cerrar al tocar dentro

            Column {
                id: calCol
                x: 12; y: 12; width: parent.width - 24
                spacing: 8

                Text { text: "Selecciona el rango de fechas"; font.pixelSize: 15; font.bold: true; color: pluginRoot.cText }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 11; color: pluginRoot.cMuted
                    text: "Toca el día inicial y después el final. Para un solo día, tócalo una vez y pulsa Aceptar."
                }

                // Desde / Hasta
                Row {
                    spacing: 8
                    Repeater {
                        model: [
                            { l: "Desde", v: pluginRoot.selIni ? Inf.fmtFecha(pluginRoot.selIni) : "—" },
                            { l: "Hasta", v: pluginRoot.selFin ? Inf.fmtFecha(pluginRoot.selFin) : (pluginRoot.selIni ? Inf.fmtFecha(pluginRoot.selIni) : "—") }
                        ]
                        Rectangle {
                            width: (calCol.width - 8) / 2; height: 44; radius: 8
                            color: "#F0F4F8"; border.color: "#D1D5DB"; border.width: 1
                            Column {
                                anchors.centerIn: parent
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; font.pixelSize: 10; color: pluginRoot.cMuted }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; font.pixelSize: 15; font.bold: true; color: pluginRoot.cPrimary }
                            }
                        }
                    }
                }

                // Navegación: mes/año  ▲ ▼
                RowLayout {
                    width: parent.width; spacing: 6
                    Rectangle {
                        Layout.fillWidth: true; height: 40; radius: 8; color: "#F0F4F8"
                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            font.pixelSize: 14; font.bold: true; color: pluginRoot.cText
                            text: pluginRoot.calVista === "dias"
                                  ? pluginRoot.mesesES[pluginRoot.calMes] + " de " + pluginRoot.calAnio + "   (" + pluginRoot.mesesEN[pluginRoot.calMes] + ")"
                                  : String(pluginRoot.calAnio)
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "▾"
                            font.pixelSize: 10; color: pluginRoot.cMuted
                        }
                        MouseArea { anchors.fill: parent; onClicked: pluginRoot.calVista = (pluginRoot.calVista === "dias" ? "meses" : "dias") }
                    }
                    Repeater {
                        model: [{ t: "▲", d: -1 }, { t: "▼", d: 1 }]
                        Rectangle {
                            width: 40; height: 40; radius: 20; color: "#F0F4F8"
                            Text { anchors.centerIn: parent; text: modelData.t; font.pixelSize: 14; color: pluginRoot.cText }
                            MouseArea { anchors.fill: parent; onClicked: pluginRoot.moverCal(modelData.d) }
                        }
                    }
                }

                // ── Vista de días ──
                Column {
                    visible: pluginRoot.calVista === "dias"
                    width: parent.width; spacing: 2
                    Row {
                        Repeater {
                            model: ["L", "M", "X", "J", "V", "S", "D"]
                            Text {
                                width: calCol.width / 7; height: 24
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                text: modelData; font.pixelSize: 12; font.bold: true; color: pluginRoot.cMuted
                            }
                        }
                    }
                    Grid {
                        columns: 7
                        Repeater {
                            model: 42
                            Item {
                                id: celda
                                width: calCol.width / 7; height: 40
                                property var fecha: { pluginRoot.calAnio; pluginRoot.calMes; return pluginRoot.diaCelda(index) }
                                property bool delMes: fecha.getMonth() === pluginRoot.calMes
                                property bool esIni: pluginRoot.mismoDia(fecha, pluginRoot.selIni)
                                property bool esFin: pluginRoot.mismoDia(fecha, pluginRoot.selFin)
                                property bool enRango: pluginRoot.selIni && pluginRoot.selFin &&
                                                       fecha.getTime() > pluginRoot.selIni.getTime() && fecha.getTime() < pluginRoot.selFin.getTime()
                                property bool esHoy: pluginRoot.mismoDia(fecha, new Date(new Date().setHours(0, 0, 0, 0)))

                                Rectangle {   // franja del rango
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 34
                                    color: "#E0F2FE"
                                    visible: celda.enRango
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34; height: 34; radius: 17
                                    color: (celda.esIni || celda.esFin) ? pluginRoot.cPrimary : "transparent"
                                    border.color: celda.esHoy && !(celda.esIni || celda.esFin) ? pluginRoot.cSecondary : "transparent"
                                    border.width: 2
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: celda.fecha.getDate()
                                    font.pixelSize: 14; font.bold: celda.esIni || celda.esFin
                                    color: (celda.esIni || celda.esFin) ? "white" : (celda.delMes ? pluginRoot.cText : "#B0B7C3")
                                }
                                MouseArea { anchors.fill: parent; onClicked: pluginRoot.tocarDia(celda.fecha) }
                            }
                        }
                    }
                }

                // ── Vista de meses ──
                Grid {
                    visible: pluginRoot.calVista === "meses"
                    columns: 4
                    Repeater {
                        model: 12
                        Item {
                            width: calCol.width / 4; height: 64
                            Rectangle {
                                anchors.centerIn: parent; width: 58; height: 58; radius: 29
                                color: index === pluginRoot.calMes ? pluginRoot.cPrimary : "transparent"
                            }
                            Column {
                                anchors.centerIn: parent
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: pluginRoot.mesesCortosES[index]; font.pixelSize: 14; font.bold: true
                                       color: index === pluginRoot.calMes ? "white" : pluginRoot.cText }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: pluginRoot.mesesEN[index]; font.pixelSize: 9
                                       color: index === pluginRoot.calMes ? "#B3E5FC" : pluginRoot.cMuted }
                            }
                            MouseArea { anchors.fill: parent; onClicked: { pluginRoot.calMes = index; pluginRoot.calVista = "dias" } }
                        }
                    }
                }

                // Botones
                RowLayout {
                    width: parent.width; spacing: 8
                    Button {
                        Layout.preferredWidth: 110; height: 42
                        background: Rectangle { color: "#F3F4F6"; radius: 10 }
                        contentItem: Text { text: "Cancelar"; color: pluginRoot.cMuted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: pluginRoot.calAbierto = false
                    }
                    Button {
                        Layout.fillWidth: true; height: 42
                        background: Rectangle { color: pluginRoot.cPrimary; radius: 10 }
                        contentItem: Text { text: "Aceptar"; color: "white"; font.pixelSize: 14; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: pluginRoot.aceptarCalendario()
                    }
                }
            }
        }
    }

    // ═════════════════════════════════════════════
    // RELOJ (rango horario, estilo Android)
    // ═════════════════════════════════════════════
    Rectangle {
        parent: mainWindow.contentItem
        anchors.fill: parent
        color: "#99000000"
        visible: pluginRoot.relojAbierto
        z: 10001
        MouseArea { anchors.fill: parent; onClicked: pluginRoot.relojAbierto = false }

        Rectangle {
            id: relCard
            width: Math.min(parent.width * 0.92, 380)
            height: relCol.height + 24
            anchors.centerIn: parent
            radius: 24; color: "#2B2B2B"
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                id: relCol
                x: 16; y: 16; width: parent.width - 32
                spacing: 12

                Text { text: "Seleccionar el rango horario"; font.pixelSize: 14; color: "#E5E7EB" }

                // Pestañas Inicio / Fin
                Row {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [{ k: "ini", l: "Inicio" }, { k: "fin", l: "Fin" }]
                        Rectangle {
                            width: (relCol.width - 8) / 2; height: 34; radius: 17
                            color: pluginRoot.tpObjetivo === modelData.k ? "#00B4D8" : "#3A3A3A"
                            Text {
                                anchors.centerIn: parent; font.pixelSize: 13; font.bold: true
                                color: pluginRoot.tpObjetivo === modelData.k ? "#0B2530" : "#D1D5DB"
                                text: modelData.l + "  " +
                                      (modelData.k === "ini" ? Inf.pad2(pluginRoot.tpIniH) + ":" + Inf.pad2(pluginRoot.tpIniM)
                                                             : Inf.pad2(pluginRoot.tpFinH) + ":" + Inf.pad2(pluginRoot.tpFinM))
                            }
                            MouseArea { anchors.fill: parent; onClicked: { pluginRoot.tpObjetivo = modelData.k; pluginRoot.tpModo = "h" } }
                        }
                    }
                }

                // HH : MM grandes
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Rectangle {
                        width: 104; height: 84; radius: 10
                        color: pluginRoot.tpModo === "h" ? "#D6D6D6" : "#3A3A3A"
                        Text { anchors.centerIn: parent; text: Inf.pad2(pluginRoot.tpH()); font.pixelSize: 52
                               color: pluginRoot.tpModo === "h" ? "#111111" : "#E5E7EB" }
                        MouseArea { anchors.fill: parent; onClicked: pluginRoot.tpModo = "h" }
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: ":"; font.pixelSize: 48; color: "#E5E7EB" }
                    Rectangle {
                        width: 104; height: 84; radius: 10
                        color: pluginRoot.tpModo === "m" ? "#D6D6D6" : "#3A3A3A"
                        Text { anchors.centerIn: parent; text: Inf.pad2(pluginRoot.tpM()); font.pixelSize: 52
                               color: pluginRoot.tpModo === "m" ? "#111111" : "#E5E7EB" }
                        MouseArea { anchors.fill: parent; onClicked: pluginRoot.tpModo = "m" }
                    }
                }

                // Esfera
                Item {
                    id: esfera
                    width: Math.min(relCol.width, 280); height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    property real cx: width / 2
                    property real cy: height / 2
                    property real rExt: width / 2 - 24
                    property real rInt: width / 2 - 62
                    // valor y radio de la aguja
                    property int valor: pluginRoot.tpModo === "h" ? pluginRoot.tpH() : pluginRoot.tpM()
                    property real angulo: pluginRoot.tpModo === "h" ? (valor % 12) * 30 : valor * 6
                    property real radioAguja: (pluginRoot.tpModo === "h" && valor >= 12) ? rInt : rExt

                    Rectangle { anchors.fill: parent; radius: width / 2; color: "#3A3A3A" }

                    // Aguja
                    Rectangle {
                        x: esfera.cx - 1; y: esfera.cy - esfera.radioAguja
                        width: 2; height: esfera.radioAguja
                        color: "white"
                        transformOrigin: Item.Bottom
                        rotation: esfera.angulo
                    }
                    Rectangle { x: esfera.cx - 4; y: esfera.cy - 4; width: 8; height: 8; radius: 4; color: "white" }
                    Rectangle {
                        width: 40; height: 40; radius: 20; color: "white"
                        x: esfera.cx + esfera.radioAguja * Math.sin(esfera.angulo * Math.PI / 180) - 20
                        y: esfera.cy - esfera.radioAguja * Math.cos(esfera.angulo * Math.PI / 180) - 20
                    }

                    // Números: horas (aro exterior 0-11, interior 12-23) o minutos (00-55)
                    Repeater {
                        model: pluginRoot.tpModo === "h" ? 24 : 12
                        Text {
                            property int v: pluginRoot.tpModo === "h" ? index : index * 5
                            property real r: (pluginRoot.tpModo === "h" && index >= 12) ? esfera.rInt : esfera.rExt
                            property real a: (pluginRoot.tpModo === "h" ? (index % 12) * 30 : index * 30) * Math.PI / 180
                            property bool sel: v === esfera.valor
                            width: 40; height: 40
                            x: esfera.cx + r * Math.sin(a) - 20
                            y: esfera.cy - r * Math.cos(a) - 20
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: pluginRoot.tpModo === "h" ? String(v) : Inf.pad2(v)
                            font.pixelSize: (pluginRoot.tpModo === "h" && index >= 12) ? 13 : 16
                            color: sel ? "#111111" : ((pluginRoot.tpModo === "h" && index >= 12) ? "#BDBDBD" : "#EEEEEE")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        function actualizar(mx, my) {
                            var dx = mx - esfera.cx, dy = my - esfera.cy
                            var ang = Math.atan2(dx, -dy); if (ang < 0) ang += 2 * Math.PI
                            if (pluginRoot.tpModo === "h") {
                                var h = Math.round(ang / (2 * Math.PI) * 12) % 12
                                var dist = Math.sqrt(dx * dx + dy * dy)
                                if (dist < (esfera.rExt + esfera.rInt) / 2) h += 12
                                pluginRoot.fijarValorReloj(h)
                            } else {
                                pluginRoot.fijarValorReloj(Math.round(ang / (2 * Math.PI) * 60) % 60)
                            }
                        }
                        onPressed: function (mouse) { actualizar(mouse.x, mouse.y) }
                        onPositionChanged: function (mouse) { actualizar(mouse.x, mouse.y) }
                        onReleased: {
                            if (pluginRoot.tpModo === "h") pluginRoot.tpModo = "m"
                            else if (pluginRoot.tpObjetivo === "ini") { pluginRoot.tpObjetivo = "fin"; pluginRoot.tpModo = "h" }
                        }
                    }
                }

                // Botones
                Row {
                    anchors.right: parent.right
                    spacing: 24
                    Text {
                        text: "Cancelar"; font.pixelSize: 15; color: "#E5E7EB"
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: pluginRoot.relojAbierto = false }
                    }
                    Text {
                        text: "Aceptar"; font.pixelSize: 15; font.bold: true; color: "#00B4D8"
                        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: pluginRoot.aceptarReloj() }
                    }
                }
                Item { width: 1; height: 4 }
            }
        }
    }

    Component.onCompleted: {
        iface.addItemToPluginsToolbar(botonInforme)
        toast("📄 Informe de puntos listo")
    }
}
