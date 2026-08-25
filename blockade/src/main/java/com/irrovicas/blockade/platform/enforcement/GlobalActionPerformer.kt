package com.irrovicas.blockade.platform.enforcement

/**
 * Abstraccion minima sobre AccessibilityService.performGlobalAction(Int).
 *
 * Existe para que AndroidBlockEnforcer no dependa de una instancia
 * concreta de AccessibilityService, sino de esta interfaz funcional -
 * la propia service puede pasarse a si misma como referencia de
 * metodo (::performGlobalAction) porque la firma coincide exactamente.
 */
fun interface GlobalActionPerformer {

    fun performGlobalAction(action: Int): Boolean
}
