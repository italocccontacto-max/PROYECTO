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
