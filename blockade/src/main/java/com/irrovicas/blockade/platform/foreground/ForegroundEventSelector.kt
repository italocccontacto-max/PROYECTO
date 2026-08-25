package com.irrovicas.blockade.platform.foreground

/**
 * Representacion minima de un evento de uso, desacoplada de
 * android.app.usage.UsageEvents.Event para poder testear la logica
 * de seleccion sin depender del framework de Android.
 *
 * eventType usa las mismas constantes de UsageEvents.Event
 * (ACTIVITY_RESUMED = 1) para que el mapeo en la implementacion
 * Android sea directo.
 */
data class ForegroundEvent(
    val packageName: String,
    val eventType: Int,
    val timestamp: Long,
)

/**
 * Logica pura: dado un listado de eventos ya filtrado por ventana de
 * tiempo, decide cual es el paquete en foreground.
 *
 * Regla: se queda con el ULTIMO evento de tipo ACTIVITY_RESUMED.
 * Eventos de otro tipo se ignoran. Si no hay ninguno, devuelve null.
 */
object ForegroundEventSelector {

    const val ACTIVITY_RESUMED = 1

    fun selectForegroundPackage(events: List<ForegroundEvent>): String? {
        return events
            .filter { it.eventType == ACTIVITY_RESUMED }
            .maxByOrNull { it.timestamp }
            ?.packageName
    }
}
