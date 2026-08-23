package com.irrovicas.blockade.domain.engine

import com.irrovicas.blockade.domain.model.BlockCondition
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.ConditionMode
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId

/**
 * Contexto observable por el motor.
 *
 * Los adaptadores Android rellenarán posteriormente este objeto
 * usando las APIs reales del sistema.
 */
data class PolicyEvaluationContext(
    val now: Instant,
    val zoneId: ZoneId,
    val foregroundApplicationPackage: String? = null,
    val currentWebDomain: String? = null,
    val currentUrl: String? = null,
    val currentAppContent: BlockTarget.AppContent? = null,
    val dailyUsageMinutesByPackage: Map<String, Long> = emptyMap(),
    val launchCountByPackage: Map<String, Int> = emptyMap(),
    val currentLatitude: Double? = null,
    val currentLongitude: Double? = null,
    val currentWifiSsid: String? = null,
)

/**
 * Evalúa políticas puras de dominio.
 */
class PolicyEvaluator {

    /**
     * Devuelve la decisión efectiva frente a un objetivo actual.
     */
    fun evaluate(
        policies: Collection<BlockadePolicy>,
        context: PolicyEvaluationContext,
    ): EnforcementDecision {
        val activePolicies = policies.filter { policy ->
            policy.enabled &&
                !policy.paused &&
                policyConditionsMatch(policy, context)
        }

        val matchingPolicies = activePolicies.filter { policy ->
            policyTargetsMatch(policy, context)
        }

        if (matchingPolicies.isEmpty()) {
            return EnforcementDecision.Allow
        }

        val strictestPolicy = matchingPolicies.maxByOrNull {
            it.strictness.ordinal
        } ?: return EnforcementDecision.Allow

        val actions = matchingPolicies
            .flatMap { it.actions }
            .toSet()

        return EnforcementDecision.Block(
            target = resolveCurrentTarget(strictestPolicy, context),
            actions = actions,
            policyIds = matchingPolicies.map { it.id }.toSet(),
            reason = buildReason(matchingPolicies),
        )
    }

    private fun policyTargetsMatch(
        policy: BlockadePolicy,
        context: PolicyEvaluationContext,
    ): Boolean {
        return policy.targets.any { target ->
            targetMatchesContext(target, context)
        }
    }

    private fun targetMatchesContext(
        target: BlockTarget,
        context: PolicyEvaluationContext,
    ): Boolean {
        return when (target) {
            is BlockTarget.Application ->
                target.packageName == context.foregroundApplicationPackage

            is BlockTarget.WebDomain ->
                target.domain.equals(
                    context.currentWebDomain,
                    ignoreCase = true,
                )

            is BlockTarget.Keyword ->
                when (target.matchingMode) {
                    com.irrovicas.blockade.domain.model.KeywordMatchingMode.DOMAIN ->
                        context.currentWebDomain?.contains(target.value, ignoreCase = true) == true

                    com.irrovicas.blockade.domain.model.KeywordMatchingMode.URL_ANYWHERE ->
                        context.currentUrl?.contains(target.value, ignoreCase = true) == true
                }

            is BlockTarget.AppContent ->
                target == context.currentAppContent
        }
    }

    private fun resolveCurrentTarget(
        policy: BlockadePolicy,
        context: PolicyEvaluationContext,
    ): BlockTarget {
        return policy.targets.firstOrNull { target ->
            targetMatchesContext(target, context)
        } ?: policy.targets.first()
    }

    private fun policyConditionsMatch(
        policy: BlockadePolicy,
        context: PolicyEvaluationContext,
    ): Boolean {
        if (policy.conditions.isEmpty()) {
            return true
        }

        return when (policy.conditionMode) {
            ConditionMode.ALL ->
                policy.conditions.all { condition ->
                    conditionMatches(condition, policy, context)
                }

            ConditionMode.ANY ->
                policy.conditions.any { condition ->
                    conditionMatches(condition, policy, context)
                }
        }
    }

