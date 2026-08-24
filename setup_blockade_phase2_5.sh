#!/usr/bin/env bash
# Fase 2.5 — InMemoryPolicyRepository + CreateQuickBlockUseCase + StopQuickBlockUseCase
# + ObservePoliciesUseCase + expiresAt en BlockadePolicy/PolicyEvaluator.
# Ejecutar desde la raíz del proyecto (donde está settings.gradle.kts)
set -euo pipefail

DOMAIN="blockade/src/main/java/com/irrovicas/blockade/domain"
TEST_DOMAIN="blockade/src/test/java/com/irrovicas/blockade/domain"

if [ ! -f settings.gradle.kts ]; then
  echo "ERROR: ejecuta esto desde la raíz del proyecto (donde está settings.gradle.kts)." >&2
  exit 1
fi

for f in "$DOMAIN/repository/PolicyRepository.kt" "$DOMAIN/model/QuickBlock.kt" "$DOMAIN/model/BlockadePolicy.kt"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: no encuentro $f. Este script asume que Fase 2 y 2b ya corrieron." >&2
    exit 1
  fi
done

echo "== Paso 1: agregando expiresAt a BlockadePolicy.kt =="
cat > "$DOMAIN/model/BlockadePolicy.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.domain.model

import java.time.Instant

/**
 * Política de enforcement normalizada.
 *
 * Puede proceder de un QuickBlock o de un Schedule.
 *
 * expiresAt es null para políticas sin vencimiento (Schedule).
 * Para QuickBlock, representa el instante en que deja de estar activa
 * sin necesidad de que nadie la deshabilite explícitamente.
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
    val expiresAt: Instant? = null,
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
KOTLIN_EOF

echo ""
echo "== Paso 2: agregando verificación de vencimiento a PolicyEvaluator.kt =="
cat > "$DOMAIN/engine/PolicyEvaluator.kt" << 'KOTLIN_EOF'
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
                !isExpired(policy, context.now) &&
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

    private fun isExpired(
        policy: BlockadePolicy,
        now: Instant,
    ): Boolean {
        val expiresAt = policy.expiresAt ?: return false
        return !now.isBefore(expiresAt)
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
echo "== Paso 3: creando InMemoryPolicyRepository.kt =="
cat > "$DOMAIN/repository/InMemoryPolicyRepository.kt" << 'KOTLIN_EOF'
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
KOTLIN_EOF

echo ""
echo "== Paso 4: creando los 3 use cases =="
mkdir -p "$DOMAIN/usecase"

cat > "$DOMAIN/usecase/CreateQuickBlockUseCase.kt" << 'KOTLIN_EOF'
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
KOTLIN_EOF

cat > "$DOMAIN/usecase/StopQuickBlockUseCase.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.domain.usecase

import com.irrovicas.blockade.domain.repository.PolicyRepository

/**
 * Detiene un QuickBlock en curso deshabilitando su política asociada.
 */
class StopQuickBlockUseCase(
    private val repository: PolicyRepository,
) {
    suspend fun execute(policyId: String) {
        repository.setEnabled(id = policyId, enabled = false)
    }
}
KOTLIN_EOF

cat > "$DOMAIN/usecase/ObservePoliciesUseCase.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.domain.usecase

import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.repository.PolicyRepository
import kotlinx.coroutines.flow.Flow

/**
 * Expone el flujo de políticas vigentes para que la UI (o el motor)
 * las observe sin conocer el mecanismo de almacenamiento.
 */
class ObservePoliciesUseCase(
    private val repository: PolicyRepository,
) {
    fun execute(): Flow<List<BlockadePolicy>> {
        return repository.observePolicies()
    }
}
KOTLIN_EOF

echo ""
echo "== Paso 5: escribiendo QuickBlockUseCaseTest.kt =="
mkdir -p "$TEST_DOMAIN/usecase"

cat > "$TEST_DOMAIN/usecase/QuickBlockUseCaseTest.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.domain.usecase

