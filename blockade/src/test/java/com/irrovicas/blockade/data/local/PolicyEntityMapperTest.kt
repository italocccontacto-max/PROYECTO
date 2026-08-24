package com.irrovicas.blockade.data.local

import com.irrovicas.blockade.data.local.entity.PolicyWithRelations
import com.irrovicas.blockade.data.local.mapper.PolicyEntityMapper
import com.irrovicas.blockade.domain.model.AppContentType
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockCondition
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.ConditionMode
import com.irrovicas.blockade.domain.model.KeywordMatchingMode
import com.irrovicas.blockade.domain.model.LocationMode
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.StrictnessLevel
import com.irrovicas.blockade.domain.model.UsageScope
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

class PolicyEntityMapperTest {

    @Test
    fun `policy survives domain to entity and back`() {
        val original = BlockadePolicy(
            id = "policy-1",
            name = "Test policy",
            source = PolicySource.SCHEDULE,
            enabled = true,
            paused = false,
            targets = setOf(
                BlockTarget.Application(
                    "com.instagram.android",
                ),
                BlockTarget.WebDomain(
                    "example.com",
                ),
                BlockTarget.Keyword(
                    value = "reels",
                    matchingMode = KeywordMatchingMode.URL_ANYWHERE,
                ),
                BlockTarget.AppContent(
                    packageName = "com.instagram.android",
                    contentType = AppContentType.INSTAGRAM_REELS,
                ),
            ),
            conditions = listOf(
                BlockCondition.TimeWindow(
                    startTime = LocalTime.of(22, 0),
                    endTime = LocalTime.of(2, 0),
                    daysOfWeek = setOf(
                        DayOfWeek.SUNDAY,
                    ),
                ),
                BlockCondition.UsageLimit(
                    limitMinutes = 30,
                    scope = UsageScope.DAILY,
                ),
                BlockCondition.LaunchCount(
                    maximumLaunches = 5,
                    scope = UsageScope.SCHEDULE_WINDOW,
                ),
                BlockCondition.Location(
                    latitude = -12.0464,
                    longitude = -77.0428,
                    radiusMeters = 100f,
                    mode = LocationMode.INSIDE,
                ),
                BlockCondition.Wifi(
                    ssid = "IRROVICAS-HOME",
                ),
            ),
            actions = setOf(
                BlockAction.LAUNCH,
                BlockAction.NOTIFICATION,
            ),
            conditionMode = ConditionMode.ALL,
            strictness = StrictnessLevel.STRICT,
            expiresAt = Instant.parse(
                "2026-08-24T00:00:00Z",
            ),
        )

        val persisted = PolicyEntityMapper.toEntities(original)

        val restored = PolicyEntityMapper.toDomain(
            PolicyWithRelations(
                policy = persisted.policy,
                targets = persisted.targets,
                conditions = persisted.conditions,
                actions = persisted.actions,
            ),
        )

        assertEquals(original.id, restored.id)
        assertEquals(original.name, restored.name)
        assertEquals(original.source, restored.source)
        assertEquals(original.enabled, restored.enabled)
        assertEquals(original.paused, restored.paused)
        assertEquals(original.targets, restored.targets)
        assertEquals(original.conditions, restored.conditions)
        assertEquals(original.actions, restored.actions)
        assertEquals(original.conditionMode, restored.conditionMode)
        assertEquals(original.strictness, restored.strictness)
        assertEquals(original.expiresAt, restored.expiresAt)

        assertNotNull(restored)
    }
}
