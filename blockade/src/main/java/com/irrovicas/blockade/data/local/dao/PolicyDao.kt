package com.irrovicas.blockade.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.irrovicas.blockade.data.local.entity.ActionEntity
import com.irrovicas.blockade.data.local.entity.ConditionEntity
import com.irrovicas.blockade.data.local.entity.PolicyEntity
import com.irrovicas.blockade.data.local.entity.PolicyWithRelations
import com.irrovicas.blockade.data.local.entity.TargetEntity
import kotlinx.coroutines.flow.Flow

@Dao
abstract class PolicyDao {

    @Transaction
    @Query(
        """
        SELECT * 
        FROM blockade_policies
        ORDER BY id ASC
        """,
    )
    abstract fun observePolicies(): Flow<List<PolicyWithRelations>>

    @Transaction
    @Query(
        """
        SELECT *
        FROM blockade_policies
        WHERE id = :id
        LIMIT 1
        """,
    )
    abstract suspend fun getPolicy(
        id: String,
    ): PolicyWithRelations?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertPolicy(
        policy: PolicyEntity,
    )

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertTargets(
        targets: List<TargetEntity>,
    )

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertConditions(
        conditions: List<ConditionEntity>,
    )

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    protected abstract suspend fun insertActions(
        actions: List<ActionEntity>,
    )

    @Query(
        "DELETE FROM blockade_targets WHERE policyId = :policyId",
    )
    protected abstract suspend fun deleteTargets(
        policyId: String,
    )

    @Query(
        "DELETE FROM blockade_conditions WHERE policyId = :policyId",
    )
    protected abstract suspend fun deleteConditions(
        policyId: String,
    )

    @Query(
        "DELETE FROM blockade_actions WHERE policyId = :policyId",
    )
    protected abstract suspend fun deleteActions(
        policyId: String,
    )

    @Query(
        "DELETE FROM blockade_policies WHERE id = :policyId",
    )
    protected abstract suspend fun deletePolicy(
        policyId: String,
    )

    @Transaction
    open suspend fun replacePolicy(
        policy: PolicyEntity,
        targets: List<TargetEntity>,
        conditions: List<ConditionEntity>,
        actions: List<ActionEntity>,
    ) {
        deleteTargets(policy.id)
        deleteConditions(policy.id)
        deleteActions(policy.id)

        insertPolicy(policy)
        insertTargets(targets)
        insertConditions(conditions)
        insertActions(actions)
    }

    @Transaction
    open suspend fun deletePolicyAndChildren(
        policyId: String,
    ) {
        deleteTargets(policyId)
        deleteConditions(policyId)
        deleteActions(policyId)
        deletePolicy(policyId)
    }

    @Query(
        """
        UPDATE blockade_policies
        SET enabled = :enabled
        WHERE id = :id
        """,
    )
    abstract suspend fun setEnabled(
        id: String,
        enabled: Boolean,
    )

    @Query(
        """
        UPDATE blockade_policies
        SET paused = :paused
        WHERE id = :id
        """,
    )
    abstract suspend fun setPaused(
        id: String,
        paused: Boolean,
    )
}