import com.irrovicas.blockade.domain.engine.EnforcementDecision
import com.irrovicas.blockade.domain.engine.PolicyEvaluationContext
import com.irrovicas.blockade.domain.engine.PolicyEvaluator
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.QuickBlock
import com.irrovicas.blockade.domain.repository.InMemoryPolicyRepository
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

class QuickBlockUseCaseTest {

    private val zoneId = ZoneId.of("America/Lima")
    private val instagram = BlockTarget.Application("com.instagram.android")
    private val startedAt = Instant.parse("2026-08-23T15:00:00Z")

    @Test
    fun `create quick block is observed and blocks target`() = runBlocking {
        val repository = InMemoryPolicyRepository()
        val create = CreateQuickBlockUseCase(repository)
        val observe = ObservePoliciesUseCase(repository)

        create.execute(
            QuickBlock(
                id = "quick-1",
                startedAt = startedAt,
                expiresAt = startedAt.plus(Duration.ofMinutes(30)),
                targets = setOf(instagram),
                actions = setOf(BlockAction.LAUNCH),
            ),
        )

        val policies = observe.execute().first()
        assertEquals(1, policies.size)

        val decision = PolicyEvaluator().evaluate(
            policies = policies,
            context = PolicyEvaluationContext(
                now = startedAt,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
            ),
        )

        assertIs<EnforcementDecision.Block>(decision)
    }

    @Test
    fun `stop quick block disables and allows access`() = runBlocking {
        val repository = InMemoryPolicyRepository()
        val create = CreateQuickBlockUseCase(repository)
        val stop = StopQuickBlockUseCase(repository)
        val observe = ObservePoliciesUseCase(repository)

        val created = create.execute(
            QuickBlock(
                id = "quick-2",
                startedAt = startedAt,
                expiresAt = null,
                targets = setOf(instagram),
            ),
        )

        stop.execute(created.id)

        val policies = observe.execute().first()

        val decision = PolicyEvaluator().evaluate(
            policies = policies,
            context = PolicyEvaluationContext(
                now = startedAt,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
            ),
        )

        assertEquals(EnforcementDecision.Allow, decision)
    }

    @Test
    fun `expired quick block does not block`() = runBlocking {
        val repository = InMemoryPolicyRepository()
        val create = CreateQuickBlockUseCase(repository)
        val observe = ObservePoliciesUseCase(repository)

        create.execute(
            QuickBlock(
                id = "quick-3",
                startedAt = startedAt,
                expiresAt = startedAt.plus(Duration.ofMinutes(10)),
                targets = setOf(instagram),
            ),
        )

        val policies = observe.execute().first()

        val afterExpiry = startedAt.plus(Duration.ofMinutes(11))

        val decision = PolicyEvaluator().evaluate(
            policies = policies,
            context = PolicyEvaluationContext(
                now = afterExpiry,
                zoneId = zoneId,
                foregroundApplicationPackage = instagram.packageName,
            ),
        )

        assertEquals(EnforcementDecision.Allow, decision)
    }

    @Test
    fun `saved quick block persists and can be retrieved`() = runBlocking {
        val repository = InMemoryPolicyRepository()
        val create = CreateQuickBlockUseCase(repository)

        val created = create.execute(
            QuickBlock(
                id = "quick-4",
                startedAt = startedAt,
                expiresAt = startedAt.plus(Duration.ofMinutes(15)),
                targets = setOf(instagram),
            ),
        )

        val fetched = assertNotNull(repository.getPolicy("quick-4"))

        assertEquals(created.id, fetched.id)
        assertEquals(created.expiresAt, fetched.expiresAt)
    }
}
KOTLIN_EOF

echo ""
echo "== Paso 6: tests + build (por módulo) =="
./gradlew :blockade:test
./gradlew :blockade:assembleDebug

echo ""
echo "== Paso 7: dejando todo listo para commit =="
git add -A
git status --short

echo ""
echo "Listo. Revisa 'git diff --staged' y cuando estés conforme:"
echo "  git commit -m \"blockade: fase 2.5 - InMemoryPolicyRepository, QuickBlock use cases, expiresAt en BlockadePolicy\""
echo "  git push"
