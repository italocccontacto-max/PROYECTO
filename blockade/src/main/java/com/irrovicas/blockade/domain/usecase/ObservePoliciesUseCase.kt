package com.irrovicas.blockade.domain.usecase

import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.repository.PolicyRepository
import kotlinx.coroutines.flow.Flow

/**
 * Expone el flujo de políticas vigentes para que la UI (o el motor)
 * las observe sin conocer el mecanismo de almacenamiento.
 */
class ObservePoliciesUseCase(
    private val repository: PolicyRepository,
) {
    fun execute(): Flow<List<BlockadePolicy>> {
        return repository.observePolicies()
    }
}
