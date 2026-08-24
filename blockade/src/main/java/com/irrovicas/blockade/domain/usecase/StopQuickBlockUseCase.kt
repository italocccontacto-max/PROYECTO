package com.irrovicas.blockade.domain.usecase

import com.irrovicas.blockade.domain.repository.PolicyRepository

/**
 * Detiene un QuickBlock en curso deshabilitando su política asociada.
 */
class StopQuickBlockUseCase(
    private val repository: PolicyRepository,
) {
    suspend fun execute(policyId: String) {
        repository.setEnabled(id = policyId, enabled = false)
    }
}
