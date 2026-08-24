package com.irrovicas.blockade.domain.usecase

import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.ConditionMode
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.QuickBlock
import com.irrovicas.blockade.domain.model.StrictnessLevel
import com.irrovicas.blockade.domain.repository.PolicyRepository

/**
 * Traduce un QuickBlock (intención del usuario) a la BlockadePolicy
 * que consume el motor, y la persiste.
 *
 * Este es el primer punto donde la UI deja de construir
 * BlockadePolicy directamente: solo construye un QuickBlock.
 */
class CreateQuickBlockUseCase(
    private val repository: PolicyRepository,
) {
    suspend fun execute(quickBlock: QuickBlock): BlockadePolicy {
        val policy = BlockadePolicy(
            id = quickBlock.id,
            name = "Quick Block",
            source = PolicySource.QUICK_BLOCK,
            enabled = quickBlock.enabled,
            paused = false,
            targets = quickBlock.targets,
            conditions = emptyList(),
            actions = quickBlock.actions,
            conditionMode = ConditionMode.ALL,
            strictness = StrictnessLevel.NORMAL,
            expiresAt = quickBlock.expiresAt,
        )

        repository.savePolicy(policy)

        return policy
    }
}
