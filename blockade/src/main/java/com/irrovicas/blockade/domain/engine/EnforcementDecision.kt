package com.irrovicas.blockade.domain.engine

import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget

/**
 * Resultado del motor de decisión.
 *
 * El motor responde:
 * "¿Qué debe hacerse?"
 *
 * El mecanismo Android responderá después:
 * "¿Cómo lo hago?"
 */
sealed interface EnforcementDecision {

    /**
     * No existe ninguna política activa que impida el acceso.
     */
    data object Allow : EnforcementDecision

    /**
     * El objetivo debe bloquearse.
     */
    data class Block(
        val target: BlockTarget,
        val actions: Set<BlockAction>,
        val policyIds: Set<String>,
        val reason: String,
    ) : EnforcementDecision
}
