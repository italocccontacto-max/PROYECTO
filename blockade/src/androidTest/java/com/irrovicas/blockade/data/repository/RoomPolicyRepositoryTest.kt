package com.irrovicas.blockade.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.irrovicas.blockade.data.local.db.BlockadeDatabase
import com.irrovicas.blockade.domain.model.BlockAction
import com.irrovicas.blockade.domain.model.BlockTarget
import com.irrovicas.blockade.domain.model.BlockadePolicy
import com.irrovicas.blockade.domain.model.PolicySource
import com.irrovicas.blockade.domain.model.StrictnessLevel
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomPolicyRepositoryTest {

    private lateinit var database: BlockadeDatabase
    private lateinit var repository: RoomPolicyRepository

    @Before
    fun setup() {
        val context = ApplicationProvider
            .getApplicationContext<Context>()

        database = Room.inMemoryDatabaseBuilder(
            context,
            BlockadeDatabase::class.java,
        ).build()

        repository = RoomPolicyRepository(
            database.policyDao(),
        )
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun saveAndRetrievePolicy() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-1",
                name = "Instagram focus",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.instagram.android",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
                strictness = StrictnessLevel.NORMAL,
                expiresAt = Instant.parse(
                    "2026-08-23T22:30:00Z",
                ),
            )

            repository.savePolicy(policy)

            val stored = repository.getPolicy("quick-1")

            assertEquals(policy.id, stored?.id)
            assertEquals(policy.name, stored?.name)
            assertEquals(policy.targets, stored?.targets)
            assertEquals(policy.actions, stored?.actions)
            assertEquals(policy.expiresAt, stored?.expiresAt)
        }
    }

    @Test
    fun observePoliciesReturnsSavedPolicy() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-2",
                name = "Focus",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.youtube.android",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
            )

            repository.savePolicy(policy)

            val policies = repository
                .observePolicies()
                .first()

            assertEquals(1, policies.size)
            assertEquals("quick-2", policies.single().id)
        }
    }

    @Test
    fun disablingPolicyIsPersisted() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-3",
                name = "Disable test",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.example.app",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
            )

            repository.savePolicy(policy)
            repository.setEnabled("quick-3", false)

            val stored = repository.getPolicy("quick-3")

            assertEquals(false, stored?.enabled)
        }
    }

    @Test
    fun deletingPolicyRemovesIt() {
        runBlocking {
            val policy = BlockadePolicy(
                id = "quick-4",
                name = "Delete test",
                source = PolicySource.QUICK_BLOCK,
                enabled = true,
                paused = false,
                targets = setOf(
                    BlockTarget.Application(
                        "com.example.app",
                    ),
                ),
                conditions = emptyList(),
                actions = setOf(BlockAction.LAUNCH),
            )

            repository.savePolicy(policy)
            repository.deletePolicy("quick-4")

            val stored = repository.getPolicy("quick-4")

            assertEquals(null, stored)
        }
    }
}
