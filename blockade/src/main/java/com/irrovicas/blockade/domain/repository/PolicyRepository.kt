package com.irrovicas.blockade.domain.repository

import com.irrovicas.blockade.domain.model.BlockadePolicy
import kotlinx.coroutines.flow.Flow

/**
 * Contrato del repositorio de políticas.
 *
 * El dominio no conoce si la implementación utiliza Room,
 * memoria, backup local o cualquier otro mecanismo.
 */
interface PolicyRepository {

    fun observePolicies(): Flow<List<BlockadePolicy>>

    suspend fun getPolicy(
        id: String,
    ): BlockadePolicy?

    suspend fun savePolicy(
        policy: BlockadePolicy,
    )

    suspend fun deletePolicy(
        id: String,
    )

    suspend fun setEnabled(
        id: String,
        enabled: Boolean,
    )

    suspend fun setPaused(
        id: String,
        paused: Boolean,
    )
}
