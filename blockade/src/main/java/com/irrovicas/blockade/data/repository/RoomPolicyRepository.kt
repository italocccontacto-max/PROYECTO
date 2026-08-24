package com.irrovicas.blockade.data.repository

import com.irrovicas.blockade.data.local.dao.PolicyDao
import com.irrovicas.blockade.data.local.mapper.PolicyEntityMapper
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.repository.PolicyRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class RoomPolicyRepository(
    private val dao: PolicyDao,
) : PolicyRepository {

    override fun observePolicies(): Flow<List<BlockadePolicy>> {
        return dao.observePolicies()
            .map { policies ->
                policies.map(PolicyEntityMapper::toDomain)
            }
    }

    override suspend fun getPolicy(
        id: String,
    ): BlockadePolicy? {
        return dao.getPolicy(id)
            ?.let(PolicyEntityMapper::toDomain)
    }

    override suspend fun savePolicy(
        policy: BlockadePolicy,
    ) {
        val persisted = PolicyEntityMapper.toEntities(policy)

        dao.replacePolicy(
            policy = persisted.policy,
            targets = persisted.targets,
            conditions = persisted.conditions,
            actions = persisted.actions,
        )
    }

    override suspend fun deletePolicy(
        id: String,
    ) {
        dao.deletePolicyAndChildren(id)
    }

    override suspend fun setEnabled(
        id: String,
        enabled: Boolean,
    ) {
        dao.setEnabled(
            id = id,
            enabled = enabled,
        )
    }

    override suspend fun setPaused(
        id: String,
        paused: Boolean,
    ) {
        dao.setPaused(
            id = id,
            paused = paused,
        )
    }
}
