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
