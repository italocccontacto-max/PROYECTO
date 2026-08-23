package com.irrovicas.blockade.domain.model

/**
 * Política de enforcement normalizada.
 *
 * Puede proceder de un QuickBlock o de un Schedule.
 */
data class BlockadePolicy(
    val id: String,
    val name: String,
    val source: PolicySource,
    val enabled: Boolean,
    val paused: Boolean,
    val targets: Set<BlockTarget>,
    val conditions: List<BlockCondition>,
    val actions: Set<BlockAction>,
    val conditionMode: ConditionMode = ConditionMode.ALL,
    val strictness: StrictnessLevel = StrictnessLevel.NORMAL,
)

enum class PolicySource {
    QUICK_BLOCK,
    SCHEDULE,
    SYSTEM,
}

/**
 * Nivel semántico de restricción.
 *
 * Cuanto mayor sea el nivel, más estricta es la política.
 */
enum class StrictnessLevel {
    NORMAL,
    STRICT,
    ABSOLUTE,
}