    private fun conditionMatches(
        condition: BlockCondition,
        policy: BlockadePolicy,
        context: PolicyEvaluationContext,
    ): Boolean {
        return when (condition) {
            is BlockCondition.TimeWindow ->
                timeWindowMatches(condition, context)

            is BlockCondition.UsageLimit ->
                usageLimitReached(condition, policy, context)

            is BlockCondition.LaunchCount ->
                launchLimitReached(condition, policy, context)

            is BlockCondition.Location ->
                locationMatches(condition, context)

            is BlockCondition.Wifi ->
                wifiMatches(condition, context)
        }
    }

    private fun timeWindowMatches(
        condition: BlockCondition.TimeWindow,
        context: PolicyEvaluationContext,
    ): Boolean {
        val localDateTime =
            LocalDateTime.ofInstant(context.now, context.zoneId)

        val currentDay = localDateTime.dayOfWeek
        val currentTime = localDateTime.toLocalTime()

        if (currentDay !in condition.daysOfWeek) {
            return false
        }

        return if (condition.startTime <= condition.endTime) {
            currentTime >= condition.startTime &&
                currentTime < condition.endTime
        } else {
            currentTime >= condition.startTime ||
                currentTime < condition.endTime
        }
    }

    private fun usageLimitReached(
        condition: BlockCondition.UsageLimit,
        policy: BlockadePolicy,
        context: PolicyEvaluationContext,
    ): Boolean {
        val usageMinutes = policy.targets
            .filterIsInstance<BlockTarget.Application>()
            .sumOf { target ->
                context.dailyUsageMinutesByPackage[target.packageName] ?: 0L
            }

        return usageMinutes >= condition.limitMinutes
    }

    private fun launchLimitReached(
        condition: BlockCondition.LaunchCount,
        policy: BlockadePolicy,
        context: PolicyEvaluationContext,
    ): Boolean {
        val launchCount = policy.targets
            .filterIsInstance<BlockTarget.Application>()
            .sumOf { target ->
                context.launchCountByPackage[target.packageName] ?: 0
            }

        return launchCount >= condition.maximumLaunches
    }

    private fun locationMatches(
        condition: BlockCondition.Location,
        context: PolicyEvaluationContext,
    ): Boolean {
        val latitude = context.currentLatitude ?: return false
        val longitude = context.currentLongitude ?: return false

        val distanceMeters = haversineDistanceMeters(
            latitude1 = latitude,
            longitude1 = longitude,
            latitude2 = condition.latitude,
            longitude2 = condition.longitude,
        )

        val inside = distanceMeters <= condition.radiusMeters

        return when (condition.mode) {
            com.irrovicas.blockade.domain.model.LocationMode.INSIDE ->
                inside

            com.irrovicas.blockade.domain.model.LocationMode.OUTSIDE ->
                !inside
        }
    }

    private fun wifiMatches(
        condition: BlockCondition.Wifi,
        context: PolicyEvaluationContext,
    ): Boolean {
        return condition.ssid == context.currentWifiSsid
    }

    private fun haversineDistanceMeters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double,
    ): Double {
        val earthRadiusMeters = 6_371_000.0

        val lat1 = Math.toRadians(latitude1)
        val lat2 = Math.toRadians(latitude2)
        val deltaLat = Math.toRadians(latitude2 - latitude1)
        val deltaLon = Math.toRadians(longitude2 - longitude1)

        val a =
            kotlin.math.sin(deltaLat / 2).let { sinLat ->
                sinLat * sinLat
            } +
                kotlin.math.cos(lat1) *
                kotlin.math.cos(lat2) *
                kotlin.math.sin(deltaLon / 2).let { sinLon ->
                    sinLon * sinLon
                }

        val c = 2 * kotlin.math.atan2(
            kotlin.math.sqrt(a),
            kotlin.math.sqrt(1 - a),
        )

        return earthRadiusMeters * c
    }

    private fun buildReason(
        policies: Collection<BlockadePolicy>,
    ): String {
        return policies.joinToString(
            separator = ", ",
            prefix = "Bloqueado por: ",
        ) { it.name }
    }
}
