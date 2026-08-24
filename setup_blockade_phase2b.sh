#!/usr/bin/env bash
# Fase 2b — corrige TimeWindow (cruce de medianoche) y agrega los 5 tests
# que pidió ChatGPT: medianoche, wifi match, wifi distinto, ALL, ANY.
# Ejecutar desde la raíz del proyecto (donde está settings.gradle.kts)
set -euo pipefail

ENGINE_MAIN="blockade/src/main/java/com/irrovicas/blockade/domain/engine/PolicyEvaluator.kt"
ENGINE_TEST="blockade/src/test/java/com/irrovicas/blockade/domain/engine/PolicyEvaluatorTest.kt"

if [ ! -f settings.gradle.kts ]; then
  echo "ERROR: ejecuta esto desde la raíz del proyecto (donde está settings.gradle.kts)." >&2
  exit 1
fi

if [ ! -f "$ENGINE_MAIN" ] || [ ! -f "$ENGINE_TEST" ]; then
  echo "ERROR: no encuentro $ENGINE_MAIN o $ENGINE_TEST." >&2
  echo "Este script asume que ya corriste setup_blockade_phase2.sh antes." >&2
  exit 1
fi

echo "== Paso 1: corrigiendo timeWindowMatches en PolicyEvaluator.kt =="
cat > "$ENGINE_MAIN" << 'KOTLIN_EOF'
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

        val crossesMidnight = condition.startTime > condition.endTime

        if (!crossesMidnight) {
            return currentDay in condition.daysOfWeek &&
                currentTime >= condition.startTime &&
                currentTime < condition.endTime
        }

        // La ventana empieza un día y termina al día siguiente.
        // daysOfWeek se interpreta como el día en que ARRANCA la ventana,
        // así que la porción posterior a medianoche pertenece al día
        // anterior al actual.
        val startsToday = currentDay in condition.daysOfWeek &&
            currentTime >= condition.startTime

        val continuesFromYesterday = currentDay.minus(1) in condition.daysOfWeek &&
            currentTime < condition.endTime

        return startsToday || continuesFromYesterday
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
KOTLIN_EOF

echo ""
echo "== Paso 2: agregando los 5 tests nuevos a PolicyEvaluatorTest.kt =="
cat > "$ENGINE_TEST" << 'KOTLIN_EOF'
package com.irrovicas.blockade.domain.engine

import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockCondition
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.ConditionMode
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.StrictnessLevel
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

class PolicyEvaluatorTest {

    private val evaluator = PolicyEvaluator()

    private val zoneId = ZoneId.of("America/Lima")

    private val now = Instant.parse("2026-08-23T15:00:00Z")

    private val instagram =
        BlockTarget.Application("com.instagram.android")

    private fun context(
        foregroundPackage: String? = null,
        url: String? = null,
        domain: String? = null,
        dailyUsage: Map<String, Long> = emptyMap(),
        launchCount: Map<String, Int> = emptyMap(),
    ): PolicyEvaluationContext {
        return PolicyEvaluationContext(
            now = now,
            zoneId = zoneId,
            foregroundApplicationPackage = foregroundPackage,
            currentUrl = url,
            currentWebDomain = domain,
            dailyUsageMinutesByPackage = dailyUsage,
            launchCountByPackage = launchCount,
        )
    }

    private fun policy(
        id: String = "policy-1",
        target: BlockTarget = instagram,
        conditions: List<BlockCondition> = emptyList(),
        strictness: StrictnessLevel = StrictnessLevel.NORMAL,
    ): BlockadePolicy {
        return BlockadePolicy(
            id = id,
            name = id,
            source = PolicySource.QUICK_BLOCK,
            enabled = true,
            paused = false,
            targets = setOf(target),
            conditions = conditions,
            actions = setOf(BlockAction.LAUNCH),
            conditionMode = ConditionMode.ALL,
            strictness = strictness,
        )
    }

