package com.irrovicas.blockade.domain.repository

import com.irrovicas.blockade.domain.model.BlockadePolicy
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map

/**
 * Implementación en memoria de PolicyRepository.
 *
 * Sirve para probar el flujo completo (UseCase -> Repository ->
 * PolicyEvaluator) sin introducir Room todavía. No persiste entre
 * procesos: vive mientras viva la instancia.
 */
class InMemoryPolicyRepository : PolicyRepository {

    private val state = MutableStateFlow<Map<String, BlockadePolicy>>(emptyMap())

    override fun observePolicies(): Flow<List<BlockadePolicy>> {
        return state.map { it.values.toList() }
    }

    override suspend fun getPolicy(id: String): BlockadePolicy? {
        return state.value[id]
    }

    override suspend fun savePolicy(policy: BlockadePolicy) {
        state.value = state.value + (policy.id to policy)
    }

    override suspend fun deletePolicy(id: String) {
        state.value = state.value - id
    }

    override suspend fun setEnabled(id: String, enabled: Boolean) {
        updatePolicy(id) { it.copy(enabled = enabled) }
    }

    override suspend fun setPaused(id: String, paused: Boolean) {
        updatePolicy(id) { it.copy(paused = paused) }
    }

    private fun updatePolicy(
        id: String,
        transform: (BlockadePolicy) -> BlockadePolicy,
    ) {
        val current = state.value[id] ?: return
        state.value = state.value + (id to transform(current))
    }
}
