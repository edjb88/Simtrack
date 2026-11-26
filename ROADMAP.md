# Simtrack · pendientes

Backlog de la app iOS. Nada de aquí está implementado todavía.

## Hecho recientemente

- [x] **Dashboard superpuesto al tracking**: `TrackingView` ya no se desmonta
      al cambiar de pestaña (barra de pestañas propia + capas superpuestas),
      así ARKit sigue enviando la pose con el dashboard abierto.
- [x] **Pantalla del iPhone siempre encendida** mientras la app está en primer
      plano (`isIdleTimerDisabled`), para que iOS no corte ARKit al bloquearse
      el móvil.

## Siguiente build (aparcado hasta la próxima tanda de cambios)

## Fase 2 · auriculares

- [ ] Integrar el Sony Head Tracker (IMU) en `Simtrack.Bluetooth`.
- [ ] Filtro complementario en `PoseFusion`: rotación de la IMU + posición por
      TrueDepth.
- [ ] Telemetría real de los auriculares por UDP 4244 (la pestaña
      «Auriculares» ya tiene el receptor y el modelo de datos).

## Mejoras opcionales

- [ ] Botón para volver a lanzar el descubrimiento del PC desde ajustes.
- [ ] Mostrar en la app la IP del PC descubierta (para diagnóstico).
- [ ] Elegir el puerto de SimHub desde la app si no es el 8888.
- [ ] Malla facial opcional solo como depuración (ya existe el código del
      render, hoy sin usar tras el cambio de pestañas superpuestas).
