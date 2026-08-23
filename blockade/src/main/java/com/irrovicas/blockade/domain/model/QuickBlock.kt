package com.irrovicas.blockade.domain.model

import java.time.Instant

/**
 * Bloqueo temporal iniciado manualmente por el usuario.
 */
data class QuickBlock(
    val id: String,
    val enabled: Boolean = true,
    val startedAt: Instant,
    val expiresAt: Instant?,
    val targets: Set<BlockTarget>,
    val actions: Set<BlockAction> = setOf(BlockAction.LAUNCH),
    val pomodoro: PomodoroConfig? = null,
)

/**
 * Configuración opcional de Pomodoro.
 */
data class PomodoroConfig(
    val focusMinutes: Int = 25,
    val shortBreakMinutes: Int = 5,
    val longBreakMinutes: Int = 15,
    val cyclesBeforeLongBreak: Int = 4,
)