    @Test
    fun `no policies allows access`() {
        val result = evaluator.evaluate(
            policies = emptyList(),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `matching application policy blocks`() {
        val result = evaluator.evaluate(
            policies = listOf(policy()),
            context = context(foregroundPackage = instagram.packageName),
        )

        val block = assertIs<EnforcementDecision.Block>(result)

        assertEquals(instagram, block.target)
        assertEquals(setOf("policy-1"), block.policyIds)
        assertEquals(setOf(BlockAction.LAUNCH), block.actions)
    }

    @Test
    fun `different application is allowed`() {
        val result = evaluator.evaluate(
            policies = listOf(policy()),
            context = context(
                foregroundPackage = "com.example.other",
            ),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `disabled policy is ignored`() {
        val disabled = policy().copy(enabled = false)

        val result = evaluator.evaluate(
            policies = listOf(disabled),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `paused policy is ignored`() {
        val paused = policy().copy(paused = true)

        val result = evaluator.evaluate(
            policies = listOf(paused),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `active time window blocks`() {
        val condition = BlockCondition.TimeWindow(
            startTime = LocalTime.of(8, 0),
            endTime = LocalTime.of(23, 0),
            daysOfWeek = setOf(DayOfWeek.SUNDAY),
        )

        val result = evaluator.evaluate(
            policies = listOf(policy(conditions = listOf(condition))),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `inactive time window allows`() {
        val condition = BlockCondition.TimeWindow(
            startTime = LocalTime.of(18, 0),
            endTime = LocalTime.of(23, 0),
            daysOfWeek = setOf(DayOfWeek.SUNDAY),
        )

        val result = evaluator.evaluate(
            policies = listOf(policy(conditions = listOf(condition))),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `usage limit blocks when threshold is reached`() {
        val condition = BlockCondition.UsageLimit(
            limitMinutes = 30,
        )

        val result = evaluator.evaluate(
            policies = listOf(policy(conditions = listOf(condition))),
            context = context(
                foregroundPackage = instagram.packageName,
                dailyUsage = mapOf(instagram.packageName to 30),
            ),
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `usage limit allows below threshold`() {
        val condition = BlockCondition.UsageLimit(
            limitMinutes = 30,
        )

        val result = evaluator.evaluate(
            policies = listOf(policy(conditions = listOf(condition))),
            context = context(
                foregroundPackage = instagram.packageName,
                dailyUsage = mapOf(instagram.packageName to 29),
            ),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `launch limit blocks at threshold`() {
        val condition = BlockCondition.LaunchCount(
            maximumLaunches = 5,
        )

        val result = evaluator.evaluate(
            policies = listOf(policy(conditions = listOf(condition))),
            context = context(
                foregroundPackage = instagram.packageName,
                launchCount = mapOf(instagram.packageName to 5),
            ),
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `domain keyword blocks matching domain`() {
        val target = BlockTarget.Keyword(
            value = "game",
            matchingMode =
                com.irrovicas.blockade.domain.model.KeywordMatchingMode.DOMAIN,
        )

        val result = evaluator.evaluate(
            policies = listOf(
                policy(target = target),
            ),
            context = context(
                domain = "store.epicgame.com",
            ),
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `url keyword blocks anywhere in url`() {
        val target = BlockTarget.Keyword(
            value = "reels",
            matchingMode =
                com.irrovicas.blockade.domain.model.KeywordMatchingMode.URL_ANYWHERE,
        )

        val result = evaluator.evaluate(
            policies = listOf(
                policy(target = target),
            ),
            context = context(
                url = "https://example.com/videos/reels/123",
            ),
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `outside location condition works`() {
        val condition = BlockCondition.Location(
            latitude = -12.0464,
            longitude = -77.0428,
            radiusMeters = 100f,
            mode =
                com.irrovicas.blockade.domain.model.LocationMode.OUTSIDE,
        )

        val result = evaluator.evaluate(
            policies = listOf(policy(conditions = listOf(condition))),
            context = PolicyEvaluationContext(
                now = now,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
                currentLatitude = -12.10,
                currentLongitude = -77.10,
            ),
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `time window crossing midnight blocks after midnight`() {
        val condition = BlockCondition.TimeWindow(
            startTime = LocalTime.of(22, 0),
            endTime = LocalTime.of(2, 0),
            daysOfWeek = setOf(DayOfWeek.SUNDAY),
        )

        val context = PolicyEvaluationContext(
            now = Instant.parse("2026-08-24T06:00:00Z"),
            zoneId = zoneId,
            foregroundApplicationPackage = instagram.packageName,
        )

        val result = evaluator.evaluate(
            policies = listOf(
                policy(conditions = listOf(condition)),
            ),
            context = context,
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `wifi matching condition blocks`() {
        val condition = BlockCondition.Wifi(
            ssid = "IRROVICAS-HOME",
        )

        val result = evaluator.evaluate(
            policies = listOf(
                policy(conditions = listOf(condition)),
            ),
            context = PolicyEvaluationContext(
                now = now,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
                currentWifiSsid = "IRROVICAS-HOME",
            ),
        )

        assertIs<EnforcementDecision.Block>(result)
    }

    @Test
    fun `different wifi allows access`() {
        val condition = BlockCondition.Wifi(
            ssid = "IRROVICAS-HOME",
        )

        val result = evaluator.evaluate(
            policies = listOf(
                policy(conditions = listOf(condition)),
            ),
            context = PolicyEvaluationContext(
                now = now,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
                currentWifiSsid = "OTHER-NETWORK",
            ),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `all conditions require every condition to match`() {
        val timeCondition = BlockCondition.TimeWindow(
            startTime = LocalTime.of(8, 0),
            endTime = LocalTime.of(23, 0),
            daysOfWeek = setOf(DayOfWeek.SUNDAY),
        )

        val wifiCondition = BlockCondition.Wifi(
            ssid = "IRROVICAS-HOME",
        )

        val result = evaluator.evaluate(
            policies = listOf(
                policy(
                    conditions = listOf(
                        timeCondition,
                        wifiCondition,
                    ),
                    strictness = StrictnessLevel.NORMAL,
                ),
            ),
            context = PolicyEvaluationContext(
                now = now,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
                currentWifiSsid = "OTHER-NETWORK",
            ),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `any condition can activate the policy`() {
        val timeCondition = BlockCondition.TimeWindow(
            startTime = LocalTime.of(8, 0),
            endTime = LocalTime.of(23, 0),
            daysOfWeek = setOf(DayOfWeek.SUNDAY),
        )

        val wifiCondition = BlockCondition.Wifi(
            ssid = "DIFFERENT-NETWORK",
        )

        val anyPolicy = policy(
            conditions = listOf(
                timeCondition,
                wifiCondition,
            ),
        ).copy(
            conditionMode = ConditionMode.ANY,
        )

        val result = evaluator.evaluate(
            policies = listOf(anyPolicy),
            context = PolicyEvaluationContext(
                now = now,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
                currentWifiSsid = "IRROVICAS-HOME",
            ),
        )

        assertIs<EnforcementDecision.Block>(result)
    }
}
KOTLIN_EOF

echo ""
echo "== Paso 3: tests + build (por módulo, para no reventar el daemon) =="
./gradlew :blockade:test
./gradlew :blockade:assembleDebug

echo ""
echo "== Paso 4: dejando todo listo para commit =="
git add -A
git status --short

echo ""
echo "Listo. Revisa 'git diff --staged' y cuando estés conforme:"
echo "  git commit -m \"blockade: corrige cruce de medianoche en TimeWindow, agrega tests de wifi/ALL/ANY\""
echo "  git push"
