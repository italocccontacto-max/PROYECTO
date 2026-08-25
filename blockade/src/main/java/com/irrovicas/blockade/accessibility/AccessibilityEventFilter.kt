package com.irrovicas.blockade.accessibility

/**
 * Logica pura de interpretacion de un AccessibilityEvent crudo.
 *
 * Decide dos cosas a la vez:
 *   1) si el evento es relevante (cambio de ventana, no cualquier
 *      otro tipo de evento - el service tambien recibe
 *      typeWindowContentChanged, mucho mas ruidoso, y ese se ignora
 *      aqui antes de tocar el motor de decision);
 *   2) que packageName usar, excluyendo la propia app BLOCKADE
 *      (mismo criterio de auto-exclusion que ya usa
 *      AndroidInstalledAppsProvider contra context.packageName).
 *
 * TYPE_WINDOW_STATE_CHANGED = 32 replica el valor real de
 * android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
 * (verificado contra la documentacion oficial de Android), para que
 * esta clase no dependa del framework y se pueda testear en JVM puro.
 */
object AccessibilityEventFilter {

    const val TYPE_WINDOW_STATE_CHANGED = 32

    fun resolveForegroundPackage(
        eventType: Int,
        packageName: String?,
        ownPackageName: String,
    ): String? {
        if (eventType != TYPE_WINDOW_STATE_CHANGED) {
            return null
        }

        if (packageName.isNullOrBlank()) {
            return null
        }

        if (packageName == ownPackageName) {
            return null
        }

        return packageName
    }
}
