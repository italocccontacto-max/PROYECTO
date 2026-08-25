package com.irrovicas.blockade.platform.foreground

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context

/**
 * Implementacion Android de ForegroundAppProvider basada en
 * UsageStatsManager.queryEvents(...).
 *
 * Importante: UsageStatsManager por si solo NO bloquea aplicaciones,
 * solo permite consultar que paquete estuvo en foreground. El
 * enforcement (AccessibilityService u otro mecanismo) es una capa
 * separada que se construira despues.
 *
 * Requiere el permiso PACKAGE_USAGE_STATS, que es un permiso
 * especial: declararlo en el manifest no otorga el acceso, el
 * usuario debe habilitarlo manualmente desde
 * Settings.ACTION_USAGE_ACCESS_SETTINGS. Ese flujo de UI no se
 * implementa todavia en este paso.
 */
class AndroidForegroundAppProvider(
    private val context: Context,
    private val clock: Clock = SystemClock(),
    private val windowMillis: Long = DEFAULT_WINDOW_MILLIS,
) : ForegroundAppProvider {

    override suspend fun getForegroundPackage(): String? {
        val usageStatsManager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return null

        val now = clock.currentTimeMillis()
        val events = usageStatsManager.queryEvents(now - windowMillis, now)

        val collected = mutableListOf<ForegroundEvent>()
        val event = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)

            collected.add(
                ForegroundEvent(
                    packageName = event.packageName,
                    eventType = event.eventType,
                    timestamp = event.timeStamp,
                ),
            )
        }

        return ForegroundEventSelector.selectForegroundPackage(collected)
    }

    private companion object {
        const val DEFAULT_WINDOW_MILLIS = 10_000L
    }
}
