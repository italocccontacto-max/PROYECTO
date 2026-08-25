package com.irrovicas.blockade.platform.enforcement

import com.irrovicas.blockade.domain.engine.EnforcementDecision
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BlockEnforcementActionResolverTest {

    private val target = BlockTarget.Application("com.example.blocked")

    @Test
    fun `does not enforce when decision is Allow`() {
        val result =
            BlockEnforcementActionResolver.shouldEnforce(
                EnforcementDecision.Allow,
            )

        assertFalse(result)
    }

    @Test
    fun `enforces when Block includes LAUNCH`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.LAUNCH),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertTrue(result)
    }

    @Test
    fun `enforces when Block includes FULL`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.FULL),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertTrue(result)
    }

    @Test
    fun `does not enforce when Block only includes NOTIFICATION`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.NOTIFICATION),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertFalse(result)
    }

    @Test
    fun `enforces when Block includes LAUNCH and NOTIFICATION together`() {
        val decision = EnforcementDecision.Block(
            target = target,
            actions = setOf(BlockAction.LAUNCH, BlockAction.NOTIFICATION),
            policyIds = setOf("policy-1"),
            reason = "test",
        )

        val result = BlockEnforcementActionResolver.shouldEnforce(decision)

        assertTrue(result)
    }
}
