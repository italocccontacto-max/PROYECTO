package com.irrovicas.blockade.platform.enforcement

import android.accessibilityservice.AccessibilityService
import com.irrovicas.blockade.domain.engine.EnforcementDecision

/**
 * Primera implementacion real de BlockEnforcer.
 *
 * Mecanismo MVP: cuando corresponde bloquear, saca al usuario de la
 * app/contenido llevandolo a la pantalla de inicio via
 * AccessibilityService.performGlobalAction(GLOBAL_ACTION_HOME).
 *
 * No intenta (todavia) mostrar un overlay explicativo ni distinguir
 * entre tipos de BlockTarget - eso puede refinarse en un paso
 * posterior sin cambiar el contrato de BlockEnforcer.
 */
class AndroidBlockEnforcer(
    private val globalActionPerformer: GlobalActionPerformer,
) : BlockEnforcer {

    override fun enforce(decision: EnforcementDecision.Block) {
        if (!BlockEnforcementActionResolver.shouldEnforce(decision)) {
            return
        }

        globalActionPerformer.performGlobalAction(
            AccessibilityService.GLOBAL_ACTION_HOME,
        )
    }
}
