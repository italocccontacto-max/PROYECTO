package com.irrovicas.blockade.domain.model

import java.time.Instant

/**
 * Horario persistente de BLOCKADE.
 *
 * Un Schedule agrupa objetivos + condiciones + acciones.
 */
data class Schedule(
    val id: String,
    val name: String,
    val enabled: Boolean = true,
    val paused: Boolean = false,
    val targets: Set<BlockTarget>,
    val conditions: List<BlockCondition>,
    val actions: Set<BlockAction> = setOf(BlockAction.LAUNCH),
    val conditionMode: ConditionMode = ConditionMode.ALL,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
)

enum class ConditionMode {
    /**
     * Todas las condiciones deben cumplirse.
     *
     * Ejemplo:
     * 09:00-12:00 + Wi-Fi de la escuela.
     */
    ALL,

    /**
     * Basta con que una condición se cumpla.
     */
    ANY,
}
