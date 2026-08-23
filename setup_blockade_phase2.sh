#!/usr/bin/env bash
# Fase 2 — IRROVICAS BLOCKADE: limpieza del modelo viejo + tests de PolicyEvaluator/ConflictResolver
# Ejecutar desde la raíz del proyecto (donde está settings.gradle.kts)
set -euo pipefail

DOMAIN="blockade/src/main/java/com/irrovicas/blockade/domain"
OLD_POLICY="$DOMAIN/Policy.kt"
OLD_TEST="blockade/src/test/java/com/irrovicas/blockade/domain/PolicyTest.kt"
ENGINE_TEST_DIR="blockade/src/test/java/com/irrovicas/blockade/domain/engine"

if [ ! -f settings.gradle.kts ]; then
  echo "ERROR: ejecuta esto desde la raíz del proyecto (donde está settings.gradle.kts)." >&2
  exit 1
fi

echo "== Paso 0: verificando que el dominio nuevo ya exista =="
REQUIRED=(
  "$DOMAIN/model"
  "$DOMAIN/engine/PolicyEvaluator.kt"
  "$DOMAIN/engine/ConflictResolver.kt"
)
MISSING=0
for path in "${REQUIRED[@]}"; do
  if [ ! -e "$path" ]; then
    echo "  FALTA: $path"
    MISSING=1
  fi
done
if [ "$MISSING" -eq 1 ]; then
  echo ""
  echo "No encuentro el dominio nuevo (domain/model, PolicyEvaluator, ConflictResolver) en este checkout."
  echo "Este script solo limpia y corre tests; no puede compilar si ese código no existe todavía aquí."
  echo "Verifica que estás parado sobre el checkout que SÍ tiene ese trabajo (local o Codespace), no uno recién clonado de GitHub."
  exit 1
fi
echo "  OK: dominio nuevo presente."

echo ""
echo "== Paso 1: revisando usos de Policy.kt (modelo viejo) =="
if [ -f "$OLD_POLICY" ]; then
  MATCHES=$(grep -RIl "com\.irrovicas\.blockade\.domain\.BlockadePolicy\|BlockadePolicy(" \
    blockade/src/main blockade/src/test --include="*.kt" 2>/dev/null | grep -v "^$OLD_POLICY\$" || true)

  if [ -z "$MATCHES" ]; then
    echo "  Sin usos externos -> elimino Policy.kt"
    rm -f "$OLD_POLICY"
  elif [ "$MATCHES" = "$OLD_TEST" ]; then
    echo "  Único uso: $OLD_TEST (test del modelo viejo, ya cubierto por PolicyEvaluatorTest.kt)"
    echo "  Elimino Policy.kt y PolicyTest.kt juntos"
    rm -f "$OLD_POLICY" "$OLD_TEST"
  else
    echo "  Hay otros archivos usando el modelo viejo. Revísalos a mano antes de seguir:"
    echo "$MATCHES"
    exit 1
  fi
else
  echo "  Policy.kt ya no existe, nada que hacer."
fi

echo ""
echo "== Paso 2: creando carpeta de tests del engine =="
mkdir -p "$ENGINE_TEST_DIR"

echo ""
echo "== Paso 3: escribiendo PolicyEvaluatorTest.kt =="
cat > "$ENGINE_TEST_DIR/PolicyEvaluatorTest.kt" << 'KOTLIN_EOF'
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
}
KOTLIN_EOF

echo ""
echo "== Paso 4: escribiendo ConflictResolverTest.kt =="
cat > "$ENGINE_TEST_DIR/ConflictResolverTest.kt" << 'KOTLIN_EOF'
package com.irrovicas.blockade.domain.engine

import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.StrictnessLevel
import kotlin.test.Test
import kotlin.test.assertEquals

class ConflictResolverTest {

    private val resolver = ConflictResolver()

    private val instagram =
        BlockTarget.Application("com.instagram.android")

    private fun policy(
        id: String,
        strictness: StrictnessLevel,
        actions: Set<BlockAction> =
            setOf(BlockAction.LAUNCH),
    ) = BlockadePolicy(
        id = id,
        name = id,
        source = PolicySource.SCHEDULE,
        enabled = true,
        paused = false,
        targets = setOf(instagram),
        conditions = emptyList(),
        actions = actions,
        strictness = strictness,
    )

    @Test
    fun `strict policy wins over normal policy`() {
        val normal = policy(
            id = "normal",
            strictness = StrictnessLevel.NORMAL,
        )

        val strict = policy(
            id = "strict",
            strictness = StrictnessLevel.STRICT,
        )

        val result = resolver.resolve(
            listOf(normal, strict),
        )

        assertEquals("strict", result?.id)
    }

    @Test
    fun `absolute policy wins over strict policy`() {
        val strict = policy(
            id = "strict",
            strictness = StrictnessLevel.STRICT,
        )

        val absolute = policy(
            id = "absolute",
            strictness = StrictnessLevel.ABSOLUTE,
        )

        val result = resolver.resolve(
            listOf(strict, absolute),
        )

        assertEquals("absolute", result?.id)
    }

    @Test
    fun `full action wins over launch`() {
        val launch = policy(
            id = "launch",
            strictness = StrictnessLevel.NORMAL,
            actions = setOf(BlockAction.LAUNCH),
        )

        val full = policy(
            id = "full",
            strictness = StrictnessLevel.NORMAL,
            actions = setOf(BlockAction.FULL),
        )

        val result = resolver.resolve(
            listOf(launch, full),
        )

        assertEquals("full", result?.id)
    }

    @Test
    fun `actions from all active policies are merged`() {
        val launch = policy(
            id = "launch",
            strictness = StrictnessLevel.NORMAL,
            actions = setOf(BlockAction.LAUNCH),
        )

        val notification = policy(
            id = "notification",
            strictness = StrictnessLevel.NORMAL,
            actions = setOf(BlockAction.NOTIFICATION),
        )

        val result = resolver.resolveActions(
            listOf(launch, notification),
        )

        assertEquals(
            setOf(
                BlockAction.LAUNCH,
                BlockAction.NOTIFICATION,
            ),
            result,
        )
    }
}
KOTLIN_EOF

echo ""
echo "== Paso 5: build + tests =="
./gradlew :blockade:test
./gradlew :blockade:assembleDebug
./gradlew :system:assembleDebug :blockade:assembleDebug :metrics:assembleDebug

echo ""
echo "== Paso 6: dejando todo listo para commit =="
git add -A
git status --short

echo ""
echo "Listo. Fase 2 verificada: modelo viejo eliminado, engine probado, los tres módulos compilan."
echo "Cambios en stage (aún no commiteados). Revisa 'git diff --staged' y cuando estés conforme:"
echo "  git commit -m \"blockade: fase 2 - PolicyEvaluator + ConflictResolver con tests, elimina modelo viejo\""
echo "  git push"
