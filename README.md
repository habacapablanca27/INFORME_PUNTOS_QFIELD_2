# Informe de puntos por horario — Plugin QField

Genera un PDF con el número de puntos tomados en una capa dentro de un rango de fechas y horas,
leyendo el campo `FecHoraLec` (formato inglés `Mon Aug 31 09:50:28 2026`).

## Instalación
1. Copia la carpeta `informe_puntos_qfield` en la carpeta de plugins de QField:
   `/storage/emulated/0/Android/data/ch.opengis.qfield/files/QField/plugins/`
2. QField → Configuración → Plugins → activar **"Informe de puntos por horario"**.
3. Aparece un botón nuevo (icono de documento con barras) en la columna derecha, bajo la lupa, junto a los demás botones de plugins.

## Uso
1. Pulsa 📄 y rellena **Responsable** y **Tablet** (salen en el PDF).
   Elige **capa** y **campo de fecha/hora** (se preselecciona `FecHoraLec`).
2. Indica **fechas** (dd/mm/aaaa) y **horas** (hh:mm), escribiéndolas o con los botones:
   - **📅 Calendario**: toca el día inicial y el final (meses en español con su abreviatura inglesa: Septiembre (Sep)).
   - **🕒 Reloj**: esfera tipo Android; pestañas Inicio / Fin, primero la hora y luego los minutos.
   - Atajos: Hoy / Ayer / 7 días, Mañana 08-15 / Tarde 15-22 / Todo el día.
3. La franja horaria se aplica a cada día del rango (p.ej. del 31/08 al 02/09 de 08:00 a 15:00 cada día).
   **Capa**: con "Trabajar sobre la capa activa" marcado se usa la capa activa de QField;
   desmarcado, se elige en la lista y queda fija. **Campo**: FecHoraLec; si la capa no lo tiene, queda en blanco
   y hay que elegirlo. Las opciones se recuerdan al cerrar el panel (y entre sesiones si QField lo permite).
   Se avisa de incongruencias: fechas inexistentes, Hasta < Desde, fechas futuras, hora fin < inicio,
   rango sin puntos (indicando entre qué fechas hay datos), puntos con fecha futura, etc.
4. **Tipo de análisis**: Diario / Semanal (lunes a domingo) / Mensual. El PDF incluye una tabla-resumen
   con los periodos del rango que tienen puntos (los de 0 no se muestran), su % y una barra.
5. **Incluir puntos sin fecha** (casilla, marcada por defecto): añade los puntos con FecHoraLec vacío/NULL
   que tengan AL MENOS UNA foto (Situacion, FInmueble, FContador o FArqueta). Si las 4 fotos están vacías, no cuentan.
   En el PDF salen como fila "Puntos sin fecha" en el resumen (suman al total) y en una tabla aparte al final.
6. **🔢 Contar** muestra el recuento sin generar PDF. **📄 Generar PDF** lo crea y lo abre.

La hora final es exacta: "hasta las 10:00" incluye 10:00:00 pero no 10:00:25. "Todo el día" (23:59) llega hasta 23:59:59.

## PDF
Se guarda en la carpeta del proyecto: `Informe_<capa>_<aaaammdd_hhmmss>.pdf`. Contiene:
- Total de puntos en el rango (y cuántos registros no tienen fecha legible)
- Primer y último punto, ritmo medio (puntos/hora, si es un solo día)
- Gráfico de puntos por hora y tabla por día
- Listado con TODOS los puntos del rango: fecha/hora, FID y hasta 5 columnas a elegir
  (por defecto Direccion, NContador, Observacio). Las columnas en blanco no se imprimen.
  El ancho de cada columna se ajusta a su contenido: la Direccion (u otra con textos largos) ocupa el espacio libre.
- Pie de cada página: "Informe Generado: dd/mm/aaaa hh:mm".

## Formatos de fecha admitidos
`Mon Aug 31 09:50:28 2026`, `2026-08-31 09:50:28`, `31/08/2026 09:50:28` y campos de tipo Fecha/Hora.
