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
    fun `create quick block is observed and blocks target`() {
        runBlocking {
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
    }

    @Test
    fun `stop quick block disables and allows access`() {
        runBlocking {
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
    }

    @Test
    fun `expired quick block does not block`() {
        runBlocking {
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
    }

    @Test
    fun `saved quick block persists and can be retrieved`() {
        runBlocking {
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
}
