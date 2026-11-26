# Simtrack · pendientes

Backlog de la app iOS. Nada de aquí está implementado todavía.

## Siguiente build (aparcado hasta la próxima tanda de cambios)

- [ ] **Mantener la pantalla del iPhone encendida** mientras la app está en
      primer plano a pantalla de tracking/dashboard.
      - Implementación prevista: `UIApplication.shared.isIdleTimerDisabled = true`
        al arrancar y volver a `false` al pasar a segundo plano / cerrar.
      - Motivo: con ARKit y el dashboard abiertos el móvil acaba bloqueándose
        y deja de enviar pose (iOS no ejecuta ARKit en segundo plano).

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
