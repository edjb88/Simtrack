# Resumen exhaustivo del proyecto “Simtrack” (para continuar con otra IA)

## 1. Objetivo general
Crear un sistema propio de head tracking 6DOF para simracing usando:
- iPhone X con cámara TrueDepth / Face ID para obtener posición (X, Y, Z) y rotación inicial.
- Auriculares Sony ULT WEAR para obtener rotación de baja latencia mediante su IMU/giroscopio.
- PC Windows como puente: recibe datos por UDP, fusiona señales y escribe en la memoria compartida de FreeTrack 2.0 para que el simulador los lea como TrackIR nativo.
- Assetto Corsa EVO como simulador principal de pruebas. AC EVO soporta TrackIR de forma nativa desde la versión 0.9.1.
- SimHub para mostrar dashboards en la pestaña correspondiente de la app iOS.

La idea final es tener una app iOS con varias pestañas y una app Windows unificada que sustituya a OpenTrack + Sony Head Tracker.

## 2. Hardware y software disponible
### Hardware
- iPhone X con Face ID / TrueDepth. Funciona con apps que usan ARKit y ARFaceTrackingConfiguration.
- Sony ULT WEAR (WH-ULT900N). Compatibles con el proyecto open-source Sony Head Tracker de Nicholas Slattery.
- PC Windows con Visual Studio Community instalado y workload de C# en proceso/instalado.
- MacBook Pro 13” mid 2015 con macOS Monterey y Xcode 14.2. Se usó para crear el proyecto iOS y generar la clave SSH. Xcode no va fino, pero sirvió para lo esencial.
- PS3 Eye disponible, pero no se está usando actualmente. Podría servir más adelante para un sistema IR DIY.
- AirPods descartados: en Windows requieren un puente tipo Raspberry Pi y complican el audio. No interesan para este proyecto.

### Software y servicios
- GitHub: repositorios públicos.
  - iOS: https://github.com/edjb88/Simtrack
  - Windows: https://github.com/edjb88/Simtrack.Bridge
- GitHub Actions para compilar el proyecto iOS en la nube sin Mac.
- Sideloadly para instalar el .ipa sin firmar en el iPhone desde Windows.
- SimHub para dashboards.
- OpenTrack / FreeTrack 2.0 como referencia de protocolo.
- Sony Head Tracker (proyecto de Nicholas Slattery, MIT) como referencia para leer los Sony.
- Visual Studio Community + C# para la app Windows.

## 3. Decisiones tomadas
1. Descartar AirPods/Beats para Windows: requieren puente con Raspberry Pi o dispositivo Apple, añaden latencia y complican el audio del PC.
2. Usar Sony ULT WEAR + Sony Head Tracker para la rotación: funciona de forma nativa en Windows, sin puentes, y es open source.
3. Usar iPhone X + TrueDepth para la posición: Face ID da muy buena precisión de profundidad.
4. Fusionar en la app Windows, no en el iPhone: la app iOS envía datos; Windows decide qué usar y escribe en FreeTrack.
5. Salida final al juego: FreeTrack 2.0 Enhanced, no UDP directo. Es el estándar que leen la mayoría de simuladores, incluido AC EVO.
6. App iOS con SwiftUI y pestañas, no Storyboard.
7. No hacer ingeniería inversa de apps de la App Store. Se descartó “destripar” TrackBridge, HeadLink, etc. por motivos legales y técnicos. La vía correcta es desarrollar con ARKit.
8. La app iOS actual tiene 3 pestañas: Tracking, Auriculares y Dashboard. Todavía no muestra tracking y dashboard a la vez; eso queda como evolución futura.
9. Dashboard de SimHub vía WKWebView, cargando la URL que SimHub genera con “Open in browser”. Debe ser http://, no https://.
10. La app Windows se organiza por módulos: App, Communication, Core, Output, Bluetooth.

## 4. Estado actual del repositorio iOS (edjb88/Simtrack)
### Estructura relevante
- Proyecto Xcode: Simtrack.xcodeproj
- Código fuente principal: Simtrack/ContentView.swift
- Punto de entrada: SimtrackApp.swift, que llama a ContentView()
- Bundle ID: com.simtrack.Simtrack
- El proyecto compila Simtrack/ContentView.swift (NO el de la raíz; se movió allí para corregir un problema).
- Permisos insertados en Simtrack.xcodeproj/project.pbxproj como:
  - INFOPLIST_KEY_NSCameraUsageDescription
  - INFOPLIST_KEY_NSLocalNetworkUsageDescription
- Workflow GitHub Actions: .github/workflows/build.yml

### Funcionalidad actual de la app iOS
- Muestra tres pestañas:
  1. Tracking: usa ARSCNView + ARFaceTrackingConfiguration, pide permiso de cámara y muestra la cámara frontal. No dibuja la malla facial (no es necesario para el objetivo).
  2. Auriculares: información y, según el último commit, preparada para recibir telemetría desde Windows mediante WindowsBridge y Combine.
  3. Dashboard: WKWebView que intenta cargar una URL de SimHub. Actualmente tiene una IP de ejemplo y aparece vacía.
