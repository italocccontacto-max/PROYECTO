# IRROVICAS

Base Android multi-app para IRROVICAS, separada en tres aplicaciones independientes:

- **IRROVICAS SYSTEM**: criterio, orientación, operación y memoria personal.
- **IRROVICAS BLOCKADE**: enforcement técnico del dispositivo.
- **IRROVICAS METRICS**: observabilidad, evidencia y reporting autorizado.

## Toolchain

- Android Gradle Plugin 9.3.0
- Gradle 9.5.0
- Kotlin 2.3.21
- JDK 17
- compileSdk / targetSdk 37
- minSdk 35
- Compose BOM 2026.08.00
- Navigation Compose 2.9.8
- Activity Compose 1.13.0
- DataStore 1.2.1

## Compilar

```bash
./gradlew assembleDebug
```

APKs:

```text
system/build/outputs/apk/debug/system-debug.apk
blockade/build/outputs/apk/debug/blockade-debug.apk
metrics/build/outputs/apk/debug/metrics-debug.apk
```

## Filosofía de dominio

Las apps no dependen de la implementación interna de las otras. La comunicación futura deberá usar contratos explícitos (deep links, intents, contenido compartido controlado o backend) y no acceder directamente a bases de datos privadas de otra app.

## Estado de esta base

Esta entrega establece la fundación compilable y las fronteras arquitectónicas. BLOCKADE ya incorpora los puntos de entrada de los servicios privilegiados, pero la lógica completa de enforcement, estadísticas y Strict Mode se implementará por fases.
