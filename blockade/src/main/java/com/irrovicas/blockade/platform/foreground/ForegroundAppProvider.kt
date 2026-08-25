package com.irrovicas.blockade.platform.foreground

/**
 * Contrato para obtener el paquete de la aplicacion actualmente en
 * foreground. No implementa bloqueo ni enforcement: solo responde
 * la pregunta "que app esta en primer plano ahora mismo".
 *
 * El enforcement (AccessibilityService u otro mecanismo) es una
 * capa separada que se conectara despues, tal como se acordo con
 * ChatGPT para no mezclar ambas responsabilidades.
 */
interface ForegroundAppProvider {

    suspend fun getForegroundPackage(): String?
}