- La app funciona instalada en el iPhone X mediante Sideloadly. Se activó el Modo Desarrollador en iOS.
- La app se firma con Apple ID gratuito; caduca a los 7 días y hay que reinstalar.

### Red iOS
El código más reciente define varios puertos:
- 4242: tracking 6DOF. Formato binario de 48 bytes = 6 double little-endian en orden (X, Y, Z, Yaw, Pitch, Roll).
- 4243: control desde iPhone a Windows. Mensajes JSON con "protocol": "simtrack.bridge.v1", por ejemplo orden de recentrado.
- 4244: telemetría desde Windows a iPhone. JSON con datos de auriculares Sony, conexión, IMU, etc.

La IP del PC está en SimtrackNetwork.pcIP y actualmente vale "172.20.10.12". Hay que cambiarla por la IP LAN real del PC (obtenida con ipconfig).

### Código clave ya existente
- UDPClient en Swift usando Network.framework para enviar los 6 double.
- Coordinator de ARSCNViewDelegate que recibe ARFaceAnchor.transform.
- Conversión de matriz a ángulos de Euler mediante extensión matrix_float4x4.eulerAngles (yaw, pitch, roll).
- Botón de recentrado que incrementa recenterToken y envía orden JSON a Windows.
- WindowsBridge con Combine para mostrar telemetría recibida.

## 5. Estado actual del repositorio Windows (edjb88/Simtrack.Bridge)
### Estructura
- Simtrack.App — aplicación principal (WPF o similar).
- Simtrack.Communication — aquí irá el receptor UDP.
- Simtrack.Core — aquí irá Pose y el motor de fusión.
- Simtrack.Output — aquí irá el escritor de FreeTrack.
- Simtrack.Bluetooth — aquí podría ir la integración con Sony.

### Estado real
- Es un esqueleto. MainWindow.xaml.cs solo tiene InitializeComponent().
- Las clases de Communication y Output son Class1 vacías.
- Todavía no hay lógica de recepción UDP ni escritura en FreeTrack.

## 6. Detalles técnicos críticos
### 6.1 FreeTrack 2.0 Enhanced
La app Windows debe escribir en una memoria compartida llamada exactamente:
FT_SharedMem
La estructura de datos que espera el juego es, en C#:
[StructLayout(LayoutKind.Sequential)]
public struct FTData
{
    public int DataID;      // 1
    public int CamWidth;    // 100 típico
    public int CamHeight;   // 250 típico
    public float Yaw;       // radianes
    public float Pitch;     // radianes
    public float Roll;      // radianes
    public float X;         // centímetros
    public float Y;         // centímetros
    public float Z;         // centímetros
}
[StructLayout(LayoutKind.Sequential)]
public struct FTSharedMem
{
    public FTData Data;
    public int GameID;
    public int GameID2;
    // relleno hasta 108 bytes
}
Datos importantes:
- FTData ocupa 92 bytes.
- El bloque completo FT_SharedMem ocupa 108 bytes.
- DataID debe ser 1.
- Rotaciones en radianes; traslaciones en centímetros.
- Se debe escribir a alta frecuencia, idealmente 250 Hz.
- En C#: MemoryMappedFile.CreateOrOpen("FT_SharedMem", 108) + MemoryMappedViewAccessor.

### 6.2 UDP
- El iPhone envía tracking a 4242.
- El paquete de tracking son 48 bytes = 6 double little-endian.
- El PC debe escuchar con UdpClient(4242).
- Firewall de Windows debe permitir la app.
- PC e iPhone deben estar en la misma red. El PC está por cable y el iPhone por Wi-Fi; mientras sea el mismo router, funciona.

### 6.3 Fusión prevista
- Rotación: tomarla de los Sony (baja latencia, sin depender de luz).
- Posición: tomarla del iPhone (TrueDepth).
- Algoritmo propuesto: filtro complementario. La rotación final se corrige suavemente con la rotación de ARKit para eliminar la deriva del giroscopio.
- Si no hay Sony, usar la pose completa del iPhone directamente.

### 6.4 Sony Head Tracker
- Proyecto open source MIT de Nicholas Slattery.
- Lee el protocolo Android Head Tracker HID de los Sony y lo envía a OpenTrack.
- Modelos compatibles confirmados: WH-1000XM5, WH-1000XM6, WF-1000XM6, ULT WEAR (WH-ULT900N). WF-1000XM5 probable pero no verificado. WH-1000XM4 no compatible.
- En la app Windows se puede integrar su código o recibir su salida UDP.

### 6.5 Assetto Corsa EVO
- Soporte nativo de TrackIR desde 0.9.1.
- Por tanto, escribiendo en FT_SharedMem debería funcionar sin mods.
- Alternativa: mod compatible con OpenTrack, pero la vía FreeTrack es la principal.

### 6.6 SimHub
- Sirve dashboards por web.
- URL típica: http://[IP_PC]:8888/dashboard/[nombre].
- Puerto puede variar; lo más fiable es usar “Open in browser” en SimHub y copiar la URL exacta.
- En iOS debe cargarse con WKWebView y http://, no https://.

