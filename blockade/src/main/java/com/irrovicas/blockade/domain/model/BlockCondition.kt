package com.irrovicas.blockade.domain.model

import java.time.DayOfWeek
import java.time.LocalTime

/**
 * Condiciones que determinan cuándo una política está activa.
 */
sealed interface BlockCondition {

    /**
     * Condición por hora y días de la semana.
     *
     * endTime puede ser anterior a startTime para representar
     * un intervalo que atraviesa medianoche.
     */
    data class TimeWindow(
        val startTime: LocalTime,
        val endTime: LocalTime,
        val daysOfWeek: Set<DayOfWeek>,
    ) : BlockCondition

    /**
     * Condición por tiempo de uso acumulado.
     *
     * usageLimitMinutes representa el límite permitido.
     */
    data class UsageLimit(
        val limitMinutes: Long,
        val scope: UsageScope = UsageScope.DAILY,
    ) : BlockCondition

    /**
     * Condición por número de aperturas.
     */
    data class LaunchCount(
        val maximumLaunches: Int,
        val scope: UsageScope = UsageScope.DAILY,
    ) : BlockCondition

    /**
     * Condición por ubicación.
     *
     * La evaluación real de distancia queda fuera del dominio.
     * Aquí solo definimos la intención.
     */
    data class Location(
        val latitude: Double,
        val longitude: Double,
        val radiusMeters: Float,
        val mode: LocationMode = LocationMode.INSIDE,
    ) : BlockCondition

    /**
     * Condición por red Wi-Fi.
     */
    data class Wifi(
        val ssid: String,
    ) : BlockCondition
}

enum class UsageScope {
    DAILY,
    SCHEDULE_WINDOW,
}

enum class LocationMode {
    INSIDE,
    OUTSIDE,
}
