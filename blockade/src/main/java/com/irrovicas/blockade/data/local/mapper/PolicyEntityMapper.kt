package com.irrovicas.blockade.data.local.mapper

import com.irrovicas.blockade.data.local.entity.ActionEntity
import com.irrovicas.blockade.data.local.entity.ConditionEntity
import com.irrovicas.blockade.data.local.entity.PolicyEntity
import com.irrovicas.blockade.data.local.entity.PolicyWithRelations
import com.irrovicas.blockade.data.local.entity.TargetEntity
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

object PolicyEntityMapper {

    fun toEntities(
        policy: BlockadePolicy,
    ): PersistedPolicy {
        val policyEntity = PolicyEntity(
            id = policy.id,
            name = policy.name,
            source = policy.source.name,
            enabled = policy.enabled,
            paused = policy.paused,
            conditionMode = policy.conditionMode.name,
            strictness = policy.strictness.name,
            expiresAtEpochMillis = policy.expiresAt?.toEpochMilli(),
        )

        val targets = policy.targets.map { target ->
            target.toEntity(policy.id)
        }

        val conditions = policy.conditions.map { condition ->
            condition.toEntity(policy.id)
        }

        val actions = policy.actions.map { action ->
            ActionEntity(
                policyId = policy.id,
                action = action.name,
            )
        }

        return PersistedPolicy(
            policy = policyEntity,
            targets = targets,
            conditions = conditions,
            actions = actions,
        )
    }

    fun toDomain(
        aggregate: PolicyWithRelations,
    ): BlockadePolicy {
        return BlockadePolicy(
            id = aggregate.policy.id,
            name = aggregate.policy.name,
            source = PolicySource.valueOf(aggregate.policy.source),
            enabled = aggregate.policy.enabled,
            paused = aggregate.policy.paused,
            targets = aggregate.targets.map { it.toDomain() }.toSet(),
            conditions = aggregate.conditions.map { it.toDomain() },
            actions = aggregate.actions.map {
                BlockAction.valueOf(it.action)
            }.toSet(),
            conditionMode = ConditionMode.valueOf(
                aggregate.policy.conditionMode,
            ),
            strictness = StrictnessLevel.valueOf(
                aggregate.policy.strictness,
            ),
            expiresAt = aggregate.policy.expiresAtEpochMillis
                ?.let(Instant::ofEpochMilli),
        )
    }

    private fun BlockTarget.toEntity(
        policyId: String,
    ): TargetEntity {
        return when (this) {
            is BlockTarget.Application ->
                TargetEntity(
                    policyId = policyId,
                    type = "APPLICATION",
                    value = packageName,
                    matchingMode = null,
                    contentType = null,
                )

            is BlockTarget.WebDomain ->
                TargetEntity(
                    policyId = policyId,
                    type = "WEB_DOMAIN",
                    value = domain,
                    matchingMode = null,
                    contentType = null,
                )

            is BlockTarget.Keyword ->
                TargetEntity(
                    policyId = policyId,
                    type = "KEYWORD",
                    value = value,
                    matchingMode = matchingMode.name,
                    contentType = null,
                )

            is BlockTarget.AppContent ->
                TargetEntity(
                    policyId = policyId,
                    type = "APP_CONTENT",
                    value = packageName,
                    matchingMode = null,
                    contentType = contentType.name,
                )
        }
    }

    private fun TargetEntity.toDomain(): BlockTarget {
        return when (type) {
            "APPLICATION" ->
                BlockTarget.Application(value)

            "WEB_DOMAIN" ->
                BlockTarget.WebDomain(value)

            "KEYWORD" ->
                BlockTarget.Keyword(
                    value = value,
                    matchingMode = KeywordMatchingMode.valueOf(
                        requireNotNull(matchingMode),
                    ),
                )

            "APP_CONTENT" ->
                BlockTarget.AppContent(
                    packageName = value,
                    contentType = AppContentType.valueOf(
                        requireNotNull(contentType),
                    ),
                )

            else -> error("Unknown target type: $type")
        }
    }

    private fun BlockCondition.toEntity(
        policyId: String,
    ): ConditionEntity {
        return when (this) {
            is BlockCondition.TimeWindow ->
                ConditionEntity(
                    policyId = policyId,
                    type = "TIME_WINDOW",
                    startTime = startTime.toString(),
                    endTime = endTime.toString(),
                    daysOfWeek = daysOfWeek
                        .sortedBy(DayOfWeek::getValue)
                        .joinToString(",") { it.name },
                    limitMinutes = null,
                    usageScope = null,
                    maximumLaunches = null,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = null,
                )

            is BlockCondition.UsageLimit ->
                ConditionEntity(
                    policyId = policyId,
                    type = "USAGE_LIMIT",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = limitMinutes,
                    usageScope = scope.name,
                    maximumLaunches = null,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = null,
                )

            is BlockCondition.LaunchCount ->
                ConditionEntity(
                    policyId = policyId,
                    type = "LAUNCH_COUNT",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = null,
                    usageScope = scope.name,
                    maximumLaunches = maximumLaunches,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = null,
                )

            is BlockCondition.Location ->
                ConditionEntity(
                    policyId = policyId,
                    type = "LOCATION",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = null,
                    usageScope = null,
                    maximumLaunches = null,
                    latitude = latitude,
                    longitude = longitude,
                    radiusMeters = radiusMeters,
                    locationMode = mode.name,
                    ssid = null,
                )

            is BlockCondition.Wifi ->
                ConditionEntity(
                    policyId = policyId,
                    type = "WIFI",
                    startTime = null,
                    endTime = null,
                    daysOfWeek = null,
                    limitMinutes = null,
                    usageScope = null,
                    maximumLaunches = null,
                    latitude = null,
                    longitude = null,
                    radiusMeters = null,
                    locationMode = null,
                    ssid = ssid,
                )
        }
    }

    private fun ConditionEntity.toDomain(): BlockCondition {
        return when (type) {
            "TIME_WINDOW" ->
                BlockCondition.TimeWindow(
                    startTime = LocalTime.parse(
                        requireNotNull(startTime),
                    ),
                    endTime = LocalTime.parse(
                        requireNotNull(endTime),
                    ),
                    daysOfWeek = requireNotNull(daysOfWeek)
                        .split(',')
                        .filter(String::isNotBlank)
                        .map(DayOfWeek::valueOf)
                        .toSet(),
                )

            "USAGE_LIMIT" ->
                BlockCondition.UsageLimit(
                    limitMinutes = requireNotNull(limitMinutes),
                    scope = UsageScope.valueOf(
                        requireNotNull(usageScope),
                    ),
                )

            "LAUNCH_COUNT" ->
                BlockCondition.LaunchCount(
                    maximumLaunches = requireNotNull(maximumLaunches),
                    scope = UsageScope.valueOf(
                        requireNotNull(usageScope),
                    ),
                )

            "LOCATION" ->
                BlockCondition.Location(
                    latitude = requireNotNull(latitude),
                    longitude = requireNotNull(longitude),
                    radiusMeters = requireNotNull(radiusMeters),
                    mode = LocationMode.valueOf(
                        requireNotNull(locationMode),
                    ),
                )

            "WIFI" ->
                BlockCondition.Wifi(
                    ssid = requireNotNull(ssid),
                )

            else -> error("Unknown condition type: $type")
        }
    }
}

data class PersistedPolicy(
    val policy: PolicyEntity,
    val targets: List<TargetEntity>,
    val conditions: List<ConditionEntity>,
    val actions: List<ActionEntity>,
)