## 7. Problemas ya resueltos y lecciones aprendidas
### Xcode / GitHub Actions
- Xcode 15.4 no existe en macos-latest. Se eliminó sudo xcode-select -s /Applications/Xcode_15.4.app y se usa el Xcode por defecto.
- Error YAML línea 2: la clave on debe escribirse entrecomillada: "on":.
- Archivos YAML contaminados por cat << 'EOF': a veces el heredoc se pega mal y mete comandos dentro del archivo. Solución: crear build.yml con el Bloc de notas y guardar como UTF-8.
- Node.js 20 deprecated: aviso inocuo. Se actualizó a actions/checkout@v5 y actions/upload-artifact@v7.
- Conflicto de rebase: se resolvió sobrescribiendo ContentView.swift, git add, git rebase --continue con GIT_EDITOR=nano o GIT_EDITOR=true.
- La app mostraba “Hello World”: había dos ContentView.swift, uno en la raíz y otro en Simtrack/. El proyecto compilaba el de Simtrack/, que era el viejo. Se copió el bueno a Simtrack/ContentView.swift y se eliminó el de la raíz. Ahora la app muestra las tres pestañas.
- El .ipa pesa 11 KB: es normal porque el binario se comprime; el binario real son ~96 KB. El problema real era el archivo duplicado.
- Diagnóstico útil: strings sobre el binario para buscar Tracking, Auriculares, etc.

### Git / SSH
- Clave SSH generada en el Mac y copiada a Windows en C:\Users\Eduu\.ssh\.
- Git configurado con user.name y user.email.
- Remoto iOS: git@github.com:edjb88/Simtrack.git (ojo, mayúscula en Simtrack).
- git pull --rebase usado para integrar cambios remotos.
- Se usa git push origin main.

### iOS
- Es obligatorio activar Modo Desarrollador en Ajustes → Privacidad y seguridad.
- La app instalada con Sideloadly caduca a los 7 días.
- ARKit no funciona en simulador; hay que probar en iPhone X.
- La cámara no puede capturar en segundo plano; la app debe estar en primer plano.
- Se puede ejecutar ARKit sin mostrar la vista de cámara, usando solo el delegate. Eso permitiría en el futuro mostrar un WKWebView con SimHub mientras ARKit sigue capturando.

## 8. Lo que falta por hacer
### Inmediato: app Windows
1. Implementar en Simtrack.Communication un receptor UDP en el puerto 4242 que lea 48 bytes y convierta a 6 double.
2. Implementar en Simtrack.Output el escritor de FreeTrack 2.0:
   - Crear/abrir FT_SharedMem con 108 bytes.
   - Rellenar FTData con DataID=1, CamWidth=100, CamHeight=250, rotaciones en radianes y posición en cm.
   - Escribir a alta frecuencia.
3. Probar la cadena iPhone → PC → Assetto Corsa EVO sin fusionar todavía: usar directamente la pose del iPhone.
4. Verificar en AC EVO que la cámara responde.

### Después: fusión y Sony
5. Integrar o recibir los datos de Sony Head Tracker.
6. Implementar FusionEngine en Simtrack.Core con filtro complementario.
7. Enviar telemetría de vuelta al iPhone por 4244 para la pestaña Auriculares.
8. Implementar la orden de recentrado desde iOS a Windows por 4243.

### Más adelante: app iOS avanzada
9. Cambiar la IP 172.20.10.12 por la IP real del PC.
10. Configurar la URL real de SimHub en DashboardView.
11. Opcional: crear una pantalla única que muestre el dashboard con WKWebView mientras ARKit captura sin preview.
12. Opcional: visualizar la malla facial en la pestaña Tracking para depurar.
13. Opcional: estudiar un sistema IR DIY con PS3 Eye + LEDs, pero no es prioritario.

## 9. Prompt sugerido para la nueva IA
> Continúa el proyecto “Simtrack” descrito en este resumen. El usuario está en Windows, tiene Visual Studio Community con C#, y necesita instrucciones paso a paso, en español, sin dar por sabido nada. El repositorio iOS edjb88/Simtrack ya compila y la app funciona en iPhone X con tres pestañas. El repositorio Windows edjb88/Simtrack.Bridge es un esqueleto con proyectos App, Communication, Core, Output y Bluetooth. La prioridad es implementar el receptor UDP en Communication y el escritor de FreeTrack 2.0 en Output, usando la estructura FTData/FTSharedMem indicada, para probar en Assetto Corsa EVO. Después, fusionar Sony + iPhone y añadir telemetría/recentrado. No propongas ingeniería inversa de apps de la App Store. No uses AirPods. Ten en cuenta los problemas ya resueltos: "on": en YAML, archivos duplicados ContentView.swift, Xcode por defecto en macos-latest, GIT_EDITOR=true, permisos en project.pbxproj, y que la app iOS se instala con Sideloadly y caduca a los 7 días.