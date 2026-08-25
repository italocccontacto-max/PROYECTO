package com.irrovicas.blockade.platform.enforcement

import com.irrovicas.blockade.domain.engine.EnforcementDecision
import com.irrovicas.blockade.domain.model.BlockAction

/**
 * Logica pura: dado un EnforcementDecision, decide si corresponde
 * ejecutar el mecanismo de bloqueo (llevar al usuario fuera de la
 * app/contenido).
 *
 * Solo actua cuando la decision es Block y sus acciones incluyen
 * LAUNCH o FULL. Una politica que solo pide silenciar
 * NOTIFICATION no debe sacar al usuario de la app.
 */
object BlockEnforcementActionResolver {

    fun shouldEnforce(decision: EnforcementDecision): Boolean {
        if (decision !is EnforcementDecision.Block) {
            return false
        }

        return BlockAction.LAUNCH in decision.actions ||
            BlockAction.FULL in decision.actions
    }
}
