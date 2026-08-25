package com.irrovicas.blockade.platform.enforcement

import com.irrovicas.blockade.domain.engine.EnforcementDecision

/**
 * Mecanismo Android que hace efectiva una decision de bloqueo.
 *
 * El "que" ya lo respondio PolicyEvaluator (ver EnforcementDecision).
 * Esta interfaz responde el "como": que hace el dispositivo cuando
 * hay que bloquear.
 */
interface BlockEnforcer {

    fun enforce(decision: EnforcementDecision.Block)
}
