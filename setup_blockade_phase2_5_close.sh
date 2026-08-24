#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup_blockade_phase2_5_close.sh
#
# Cierra la Fase 2.5 agregando los 3 tests de frontera para
# expiresAt en PolicyEvaluatorTest, según lo acordado con ChatGPT:
#
#   expiresAt == now        -> ALLOW (política inactiva)
#   expiresAt == now - 1ms  -> ALLOW (política inactiva)
#   expiresAt == now + 1ms  -> BLOCK (política todavía activa)
#
# IMPORTANTE: este script NO modifica ninguna clase de producción.
# Se verificó antes de generarlo que PolicyEvaluator.isExpired(),
# CreateQuickBlockUseCase y StopQuickBlockUseCase ya implementan
# exactamente la semántica que pide ChatGPT:
#   - expiresAt == null            -> nunca expira
#   - !now.isBefore(expiresAt)     -> política inactiva (expiresAt <= now)
#   - enabled y expiresAt son independientes (StopQuickBlockUseCase
#     solo toca setEnabled, nunca expiresAt)
#
# Por eso el único cambio real es reescribir PolicyEvaluatorTest.kt
# agregando los 3 tests de frontera. Si al correr los tests algo
# falla, es señal de que el supuesto de arriba está mal — pega la
# salida del error, no hay que adivinar un fix.
# ============================================================

REPO_ROOT="$(pwd)"
MODULE_DIR="$REPO_ROOT/blockade"
MAIN_ENGINE_DIR="$MODULE_DIR/src/main/java/com/irrovicas/blockade/domain/engine"
MAIN_MODEL_DIR="$MODULE_DIR/src/main/java/com/irrovicas/blockade/domain/model"
TEST_FILE="$MODULE_DIR/src/test/java/com/irrovicas/blockade/domain/engine/PolicyEvaluatorTest.kt"

echo "== Validando precondiciones =="

if [ ! -f "$MODULE_DIR/build.gradle.kts" ]; then
  echo "ERROR: no se encontró blockade/build.gradle.kts."
  echo "       Corre este script desde la raíz del repo (PROYECTO/)."
  exit 1
fi

if [ ! -f "$TEST_FILE" ]; then
  echo "ERROR: no se encontró $TEST_FILE"
  echo "       Este script asume que PolicyEvaluatorTest.kt ya existe (Fase 2)."
  exit 1
fi

if ! grep -q "class PolicyEvaluator" "$MAIN_ENGINE_DIR/PolicyEvaluator.kt" 2>/dev/null; then
  echo "ERROR: no se encontró la clase PolicyEvaluator en $MAIN_ENGINE_DIR/PolicyEvaluator.kt"
  exit 1
fi

if ! grep -q "expiresAt: Instant? = null" "$MAIN_MODEL_DIR/BlockadePolicy.kt" 2>/dev/null; then
  echo "ERROR: BlockadePolicy no tiene el campo 'expiresAt: Instant? = null' esperado."
  echo "       El modelo cambió respecto a lo asumido — abortando en vez de adivinar."
  exit 1
fi

if ! grep -q "private fun isExpired(" "$MAIN_ENGINE_DIR/PolicyEvaluator.kt" 2>/dev/null; then
  echo "ERROR: PolicyEvaluator no tiene el método isExpired() esperado."
  exit 1
fi

echo "OK: build.gradle.kts, PolicyEvaluatorTest.kt, PolicyEvaluator.kt y BlockadePolicy.kt encontrados."

echo "== Reescribiendo PolicyEvaluatorTest.kt (agrega 3 tests de frontera) =="

cat > "$TEST_FILE" << 'KOTLIN_EOF'
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

    @Test
    fun `policy expiring exactly now is inactive`() {
        val expired = policy().copy(expiresAt = now)

        val result = evaluator.evaluate(
            policies = listOf(expired),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `policy expired one millisecond ago is inactive`() {
        val expired = policy().copy(expiresAt = now.minusMillis(1))

        val result = evaluator.evaluate(
            policies = listOf(expired),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertEquals(EnforcementDecision.Allow, result)
    }

    @Test
    fun `policy expiring one millisecond from now is still active`() {
        val active = policy().copy(expiresAt = now.plusMillis(1))

        val result = evaluator.evaluate(
            policies = listOf(active),
            context = context(foregroundPackage = instagram.packageName),
        )

        assertIs<EnforcementDecision.Block>(result)
    }
}
KOTLIN_EOF

echo "OK: PolicyEvaluatorTest.kt reescrito con 21 tests (18 originales + 3 nuevos de frontera)."

echo ""
echo "== Corriendo ./gradlew :blockade:test =="
cd "$REPO_ROOT"
./gradlew :blockade:test

echo ""
echo "== Corriendo ./gradlew :blockade:assembleDebug =="
./gradlew :blockade:assembleDebug

echo ""
echo "== Estado en git =="
git add -A
git status --short

cat << 'MSG'

============================================================
Fase 2.5 cerrada: expiresAt tiene sus 3 tests de frontera y
todo el motor + use cases siguen verdes.

Para commitear y subir:

  git commit -m "test(blockade): agrega tests de frontera para expiresAt en PolicyEvaluator"
  git push origin <tu-rama>

Siguiente paso (Fase 2.6): Room persistence. Todavía no tengo
las instrucciones concretas (entities, converters, DAO,
RoomPolicyRepository, plan de migraciones) — mándalas cuando
las tengas y armo setup_blockade_phase2_6.sh.
============================================================
MSG
